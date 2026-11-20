import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import '../storage/file_access.dart';

/// 读取已落盘音频的实际时长，不采用歌单标注时长或下载接口推测值。
class AudioDurationService {
  static Future<int?> readMilliseconds(String path) async {
    try {
      // 无损 FLAC 可直接从 STREAMINFO 精确计算时长，避免系统解码器兼容性差异。
      final flacDuration = await _readFlacDuration(path);
      if (flacDuration != null) return flacDuration;
      if (Platform.isAndroid) {
        return await FileAccess.channel.invokeMethod<int>('audioDuration', {
          'path': path,
        });
      }
      final player = AudioPlayer();
      try {
        await player
            .setSource(DeviceFileSource(path))
            .timeout(const Duration(seconds: 8));
        final duration = await player.getDuration().timeout(
          const Duration(seconds: 3),
        );
        return duration?.inMilliseconds;
      } finally {
        await player.dispose();
      }
    } catch (_) {
      // 无法识别时长时不误判会员权限；保护重试则必须成功测量才可解除。
      return null;
    }
  }

  static Future<int?> _readFlacDuration(String path) async {
    final file = await File(path).open();
    try {
      final bytes = await file.read(42);
      if (bytes.length < 42 ||
          bytes[0] != 0x66 ||
          bytes[1] != 0x4c ||
          bytes[2] != 0x61 ||
          bytes[3] != 0x43 ||
          (bytes[4] & 0x7f) != 0) {
        return null;
      }
      final rate = (bytes[18] << 12) | (bytes[19] << 4) | (bytes[20] >> 4);
      final samples =
          ((bytes[21] & 0x0f) << 32) |
          (bytes[22] << 24) |
          (bytes[23] << 16) |
          (bytes[24] << 8) |
          bytes[25];
      return rate > 0 && samples > 0 ? (samples * 1000 ~/ rate) : null;
    } finally {
      await file.close();
    }
  }

  /// 允许编码误差，但不拦截歌曲本身就是 20/30 秒的短曲。
  static bool isVipPreview({
    required bool isVip,
    required int expectedMs,
    required int? actualMs,
  }) {
    if (!isVip ||
        actualMs == null ||
        (expectedMs > 0 && expectedMs <= actualMs + 3000)) {
      return false;
    }
    return (actualMs - 20000).abs() <= 1500 || (actualMs - 30000).abs() <= 1500;
  }

  static bool isFullLength(int expectedMs, int? actualMs) {
    if (actualMs == null || actualMs <= 0) return false;
    return expectedMs > 0
        ? actualMs >= expectedMs - (expectedMs * 0.02).clamp(2000, 5000)
        : actualMs > 33000;
  }
}
