/// 歌单实体数据模型
/// 包含歌单基本信息、封面、歌曲总数、播放量等
class Playlist {
  /// 歌单数字 ID
  final String id;

  /// 歌单标题
  final String name;

  /// 歌单封面图片 URL
  final String coverImgUrl;

  /// 包含曲目总数
  final int trackCount;

  /// 累计播放次数
  final int playCount;

  /// 歌单描述文字
  final String description;

  /// 创建者昵称
  final String creatorName;

  /// 是否为系统自动生成的“我喜欢的音乐”歌单
  final bool isLikedSongs;

  const Playlist({
    required this.id,
    required this.name,
    required this.coverImgUrl,
    required this.trackCount,
    required this.playCount,
    this.description = '',
    this.creatorName = '',
    this.isLikedSongs = false,
  });

  /// 从网易云 API 歌单 JSON 数据解析
  factory Playlist.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString() ?? '未知歌单';
    final isLiked = name.contains('喜欢的音乐') || (json['specialType'] == 5);

    String creator = '';
    if (json['creator'] is Map && json['creator']['nickname'] != null) {
      creator = json['creator']['nickname'].toString();
    }

    return Playlist(
      id: (json['id'] ?? '').toString(),
      name: name,
      coverImgUrl: json['coverImgUrl']?.toString() ??
          json['picUrl']?.toString() ??
          '',
      trackCount: json['trackCount'] is int ? json['trackCount'] as int : 0,
      playCount: json['playCount'] is int ? json['playCount'] as int : 0,
      description: json['description']?.toString() ?? '',
      creatorName: creator,
      isLikedSongs: isLiked,
    );
  }

  /// 序列化为 Map 保存
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'coverImgUrl': coverImgUrl,
      'trackCount': trackCount,
      'playCount': playCount,
      'description': description,
      'creatorName': creatorName,
      'isLikedSongs': isLikedSongs,
    };
  }
}
