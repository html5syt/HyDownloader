/// 用户个人资料实体模型
/// 映射网易云音乐登录用户的基本信息
class UserProfile {
  /// 用户数字 ID
  final String userId;

  /// 用户昵称
  final String nickname;

  /// 头像网络 URL
  final String avatarUrl;

  /// 个性签名
  final String? signature;

  /// VIP 身份类型 (0: 非VIP, 10/11: VIP)
  final int vipType;

  /// 累计听歌数量
  final int listenSongs;

  const UserProfile({
    required this.userId,
    required this.nickname,
    required this.avatarUrl,
    this.signature,
    this.vipType = 0,
    this.listenSongs = 0,
  });

  /// 判断用户是否拥有 VIP 身份
  bool get isVip => vipType > 0;

  /// 从网易云 API 的 profile JSON 数据解析构造
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: (json['userId'] ?? json['id'] ?? '').toString(),
      nickname: json['nickname'] as String? ?? '网易云音乐用户',
      avatarUrl: json['avatarUrl'] as String? ?? '',
      signature: json['signature'] as String?,
      vipType: json['vipType'] is int ? json['vipType'] as int : 0,
      listenSongs: json['listenSongs'] is int ? json['listenSongs'] as int : 0,
    );
  }

  /// 序列化为 Map 保存
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'nickname': nickname,
      'avatarUrl': avatarUrl,
      'signature': signature,
      'vipType': vipType,
      'listenSongs': listenSongs,
    };
  }
}
