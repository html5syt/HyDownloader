/// 单曲音乐实体模型
/// 包含歌曲基础信息、歌手列表、专辑以及可供下载音质
class Song {
  /// 歌曲 ID
  final String id;

  /// 歌曲标题
  final String name;

  /// 歌手名称列表
  final List<String> artists;

  /// 所属专辑名称
  final String albumName;

  /// 所属专辑封面图片 URL
  final String albumCoverUrl;

  /// 音频时长（毫秒）
  final int durationMs;

  /// 专辑中的曲目编号
  final int trackNumber;

  /// 歌曲最高可用音质标识 (如 standard, exhigh, lossless, hires)
  final String maxQuality;

  /// 歌曲音质限制 / 独占标记 (如是否 VIP 独享)
  final int fee;

  const Song({
    required this.id,
    required this.name,
    required this.artists,
    required this.albumName,
    required this.albumCoverUrl,
    required this.durationMs,
    this.trackNumber = 1,
    this.maxQuality = 'lossless',
    this.fee = 0,
  });

  /// 格式化后的歌手连写字符串（多个歌手用 / 或分号隔开）
  String get artistString => artists.isEmpty ? '未知歌手' : artists.join(' / ');

  /// 适用于文件命名的歌手连写（避免特殊路径字符）
  String get artistStringForFileName =>
      artists.isEmpty ? '未知歌手' : artists.join(';');

  /// 格式化后的歌曲时长显示 (mm:ss)
  String get formattedDuration {
    final totalSeconds = (durationMs / 1000).floor();
    final minutes = (totalSeconds / 60).floor().toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// 是否需要 VIP 权限才能完整播放/下载
  bool get isVipRequired => fee == 1 || fee == 4;

  /// 从网易云 API 歌曲 JSON 数据解析
  factory Song.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    final name = (json['name'] ?? '未知曲目').toString();

    // 歌手解析
    final artistsList = <String>[];
    if (json['ar'] is List) {
      for (final a in json['ar']) {
        if (a is Map && a['name'] != null) {
          artistsList.add(a['name'].toString());
        }
      }
    } else if (json['artists'] is List) {
      for (final a in json['artists']) {
        if (a is Map && a['name'] != null) {
          artistsList.add(a['name'].toString());
        }
      }
    }

    // 专辑解析
    String albumName = '';
    String albumCover = '';
    if (json['al'] is Map) {
      albumName = json['al']['name']?.toString() ?? '';
      albumCover = json['al']['picUrl']?.toString() ?? '';
    } else if (json['album'] is Map) {
      albumName = json['album']['name']?.toString() ?? '';
      albumCover = json['album']['picUrl']?.toString() ?? '';
    }

    // 时长解析
    final dt = json['dt'] is int
        ? json['dt'] as int
        : (json['duration'] is int ? json['duration'] as int : 0);

    // 音轨号
    final no = json['no'] is int ? json['no'] as int : 1;

    // 最高品质探测
    String quality = 'standard';
    if (json['hr'] != null) {
      quality = 'hires';
    } else if (json['sq'] != null) {
      quality = 'lossless';
    } else if (json['h'] != null) {
      quality = 'exhigh';
    }

    return Song(
      id: id,
      name: name,
      artists: artistsList,
      albumName: albumName,
      albumCoverUrl: albumCover,
      durationMs: dt,
      trackNumber: no,
      maxQuality: quality,
      fee: json['fee'] is int ? json['fee'] as int : 0,
    );
  }

  /// 序列化保存
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'artists': artists,
      'albumName': albumName,
      'albumCoverUrl': albumCoverUrl,
      'durationMs': durationMs,
      'trackNumber': trackNumber,
      'maxQuality': maxQuality,
      'fee': fee,
    };
  }
}
