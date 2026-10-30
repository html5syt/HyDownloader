import 'dart:io';
import 'package:path/path.dart' as p;

/// LRC 歌词文件持久化写入工具
class LyricWriter {
  /// 将格式化歌词内容保存至音频文件同级目录
  ///
  /// [audioFilePath] 目标音频文件全路径
  /// [lrcContent] 歌词文本
  static Future<void> writeLrcFile(String audioFilePath, String lrcContent) async {
    if (lrcContent.trim().isEmpty) return;

    final dir = p.dirname(audioFilePath);
    final baseName = p.basenameWithoutExtension(audioFilePath);
    final lrcPath = p.join(dir, '$baseName.lrc');

    final file = File(lrcPath);
    await file.writeAsString(lrcContent, flush: true);
  }
}
