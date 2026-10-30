import 'song.dart';

/// 歌单与本地文件同步差异类型
enum SyncDifferenceType {
  /// 本地缺失歌曲（在线歌单存在，本地文件夹未找到对应文件）
  /// 推荐操作：从云端下载到选定的本地目录
  missingInLocal('云端新增 (本地缺失)'),

  /// 本地多余歌曲（本地文件夹存在音频，但在线歌单中无此歌曲）
  /// 推荐操作：从本地文件夹中清理移除
  extraInLocal('本地多余 (歌单无此曲)'),

  /// 双向一致（本地与在线歌单均存在）
  matched('已保持同步');

  final String label;
  const SyncDifferenceType(this.label);
}

/// 歌单同步差异项实体模型
/// 用于在比对界面展示每一个需要同步的项
class SyncItem {
  /// 唯一标识
  final String id;

  /// 差异类型（缺失 或 多余）
  final SyncDifferenceType type;

  /// 关联的在线歌曲信息（缺失/匹配项有值）
  final Song? song;

  /// 关联的本地文件绝对路径（多余/匹配项有值）
  final String? localFilePath;

  /// 本地文件名
  final String? localFileName;

  /// 本地所属文件夹目录
  final String? localDirectory;

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
    if (type == SyncDifferenceType.missingInLocal) {
      return '专辑: ${song?.albumName.isEmpty ?? true ? "单曲" : song?.albumName}';
    }
    return localFilePath ?? '';
  }
}
