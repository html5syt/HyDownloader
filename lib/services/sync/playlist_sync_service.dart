import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../models/song.dart';
import '../../models/sync_item.dart';
import '../../models/download_task.dart';
import '../storage/storage_service.dart';
import '../netease/music_service.dart';
import '../download/download_service.dart';

/// 歌单与本地文件对比和同步核心服务
/// 实现：在线歌单与多个不同速率本地文件夹（如 SSD/本地磁盘与外置U盘）智能双向对比、
/// 跨盘本地复用免重复下载、首份极速落盘后台异步分发、以及多余曲目安全清理
class PlaylistSyncService {
  final NeteaseMusicService _musicService = NeteaseMusicService.instance;
  final DownloadService _downloadService = DownloadService.instance;
  final StorageService _storage = StorageService.instance;

  /// 支持的本地音频文件扩展名
  static const Set<String> supportedAudioExtensions = {
    '.mp3',
    '.flac',
    '.m4a',
    '.wav',
    '.ogg',
    '.aac',
    '.ape',
  };

  /// 单例实例
  static final PlaylistSyncService instance = PlaylistSyncService._internal();
  PlaylistSyncService._internal();

  /// 对比在线歌单与多个本地文件夹的歌曲差异
  ///
  /// [playlistId] 在线歌单 ID
  /// [localFolderPaths] 选定的一个或多个本地文件夹路径（可能包含固态硬盘与慢速U盘）
  Future<List<SyncItem>> comparePlaylistWithLocalFolders({
    required String playlistId,
    required List<String> localFolderPaths,
  }) async {
    // 1. 获取在线歌单完整歌曲列表
    final onlineSongs = await _musicService.getPlaylistSongs(playlistId);

    // 2. 为每一个选定的本地目录分别建立文件与指纹索引
    final folderFileMaps = <String, Map<String, File>>{};
    final folderFilesList = <String, List<File>>{};

    for (final folderPath in localFolderPaths) {
      final dir = Directory(folderPath);
      final fileMap = <String, File>{};
      final files = <File>[];

      if (await dir.exists()) {
        try {
          final entries = await dir.list(recursive: false).toList();
          for (final entity in entries) {
            if (entity is File) {
              final ext = p.extension(entity.path).toLowerCase();
              if (supportedAudioExtensions.contains(ext)) {
                files.add(entity);
                final baseName = p.basenameWithoutExtension(entity.path);
                fileMap[_normalizeText(baseName)] = entity;
              }
            }
          }
        } catch (_) {}
      }

      folderFileMaps[folderPath] = fileMap;
      folderFilesList[folderPath] = files;
    }

    final matchedLocalFilesSet = <String>{};
    final resultItems = <SyncItem>[];

    // 3. 逐首对比在线歌曲在各个本地文件夹中的分布情况
    for (final song in onlineSongs) {
      final existingFolders = <String, File>{};
      final missingFolders = <String>[];

      for (final folderPath in localFolderPaths) {
        final fMap = folderFileMaps[folderPath] ?? {};
        final matchedFile = _findMatchingLocalFile(song, fMap);
        if (matchedFile != null) {
          existingFolders[folderPath] = matchedFile;
          matchedLocalFilesSet.add(matchedFile.path);
        } else {
          missingFolders.add(folderPath);
        }
      }

      if (missingFolders.isEmpty) {
        // 情况 A: 所有选中的磁盘文件夹均已拥有此歌曲
        resultItems.add(SyncItem(
          id: 'matched_${song.id}',
          type: SyncDifferenceType.matched,
          song: song,
          localFilePath: existingFolders.values.first.path,
          localFileName: p.basename(existingFolders.values.first.path),
          localDirectory: existingFolders.keys.first,
          targetDirectories: [],
          isSelected: false,
        ));
      } else if (existingFolders.isNotEmpty) {
        // 情况 B (需求 3): 部分磁盘已有该歌曲（例如本地电脑有，U盘缺失）
        // 策略：不从网络重复下载，直接在本地磁盘间极速复制！
        final sourceFile = existingFolders.values.first;
        resultItems.add(SyncItem(
          id: 'copy_${song.id}',
          type: SyncDifferenceType.copyFromLocal,
          song: song,
          sourceFilePath: sourceFile.path,
          localFileName: p.basename(sourceFile.path),
          targetDirectories: List.from(missingFolders),
          isSelected: true,
        ));
      } else {
        // 情况 C (需求 2): 本地所有磁盘均缺失该歌曲
        // 策略：优先从云端下载 1 份至首选磁盘，随后在后台本地拷贝分发至其他磁盘 (如慢速U盘)
        resultItems.add(SyncItem(
          id: 'missing_${song.id}',
          type: SyncDifferenceType.missingInLocal,
          song: song,
          targetDirectories: List.from(localFolderPaths),
          isSelected: true,
        ));
      }
    }

    // 4. 统计并找出在各个本地文件夹中属于“多余”的文件（即在线歌单中已被删除的曲目）
    for (final folderPath in localFolderPaths) {
      final files = folderFilesList[folderPath] ?? [];
      for (final f in files) {
        if (!matchedLocalFilesSet.contains(f.path)) {
          final fileName = p.basename(f.path);
          resultItems.add(SyncItem(
            id: 'extra_${f.path.hashCode}',
            type: SyncDifferenceType.extraInLocal,
            localFilePath: f.path,
            localFileName: fileName,
            localDirectory: folderPath,
            targetDirectories: [],
            isSelected: true,
          ));
        }
      }
    }

    return resultItems;
  }

  /// 在指定文件夹的文件映射中寻找与在线歌曲名称匹配的文件
  File? _findMatchingLocalFile(Song song, Map<String, File> localFileMap) {
    final songNameNorm = _normalizeText(song.name);
    final artistNorms = song.artists.map(_normalizeText).toList();

    for (final entry in localFileMap.entries) {
      final localNorm = entry.key;

      if (localNorm.contains(songNameNorm) || songNameNorm.contains(localNorm)) {
        if (artistNorms.isEmpty) return entry.value;
        for (final a in artistNorms) {
          if (localNorm.contains(a)) return entry.value;
        }
        if (songNameNorm.length >= 4) return entry.value;
      }
    }
    return null;
  }

  /// 字符串标准化：去除特殊字符、括号内容并转小写
  String _normalizeText(String input) {
    var s = input.toLowerCase();
    s = s.replaceAll(RegExp(r'\([^)]*\)'), '');
    s = s.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    s = s.replaceAll(RegExp(r'\{[^}]*\}'), '');
    s = s.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]'), '');
    return s.trim();
  }

  /// 执行同步操作（支持按照最大并发数进行多任务并行下载与分发，杜绝串行阻塞）
  Future<void> executeSync({
    required List<SyncItem> items,
    required String targetDownloadFolder,
    void Function(int completed, int total)? onProgress,
  }) async {
    final selectedItems = items.where((i) => i.isSelected).toList();
    if (selectedItems.isEmpty) return;

    final maxConcurrent = _storage.getMaxConcurrentDownloads();
    final queue = List<SyncItem>.from(selectedItems);
    int activeCount = 0;
    int doneCount = 0;
    final completer = Completer<void>();

    void processNext() {
      if (queue.isEmpty && activeCount == 0) {
        if (!completer.isCompleted) completer.complete();
        return;
      }

      while (activeCount < maxConcurrent && queue.isNotEmpty) {
        final item = queue.removeAt(0);
        activeCount++;
        item.executionStatus = 'syncing';

        _executeSingleSyncItem(item, targetDownloadFolder).then((_) {
          activeCount--;
          doneCount++;
          onProgress?.call(doneCount, selectedItems.length);
          processNext();
        }).catchError((e) {
          activeCount--;
          doneCount++;
          item.executionStatus = 'failed';
          item.executionMessage = '处理失败: $e';
          onProgress?.call(doneCount, selectedItems.length);
          processNext();
        });
      }
    }

    processNext();
    await completer.future;
  }

  /// 执行单个同步项的处理
  Future<void> _executeSingleSyncItem(SyncItem item, String targetDownloadFolder) async {
    if (item.type == SyncDifferenceType.copyFromLocal &&
        item.sourceFilePath != null &&
        item.targetDirectories.isNotEmpty) {
      // 策略 1: 本地直接拷贝，免网络下载
      final sourceFile = File(item.sourceFilePath!);
      if (await sourceFile.exists()) {
        final fileName = p.basename(sourceFile.path);
        final sourceLrc = File(p.setExtension(sourceFile.path, '.lrc'));
        final hasLrc = await sourceLrc.exists();

        for (final destDir in item.targetDirectories) {
          final dDir = Directory(destDir);
          if (!await dDir.exists()) await dDir.create(recursive: true);

          final destFilePath = p.join(destDir, fileName);
          await sourceFile.copy(destFilePath);

          if (hasLrc) {
            final destLrcPath = p.setExtension(destFilePath, '.lrc');
            await sourceLrc.copy(destLrcPath);
          }
        }

        item.executionStatus = 'completed';
        item.executionMessage = '已从已有磁盘直接拷贝至 ${item.targetDirectories.length} 个文件夹 (免下载)';
      } else {
        item.executionStatus = 'failed';
        item.executionMessage = '源文件不存在，无法进行本地拷贝';
      }
    } else if (item.type == SyncDifferenceType.missingInLocal &&
        item.song != null &&
        item.targetDirectories.isNotEmpty) {
      // 策略 2: 优先确保第 1 份文件在主盘下载完成，随后在后台本地拷贝分发至其他磁盘
      final primaryDir = item.targetDirectories.first;

      final task = await _downloadService.downloadSongAndWait(
        item.song!,
        targetDirectory: primaryDir,
      );

      if (task.status == DownloadStatus.completed) {
        final primaryFile = File(task.fullFilePath);

        if (item.targetDirectories.length > 1 && await primaryFile.exists()) {
          final fileName = p.basename(primaryFile.path);
          final primaryLrc = File(p.setExtension(primaryFile.path, '.lrc'));
          final hasLrc = await primaryLrc.exists();

          for (final secondaryDir in item.targetDirectories.skip(1)) {
            final sDir = Directory(secondaryDir);
            if (!await sDir.exists()) await sDir.create(recursive: true);

            final secFilePath = p.join(secondaryDir, fileName);
            await primaryFile.copy(secFilePath);

            if (hasLrc) {
              final secLrcPath = p.setExtension(secFilePath, '.lrc');
              await primaryLrc.copy(secLrcPath);
            }
          }
        }

        item.executionStatus = 'completed';
        item.executionMessage = item.targetDirectories.length > 1
            ? '已完成云端下载并分发至 ${item.targetDirectories.length} 个磁盘目录'
            : '已下载完成';
      } else {
        item.executionStatus = 'failed';
        item.executionMessage = task.errorMessage ?? '下载失败';
      }
    } else if (item.type == SyncDifferenceType.extraInLocal && item.localFilePath != null) {
      // 策略 3: 清理本地多余音频及同名歌词
      final file = File(item.localFilePath!);
      if (await file.exists()) {
        await file.delete();
      }

      final lrcPath = p.setExtension(item.localFilePath!, '.lrc');
      final lrcFile = File(lrcPath);
      if (await lrcFile.exists()) {
        await lrcFile.delete();
      }

      item.executionStatus = 'completed';
      item.executionMessage = '已从本地删除';
    }
  }
}