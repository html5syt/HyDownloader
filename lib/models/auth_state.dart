import 'user_profile.dart';

/// 登录凭证类型枚举
enum LoginMethod {
  /// 未登录
  none,

  /// 伪造令牌 / 模拟匿名设备凭证登录
  fakeToken,

  /// 抓包导入登录 (导入 capture.json 或抓包 Headers/Cookies)
  packetCapture,

  /// 官方客户端扫码登录
  qrCode,

  /// 手动 Cookie 粘贴登录
  cookie,
}

/// 用户认证状态数据模型
/// 维护当前会话的登录状态、Cookies 以及用户资料
class AuthState {
  /// 是否已登录认证
  final bool isLoggedIn;

  /// 当前登录使用的手段
  final LoginMethod loginMethod;

  /// 当前登录用户资料（若已获取）
  final UserProfile? userProfile;

  /// 会话运行时 Cookies 字典
  final Map<String, String> cookies;

  /// 抓包导入的附加参数 (AdditionalParameters: Headers, EApiHeaders, Cookies 等)
  final Map<String, dynamic> additionalParameters;

  /// 临时匿名用户 ID (针对伪造令牌模式)
  final String? anonymousDeviceId;

  const AuthState({
    required this.isLoggedIn,
    this.loginMethod = LoginMethod.none,
    this.userProfile,
    this.cookies = const {},
    this.additionalParameters = const {},
    this.anonymousDeviceId,
  });

  /// 初始未登录状态工厂方法
  factory AuthState.unauthenticated() {
    return const AuthState(
      isLoggedIn: false,
      loginMethod: LoginMethod.none,
      cookies: {},
      additionalParameters: {},
    );
  }

  /// 快速复制更新状态
  AuthState copyWith({
    bool? isLoggedIn,
    LoginMethod? loginMethod,
    UserProfile? userProfile,
    Map<String, String>? cookies,
    Map<String, dynamic>? additionalParameters,
    String? anonymousDeviceId,
  }) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      loginMethod: loginMethod ?? this.loginMethod,
      userProfile: userProfile ?? this.userProfile,
      cookies: cookies ?? this.cookies,
      additionalParameters: additionalParameters ?? this.additionalParameters,
      anonymousDeviceId: anonymousDeviceId ?? this.anonymousDeviceId,
    );
  }
}
