import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import '../../config/app_constants.dart';
import '../../models/song.dart';
import '../../models/download_task.dart';
import '../storage/storage_service.dart';
import '../netease/music_service.dart';
import '../netease/lyric_service.dart';
import 'id3_tagger.dart';
import 'lyric_writer.dart';

/// 下载任务状态变更回调函数签名
typedef DownloadStatusListener = void Function(DownloadTask task);

/// 核心下载服务管理器
/// 负责任务并发队列调度、单曲多线程分块下载加速、音频直链解析、ID3 标签写入以及 LRC 歌词同步
class DownloadService {
  final StorageService _storage = StorageService.instance;
  final NeteaseMusicService _musicService = NeteaseMusicService.instance;
  final NeteaseLyricService _lyricService = NeteaseLyricService.instance;
  late final Dio _dio;

  /// 所有维护的下载任务队列列表
  final List<DownloadTask> _tasks = [];

  /// 正在活跃下载中的 CancelToken 映射
  final Map<String, CancelToken> _cancelTokens = {};

  /// 状态变更全局监听回调列表
  final List<DownloadStatusListener> _listeners = [];

  /// 定时刷新下载速度和进度的计时器
  Timer? _ticker;

  /// 单例实例
  static final DownloadService instance = DownloadService._internal();

  DownloadService._internal() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );

    // 提高每主机的并发连接数上限，防止多任务与分块下载时被客户端内部限流超时
    if (_dio.httpClientAdapter is IOHttpClientAdapter) {
      (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.maxConnectionsPerHost = 64;
        client.connectionTimeout = const Duration(seconds: 15);
        return client;
      };
    }
  }

  /// 获取当前所有任务的只读列表
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  /// 添加任务状态监听器
  void addListener(DownloadStatusListener listener) {
    _listeners.add(listener);
  }

  /// 移除任务状态监听器
  void removeListener(DownloadStatusListener listener) {
    _listeners.remove(listener);
  }

  /// 广播通知监听器（使用副本遍历避免迭代中增删抛出 Concurrent modification）
  void _notify(DownloadTask task) {
    for (final listener in List<DownloadStatusListener>.of(_listeners)) {
      try {
        listener(task);
      } catch (_) {}
    }
  }

  /// 仅在有活跃下载任务时动态启动刷新定时器
  void _ensureTickerStarted() {
    _ticker ??= Timer.periodic(const Duration(milliseconds: 500), (_) {
      final hasActive = _tasks.any((t) => t.status == DownloadStatus.downloading);
      if (!hasActive) {
        _stopTicker();
        return;
      }
      for (final t in _tasks) {
        if (t.status == DownloadStatus.downloading) {
          _notify(t);
        }
      }
    });
  }

  /// 停止刷新计时器
  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// 添加单曲下载任务至队列
  ///
  /// [song] 目标歌曲
  /// [quality] 指定音质等级（若为空则使用用户默认设置）
  /// [targetDirectory] 指定存储目录（若为空则使用用户默认配置）
  Future<DownloadTask> enqueueSong(
    Song song, {
    String? quality,
    String? targetDirectory,
  }) async {
    final effectiveQuality = quality ?? _storage.getAudioRate();
    final effectiveDir = targetDirectory ?? await _storage.getDownloadDirectory();
    final template = _storage.getFileNameTemplate();

    // 解析出安全文件名
    final baseFileName = _buildSafeFileName(song, template);
    final taskId = '${song.id}_$effectiveQuality';

    // 检查是否已在队列中
    final existing = _tasks.where((t) => t.id == taskId).firstOrNull;
    if (existing != null) {
      if (existing.status == DownloadStatus.failed ||
          existing.status == DownloadStatus.paused ||
          existing.status == DownloadStatus.cancelled) {
        resumeTask(existing);
      }
      return existing;
    }

    final task = DownloadTask(
      id: taskId,
      song: song,
      qualityLevel: effectiveQuality,
      targetDirectory: effectiveDir,
      fileName: '$baseFileName.mp3', // 初始默认 mp3，后续解析真实类型后修正
    );

    _tasks.add(task);
    _notify(task);
    _scheduleQueue();

    return task;
  }

  /// 添加单曲下载并等待其下载完成（供同步等高级流程调度使用）
  Future<DownloadTask> downloadSongAndWait(
    Song song, {
    String? quality,
    String? targetDirectory,
  }) async {
    final task = await enqueueSong(
      song,
      quality: quality,
      targetDirectory: targetDirectory,
    );
    if (task.status == DownloadStatus.completed || task.status == DownloadStatus.failed) {
      return task;
    }
    final completer = Completer<DownloadTask>();
    void listener(DownloadTask updated) {
      if (updated.id == task.id) {
        if (updated.status == DownloadStatus.completed || updated.status == DownloadStatus.failed) {
          removeListener(listener);
          if (!completer.isCompleted) completer.complete(updated);
        }
      }
    }
    addListener(listener);
    return completer.future;
  }

  /// 批量添加歌曲到下载队列
  Future<List<DownloadTask>> enqueueSongs(
    List<Song> songs, {
    String? quality,
    String? targetDirectory,
  }) async {
    final createdList = <DownloadTask>[];
    for (final song in songs) {
      final task = await enqueueSong(
        song,
        quality: quality,
        targetDirectory: targetDirectory,
      );
      createdList.add(task);
    }
    return createdList;
  }

  /// 调度下载队列，维持在最大并发量内自动运行
  void _scheduleQueue() {
    final maxConcurrent = _storage.getMaxConcurrentDownloads();
    final activeCount = _tasks.where((t) =>
        t.status == DownloadStatus.downloading ||
        t.status == DownloadStatus.tagging ||
        t.status == DownloadStatus.lyrics).length;

    if (activeCount >= maxConcurrent) return;

    final pendingTasks = _tasks.where((t) => t.status == DownloadStatus.pending).toList();
    final slotsAvailable = maxConcurrent - activeCount;

    for (int i = 0; i < slotsAvailable && i < pendingTasks.length; i++) {
      _startTask(pendingTasks[i]);
    }
  }

  /// 启动单个下载任务执行 (支持单曲多线程分块下载)
  Future<void> _startTask(DownloadTask task) async {
    if (task.status != DownloadStatus.pending) return;

    task.status = DownloadStatus.downloading;
    task.errorMessage = null;
    _ensureTickerStarted();
    _notify(task);

    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    int lastBytes = 0;
    DateTime lastTime = DateTime.now();

    try {
      // 1. 获取网易云音频下载直链
      final urlInfo = await _musicService.getSongUrlInfo(
        songId: task.song.id,
        level: task.qualityLevel,
      );

      if (urlInfo == null || urlInfo['url'] == null || urlInfo['url'].toString().isEmpty) {
        throw Exception('无法解析音频下载链接，歌曲可能受版权或会员权益限制');
      }

      final downloadUrl = urlInfo['url'].toString();
      final ext = (urlInfo['type']?.toString().toLowerCase() ?? 'mp3');
      task.downloadUrl = downloadUrl;
      task.fileExtension = ext;

      // 修正完整文件名后缀
      final template = _storage.getFileNameTemplate();
      final baseFileName = _buildSafeFileName(task.song, template);
      final finalFileName = '$baseFileName.$ext';
      final finalFilePath = '${task.targetDirectory}/$finalFileName';

      // 确保下载目录存在
      final dir = Directory(task.targetDirectory);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 获取文件总大小
      int totalBytes = (urlInfo['size'] is int) ? urlInfo['size'] as int : 0;
      if (totalBytes <= 0) {
        try {
          final headRes = await _dio.head(
            downloadUrl,
            options: Options(headers: AppConstants.neteaseImageHeaders),
          );
          final cl = headRes.headers.value('content-length');
          if (cl != null) totalBytes = int.tryParse(cl) ?? 0;
        } catch (_) {}
      }

      final singleSongThreads = _storage.getSingleSongThreads();

      // 回调闭包：计算总体实时进度与速度
      void onProgressUpdate(int received, int total) {
        task.receivedBytes = received;
        task.totalBytes = total;
        if (total > 0) {
          task.progress = (received / total).clamp(0.0, 1.0);
        }

        final now = DateTime.now();
        final elapsed = now.difference(lastTime).inMilliseconds;
        if (elapsed >= 500) {
          final diffBytes = received - lastBytes;
          task.speedBytesPerSec = (diffBytes / (elapsed / 1000));
          lastBytes = received;
          lastTime = now;
        }
      }

      // 2. 根据用户设置选择：单曲多线程分块下载 或 原生单连接下载
      if (singleSongThreads > 1 && totalBytes > 256 * 1024) {
        await _downloadMultiThreaded(
          task: task,
          url: downloadUrl,
          targetPath: finalFilePath,
          totalBytes: totalBytes,
          threads: singleSongThreads,
          cancelToken: cancelToken,
          onProgress: onProgressUpdate,
        );
      } else {
        await _downloadSingleThreaded(
          url: downloadUrl,
          targetPath: finalFilePath,
          cancelToken: cancelToken,
          onProgress: onProgressUpdate,
        );
      }

      // 3. 写入 ID3 / 元数据标签
      if (_storage.getWriteMetadata()) {
        task.status = DownloadStatus.tagging;
        _notify(task);

        Uint8List? coverBytes;
        if (task.song.albumCoverUrl.isNotEmpty) {
          try {
            final coverRes = await _dio.get<List<int>>(
              task.song.albumCoverUrl,
              options: Options(
                headers: AppConstants.neteaseImageHeaders,
                responseType: ResponseType.bytes,
              ),
            );
            if (coverRes.data != null) {
              coverBytes = Uint8List.fromList(coverRes.data!);
            }
          } catch (_) {}
        }

        await Id3Tagger.writeTags(
          filePath: finalFilePath,
          song: task.song,
          coverBytes: coverBytes,
        );
      }

      // 4. 获取并写入歌词文件 (.lrc)
      if (_storage.getDownloadLyrics()) {
        task.status = DownloadStatus.lyrics;
        _notify(task);

        final lrc = await _lyricService.getFormattedLrc(
          songId: task.song.id,
          includeTranslation: _storage.getDownloadTranslation(),
        );

        if (lrc != null && lrc.trim().isNotEmpty) {
          await LyricWriter.writeLrcFile(finalFilePath, lrc);
        }
      }

      // 5. 标记完成
      task.status = DownloadStatus.completed;
      task.progress = 1.0;
      task.speedBytesPerSec = 0.0;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        task.status = DownloadStatus.paused;
      } else {
        task.status = DownloadStatus.failed;
        task.errorMessage = '网络下载错误: ${e.message}';
      }
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _cancelTokens.remove(task.id);
      _notify(task);
      _scheduleQueue(); // 自动调度下一个任务
    }
  }

  /// 单首歌曲多线程 Range 分块加速下载（严格校验切片与完整性，任何异常自动单线程重试）
  Future<void> _downloadMultiThreaded({
    required DownloadTask task,
    required String url,
    required String targetPath,
    required int totalBytes,
    required int threads,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
  }) async {
    final actualThreads = min(threads, max(1, totalBytes ~/ (128 * 1024)));
    final chunkSize = (totalBytes / actualThreads).ceil();

    final downloadedPerChunk = List<int>.filled(actualThreads, 0);
    final partFiles = <File>[];
    final tempMergedFile = File('$targetPath.tmp');

    try {
      final futures = <Future<void>>[];

      for (int i = 0; i < actualThreads; i++) {
        final start = i * chunkSize;
        final end = min((i + 1) * chunkSize - 1, totalBytes - 1);
        final expectedLen = end - start + 1;
        final partFile = File('$targetPath.part_$i');
        partFiles.add(partFile);

        final chunkIndex = i;
        futures.add(() async {
          final res = await _dio.get<List<int>>(
            url,
            cancelToken: cancelToken,
            options: Options(
              headers: {
                ...AppConstants.neteaseImageHeaders,
                'Range': 'bytes=$start-$end',
              },
              responseType: ResponseType.bytes,
            ),
            onReceiveProgress: (chunkReceived, _) {
              downloadedPerChunk[chunkIndex] = chunkReceived;
              final totalDownloaded = downloadedPerChunk.reduce((a, b) => a + b);
              onProgress(totalDownloaded, totalBytes);
            },
          );

          // 核心校验：服务端必须返回 206 Partial Content，且切片长度必须与预期严格一致
          if (res.statusCode != 206 || res.data == null || res.data!.length != expectedLen) {
            throw Exception('切片 $chunkIndex 响应异常 (status: ${res.statusCode}, len: ${res.data?.length}, expected: $expectedLen)');
          }

          await partFile.writeAsBytes(res.data!, flush: true);
          downloadedPerChunk[chunkIndex] = res.data!.length;
          final totalDownloaded = downloadedPerChunk.reduce((a, b) => a + b);
          onProgress(totalDownloaded, totalBytes);
        }());
      }

      await Future.wait(futures);

      // 全部切片下载无误，先合并到 .tmp 临时文件并校验文件大小
      final sink = tempMergedFile.openWrite();
      for (final pf in partFiles) {
        if (!await pf.exists()) {
          throw Exception('部分切片文件丢失，合并终止');
        }
        await sink.addStream(pf.openRead());
      }
      await sink.close();

      // 严格校验合并后的临时文件完整性
      final mergedLen = await tempMergedFile.length();
      if (mergedLen != totalBytes) {
        throw Exception('合并文件长度异常: 实际 $mergedLen, 预期 $totalBytes');
      }

      // 原子重命名为目标文件
      final finalFile = File(targetPath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tempMergedFile.rename(targetPath);

      // 清理临时切片
      for (final pf in partFiles) {
        if (await pf.exists()) {
          try { await pf.delete(); } catch (_) {}
        }
      }
    } catch (e) {
      // 若多线程分块下载失败，彻底清理切片与临时文件
      for (final pf in partFiles) {
        if (await pf.exists()) {
          try { await pf.delete(); } catch (_) {}
        }
      }
      if (await tempMergedFile.exists()) {
        try { await tempMergedFile.delete(); } catch (_) {}
      }

      if (cancelToken.isCancelled) rethrow;

      // 降级回退至稳妥的原生单连接流式下载
      await _downloadSingleThreaded(
        url: url,
        targetPath: targetPath,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
    }
  }

  /// 原生单连接流式下载（采用 .tmp 缓冲后原子重命名，防止半截损坏文件破坏目标路径）
  Future<void> _downloadSingleThreaded({
    required String url,
    required String targetPath,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
  }) async {
    final tempFile = File('$targetPath.tmp');
    try {
      await _dio.download(
        url,
        tempFile.path,
        cancelToken: cancelToken,
        options: Options(headers: AppConstants.neteaseImageHeaders),
        onReceiveProgress: onProgress,
      );

      final finalFile = File(targetPath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tempFile.rename(targetPath);
    } catch (e) {
      if (await tempFile.exists()) {
        try { await tempFile.delete(); } catch (_) {}
      }
      rethrow;
    }
  }

  /// 暂停任务
  void pauseTask(DownloadTask task) {
    if (task.status == DownloadStatus.downloading) {
      _cancelTokens[task.id]?.cancel();
      task.status = DownloadStatus.paused;
      task.speedBytesPerSec = 0.0;
      _notify(task);
      _scheduleQueue();
    } else if (task.status == DownloadStatus.pending) {
      task.status = DownloadStatus.paused;
      _notify(task);
    }
  }

  /// 恢复任务
  void resumeTask(DownloadTask task) {
    if (task.status == DownloadStatus.paused ||
        task.status == DownloadStatus.failed ||
        task.status == DownloadStatus.cancelled) {
      task.status = DownloadStatus.pending;
      task.errorMessage = null;
      _notify(task);
      _scheduleQueue();
    }
  }

  /// 重试失败任务
  void retryTask(DownloadTask task) {
    resumeTask(task);
  }

  /// 取消并移除任务
  void cancelTask(DownloadTask task) {
    _cancelTokens[task.id]?.cancel();
    _cancelTokens.remove(task.id);
    _tasks.remove(task);
    _notify(task);
    _scheduleQueue();
  }

  /// 清理已完成的任务项
  void clearCompleted() {
    _tasks.removeWhere((t) => t.status == DownloadStatus.completed);
    for (final listener in List<DownloadStatusListener>.of(_listeners)) {
      try {
        if (_tasks.isNotEmpty) {
          listener(_tasks.first);
        }
      } catch (_) {}
    }
  }

  /// 全部暂停
  void pauseAll() {
    for (final t in _tasks) {
      if (t.status == DownloadStatus.downloading || t.status == DownloadStatus.pending) {
        pauseTask(t);
      }
    }
  }

  /// 全部恢复
  void resumeAll() {
    for (final t in _tasks) {
      if (t.status == DownloadStatus.paused || t.status == DownloadStatus.failed) {
        resumeTask(t);
      }
    }
  }

  /// 生成合法安全的文件名
  String _buildSafeFileName(Song song, String template) {
    var result = template
        .replaceAll(AppConstants.placeholderSinger, song.artistStringForFileName)
        .replaceAll(AppConstants.placeholderSongName, song.name)
        .replaceAll(AppConstants.placeholderAlbum, song.albumName.isEmpty ? '单曲' : song.albumName)
        .replaceAll(AppConstants.placeholderIndex, song.trackNumber.toString().padLeft(2, '0'))
        .replaceAll(AppConstants.placeholderSongId, song.id);

    // 过滤 Windows/Linux/macOS 文件名非法字符: \ / : * ? " < > |
    result = result.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (result.isEmpty) {
      result = 'song_${song.id}';
    }
    return result;
  }
}