import 'song.dart';

/// 播客 / 声音电台实体模型
class Podcast {
  /// 电台 ID
  final String id;

  /// 电台标题
  final String name;

  /// 封面图片网络 URL
  final String coverUrl;

  /// 电台所包含的声音节目总数
  final int programCount;

  /// 订阅/收藏人数
  final int subCount;

  /// 简要描述
  final String description;

  /// 主播昵称
  final String djName;

  const Podcast({
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.programCount,
    required this.subCount,
    this.description = '',
    this.djName = '',
  });

  /// 从网易云电台 JSON 解析
  factory Podcast.fromJson(Map<String, dynamic> json) {
    String dj = '';
    if (json['dj'] is Map && json['dj']['nickname'] != null) {
      dj = json['dj']['nickname'].toString();
    }

    return Podcast(
      id: (json['id'] ?? '').toString(),
      name: json['name']?.toString() ?? '未知播客',
      coverUrl: json['picUrl']?.toString() ??
          json['intervenePicUrl']?.toString() ??
          '',
      programCount: json['programCount'] is int ? json['programCount'] as int : 0,
      subCount: json['subCount'] is int ? json['subCount'] as int : 0,
      description: json['desc']?.toString() ?? json['description']?.toString() ?? '',
      djName: dj,
    );
  }

  /// 序列化为 Map 保存
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'coverUrl': coverUrl,
      'programCount': programCount,
      'subCount': subCount,
      'description': description,
      'djName': djName,
    };
  }
}

/// 播客具体节目实体模型
/// 每个节目对应一条可播放和下载的声音音频
class PodcastProgram {
  /// 节目 ID
  final String id;

  /// 节目标题
  final String name;

  /// 节目封面图 URL
  final String coverUrl;

  /// 节目时长（毫秒）
  final int durationMs;

  /// 播放次数
  final int listenerCount;

  /// 对应的歌曲音频数据模型（方便统一调用播放和下载引擎）
  final Song mainSong;

  const PodcastProgram({
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.durationMs,
    required this.listenerCount,
    required this.mainSong,
  });

  /// 格式化后的节目时长显示
  String get formattedDuration => mainSong.formattedDuration;

  /// 从 API 节目 JSON 解析
  factory PodcastProgram.fromJson(Map<String, dynamic> json) {
    final progId = (json['id'] ?? '').toString();
    final name = json['name']?.toString() ?? '未知节目';
    final cover = json['coverUrl']?.toString() ?? '';
    final dt = json['duration'] is int ? json['duration'] as int : 0;
    final listenerCount = json['listenerCount'] is int ? json['listenerCount'] as int : 0;

    // 解析关联的 mainSong
    Song song;
    if (json['mainSong'] is Map<String, dynamic>) {
      song = Song.fromJson(json['mainSong'] as Map<String, dynamic>);
    } else {
      song = Song(
        id: progId,
        name: name,
        artists: [json['dj']?['nickname']?.toString() ?? '主播'],
        albumName: '播客节目',
        albumCoverUrl: cover,
        durationMs: dt,
      );
    }

    return PodcastProgram(
      id: progId,
      name: name,
      coverUrl: cover,
      durationMs: dt,
      listenerCount: listenerCount,
      mainSong: song,
    );
  }
}
