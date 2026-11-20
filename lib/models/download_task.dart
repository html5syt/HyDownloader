import 'song.dart';
import '../services/storage/file_access.dart';

/// 下载任务执行状态枚举
enum DownloadStatus {
  /// 排队等待下载
  pending('等待中'),

  /// 正在下载音频文件
  downloading('下载中'),

  /// 正在写入歌曲 ID3 / 元数据标签
  tagging('写入标签'),

  /// 正在获取并保存歌词文件
  lyrics('保存歌词'),

  /// 下载已完成
  completed('已完成'),

  /// 下载出错
  failed('失败'),

  /// 已暂停
  paused('已暂停'),

  /// 已取消
  cancelled('已取消');

  final String label;
  const DownloadStatus(this.label);
}

/// 下载任务实体模型
/// 维护单曲下载全周期的状态、进度与文件信息
class DownloadTask {
  /// 任务唯一标识（通常为 歌曲ID + 音质档位）
  final String id;

  /// 要下载的目标歌曲
  final Song song;

  /// 选定的下载音质档位 (如 lossless, hires, exhigh)
  final String qualityLevel;

  /// 存储目标目录绝对路径
  final String targetDirectory;

  /// 目标文件名（含后缀，如：周杰伦 - 晴天.flac）
  String fileName;

  /// 完整文件存储路径
  String get fullFilePath => FileAccess.join(targetDirectory, fileName);

  /// 当前任务运行状态
  DownloadStatus status;

  /// 下载进度百分比 (0.0 - 1.0)
  double progress;

  /// 已下载的字节数
  int receivedBytes;

  /// 文件总字节数
  int totalBytes;

  /// 实时下载速度 (字节/秒)
  double speedBytesPerSec;

  /// 错误详细信息（若发生异常）
  String? errorMessage;

  /// 实际解析出的音频文件下载直链
  String? downloadUrl;

  /// 实际音频格式后缀 (如 flac, mp3, m4a)
  String fileExtension;

  /// VIP 试听截断保护的暂停原因，与用户手动暂停分开维护。
  bool pausedForVip = false;

  /// 用户单独继续此任务时，允许忽略当前 VIP 保护。
  bool ignoreVipRestriction = false;

  /// 实际音频长度与试听截断标记。
  int? actualDurationMs;
  bool isPreview = false;

  DownloadTask({
    required this.id,
    required this.song,
    required this.qualityLevel,
    required this.targetDirectory,
    required this.fileName,
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.speedBytesPerSec = 0.0,
    this.errorMessage,
    this.downloadUrl,
    this.fileExtension = 'mp3',
  });

  /// 格式化后的文件大小（如 25.4 MB）
  String get formattedTotalSize {
    if (totalBytes <= 0) return '未知大小';
    final mb = totalBytes / (1024 * 1024);
    if (mb < 1.0) {
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// 格式化后的实时下载速度（如 2.3 MB/s）
  String get formattedSpeed {
    if (speedBytesPerSec <= 0 || status != DownloadStatus.downloading) {
      return '';
    }
    final kb = speedBytesPerSec / 1024;
    if (kb > 1024) {
      return '${(kb / 1024).toStringAsFixed(1)} MB/s';
    }
    return '${kb.toStringAsFixed(0)} KB/s';
  }
}
