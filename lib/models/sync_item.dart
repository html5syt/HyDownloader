import 'song.dart';

/// 歌单与本地文件同步差异类型
enum SyncDifferenceType {
  /// 本地所有磁盘均缺失该曲目
  /// 优化策略：从云端下载 1 份至首选磁盘，随后在后台本地拷贝分发至其他磁盘
  missingInLocal('云端下载 (本地全缺)'),

  /// 部分选中的本地磁盘已存在该歌曲
  /// 优化策略：不消耗网络带宽，直接在磁盘间极速本地拷贝复制
  copyFromLocal('本地拷贝 (跨盘复用)'),

  /// 本地文件夹存在音频，但在线歌单中无此歌曲
  /// 优化策略：从本地文件夹中清理移除
  extraInLocal('本地多余 (待清理)'),

  /// 双向一致（在所有选中的本地文件夹中均已完整存在）
  matched('已保持同步');

  final String label;
  const SyncDifferenceType(this.label);
}

/// 歌单同步差异项实体模型
/// 维护每一项的同步差异类型、来源文件、目标分发目录集合与执行进度
class SyncItem {
  /// 唯一标识
  final String id;

  /// 差异类型（全缺下载、本地拷贝复用、多余清理、已同步）
  final SyncDifferenceType type;

  /// 关联的在线歌曲信息
  final Song? song;

  /// 关联的本地文件绝对路径（多余项或已匹配项对应路径）
  final String? localFilePath;

  /// 本地文件名
  final String? localFileName;

  /// 本地所属文件夹目录
  final String? localDirectory;

  /// 本次需要同步复制或分发的目标本地文件夹列表
  final List<String> targetDirectories;

  /// 用于本地直接拷贝的来源文件绝对路径（针对 copyFromLocal 模式）
  final String? sourceFilePath;

  /// 用户是否勾选此项参与本次同步执行
  bool isSelected;

  /// 当前同步操作执行状态 ('idle', 'syncing', 'completed', 'failed')
  String executionStatus;

  /// 执行结果说明
  String? executionMessage;

  SyncItem({
    required this.id,
    required this.type,
    this.song,
    this.localFilePath,
    this.localFileName,
    this.localDirectory,
    this.targetDirectories = const [],
    this.sourceFilePath,
    this.isSelected = true,
    this.executionStatus = 'idle',
    this.executionMessage,
  });

  /// 获取用于 UI 展示的标题
  String get displayTitle {
    if (song != null) {
      return '${song!.artistString} - ${song!.name}';
    }
    return localFileName ?? '未知文件';
  }

  /// 获取副标题信息
  String get displaySubtitle {
    if (type == SyncDifferenceType.copyFromLocal) {
      return '从已有磁盘直接拷贝至 ${targetDirectories.length} 个文件夹 (免下载)';
    } else if (type == SyncDifferenceType.missingInLocal) {
      if (targetDirectories.length > 1) {
        return '优先下载第 1 份，并在后台自动分发至 ${targetDirectories.length} 个文件夹';
      }
      return '专辑: ${song?.albumName.isEmpty ?? true ? "单曲" : song?.albumName}';
    }
    return localFilePath ?? '';
  }
}