import '../storage/file_access.dart';

/// LRC 歌词文件持久化写入工具
class LyricWriter {
  /// 将格式化歌词内容保存至音频文件同级目录
  ///
  /// [audioFilePath] 目标音频文件全路径
  /// [lrcContent] 歌词文本
  static Future<void> writeLrcFile(
    String audioFilePath,
    String lrcContent,
  ) async {
    if (lrcContent.trim().isEmpty) return;

    final file = StoredFile(FileAccess.withExtension(audioFilePath, '.lrc'));
    await file.writeAsString(lrcContent, flush: true);
  }
}
