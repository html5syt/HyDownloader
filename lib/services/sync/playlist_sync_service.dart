import 'dart:io';
import 'package:path/path.dart' as p;
import '../../models/song.dart';
import '../../models/sync_item.dart';
import '../netease/music_service.dart';
import '../download/download_service.dart';

/// 歌单与本地文件对比和同步核心服务
/// 实现：在线歌单与多个本地文件夹双向对比、缺失/多余歌曲检测、批量同步与安全清理
class PlaylistSyncService {
  final NeteaseMusicService _musicService = NeteaseMusicService.instance;
  final DownloadService _downloadService = DownloadService.instance;

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
  /// [localFolderPaths] 选定的一个或多个本地文件夹路径
  Future<List<SyncItem>> comparePlaylistWithLocalFolders({
    required String playlistId,
    required List<String> localFolderPaths,
  }) async {
    // 1. 获取在线歌单完整歌曲列表
    final onlineSongs = await _musicService.getPlaylistSongs(playlistId);

    // 2. 遍历扫描所有选定本地目录下的音频文件
    final localFiles = <File>[];
    for (final folderPath in localFolderPaths) {
      final dir = Directory(folderPath);
      if (await dir.exists()) {
        try {
          final entries = await dir.list(recursive: false).toList();
          for (final entity in entries) {
            if (entity is File) {
              final ext = p.extension(entity.path).toLowerCase();
              if (supportedAudioExtensions.contains(ext)) {
                localFiles.add(entity);
              }
            }
          }
        } catch (_) {}
      }
    }

    // 3. 建立本地文件指纹索引
    // 记录文件名纯净文本 -> 文件对象
    final localFileMap = <String, File>{};
    for (final f in localFiles) {
      final baseName = p.basenameWithoutExtension(f.path);
      final normalized = _normalizeText(baseName);
      localFileMap[normalized] = f;
    }

    final matchedLocalFiles = <File>{};
    final resultItems = <SyncItem>[];

    // 4. 比对在线歌曲是否存在于本地
    for (final song in onlineSongs) {
      final songMatchedFile = _findMatchingLocalFile(song, localFileMap);

      if (songMatchedFile != null) {
        matchedLocalFiles.add(songMatchedFile);
        resultItems.add(SyncItem(
          id: 'matched_${song.id}',
          type: SyncDifferenceType.matched,
          song: song,
          localFilePath: songMatchedFile.path,
          localFileName: p.basename(songMatchedFile.path),
          localDirectory: p.dirname(songMatchedFile.path),
          isSelected: false, // 已匹配的项默认不参与操作
        ));
      } else {
        // 本地缺失该在线歌曲
        resultItems.add(SyncItem(
          id: 'missing_${song.id}',
          type: SyncDifferenceType.missingInLocal,
          song: song,
          isSelected: true, // 默认勾选待同步下载
        ));
      }
    }

    // 5. 找出本地多余（未在在线歌单中）的歌曲
    for (final f in localFiles) {
      if (!matchedLocalFiles.contains(f)) {
        final fileName = p.basename(f.path);
        resultItems.add(SyncItem(
          id: 'extra_${f.path.hashCode}',
          type: SyncDifferenceType.extraInLocal,
          localFilePath: f.path,
          localFileName: fileName,
          localDirectory: p.dirname(f.path),
          isSelected: true, // 默认勾选待清理
        ));
      }
    }

    return resultItems;
  }

  /// 在本地文件中寻找与在线歌曲匹配的文件
  File? _findMatchingLocalFile(Song song, Map<String, File> localFileMap) {
    final songNameNorm = _normalizeText(song.name);
    final artistNorms = song.artists.map(_normalizeText).toList();

    for (final entry in localFileMap.entries) {
      final localNorm = entry.key;

      // 规则 1: 本地文件名包含完整歌名
      if (localNorm.contains(songNameNorm) || songNameNorm.contains(localNorm)) {
        // 如果只有一个歌手或文件名同时包含歌手名，匹配成功
        if (artistNorms.isEmpty) return entry.value;
        for (final a in artistNorms) {
          if (localNorm.contains(a)) return entry.value;
        }
        // 如果歌名足够长(>=4个字)，直接信任歌名匹配
        if (songNameNorm.length >= 4) return entry.value;
      }
    }
    return null;
  }

  /// 字符串标准化：去除特殊字符、括号内容并转小写
  String _normalizeText(String input) {
    var s = input.toLowerCase();
    // 去除括号内容 (如 (Live), (伴奏), [128k] 等)
    s = s.replaceAll(RegExp(r'\([^)]*\)'), '');
    s = s.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    s = s.replaceAll(RegExp(r'\{[^}]*\}'), '');
    // 去除非字母数字汉字字符
    s = s.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]'), '');
    return s.trim();
  }

  /// 执行同步操作：批量下载缺失曲目，并安全清理本地多余曲目
  ///
  /// [items] 用户选择的同步项列表
  /// [targetDownloadFolder] 缺失歌曲的目标下载文件夹
  /// [onProgress] 进度更新回调
  Future<void> executeSync({
    required List<SyncItem> items,
    required String targetDownloadFolder,
    void Function(int completed, int total)? onProgress,
  }) async {
    final selectedItems = items.where((i) => i.isSelected).toList();
    int doneCount = 0;

    for (final item in selectedItems) {
      item.executionStatus = 'syncing';

      try {
        if (item.type == SyncDifferenceType.missingInLocal && item.song != null) {
          // 加入下载队列下载到选定目录
          await _downloadService.enqueueSong(
            item.song!,
            targetDirectory: targetDownloadFolder,
          );
          item.executionStatus = 'completed';
          item.executionMessage = '已添加至下载队列';
        } else if (item.type == SyncDifferenceType.extraInLocal && item.localFilePath != null) {
          // 删除本地多余音频文件
          final file = File(item.localFilePath!);
          if (await file.exists()) {
            await file.delete();
          }

          // 同步检查并删除可能存在的对应同名歌词文件 .lrc
          final lrcPath = p.setExtension(item.localFilePath!, '.lrc');
          final lrcFile = File(lrcPath);
          if (await lrcFile.exists()) {
            await lrcFile.delete();
          }

          item.executionStatus = 'completed';
          item.executionMessage = '已从本地删除';
        }
      } catch (e) {
        item.executionStatus = 'failed';
        item.executionMessage = '处理失败: $e';
      }

      doneCount++;
      onProgress?.call(doneCount, selectedItems.length);
    }
  }
}
