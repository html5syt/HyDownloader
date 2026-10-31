import 'dart:convert';
import 'dart:math';
import '../../models/user_profile.dart';
import '../../models/auth_state.dart';
import 'crypto_utils.dart';
import 'netease_client.dart';

/// 网易云音乐认证服务
/// 实现伪造令牌、抓包导入、扫码登录以及用户会话状态管理
class NeteaseAuthService {
  final NeteaseClient _client = NeteaseClient.instance;

  /// 单例
  static final NeteaseAuthService instance = NeteaseAuthService._internal();
  NeteaseAuthService._internal();

  /// 1. 伪造令牌登录（参照 HyPlayer 中 RegisterCurrentDeviceAsync 实现）
  ///
  /// 通过模拟设备硬件指纹，向云端接口注册匿名设备凭证，
  /// 实现免输入密码、规避部分风控、支持匿名浏览与歌曲检索下载
  Future<AuthState> loginWithFakeToken() async {
    // 1. 生成虚拟 Android ID 与设备标识
    final randomHex = List.generate(
      16,
      (_) => Random().nextInt(16).toRadixString(16),
    ).join();
    final deviceId = NeteaseCryptoUtils.generateDeviceId(
      androidId: randomHex,
      mac: '02:00:00:00:00:00',
    );

    // 2. 注入模拟设备环境变量至 Cookie
    final deviceCookies = {
      'deviceId': deviceId,
      'mobilename': 'andrcar_device',
      'os': 'andrcar',
      'channel': 'release',
      'deviceType': 'andrcar',
      'appver': '8.10.10',
      'versioncode': '140',
    };
    _client.importCookies(deviceCookies);
    _client.fakeCheckToken = true;

    // 3. 调用设备匿名注册接口 /api/login/anon/device
    try {
      final res = await _client.postEApi(
        apiPath: '/api/login/anon/device',
        actualRequest: {},
      );

      String tempUserId = 'guest_$randomHex';
      if (res['data'] is Map && res['data']['userId'] != null) {
        tempUserId = res['data']['userId'].toString();
      }

      final profile = UserProfile(
        userId: tempUserId,
        nickname: '访客设备 (伪造令牌)',
        avatarUrl: '',
        signature: '已启用虚拟设备令牌，可正常检索与下载公共曲目',
      );

      return AuthState(
        isLoggedIn: true,
        loginMethod: LoginMethod.fakeToken,
        userProfile: profile,
        cookies: _client.cookies,
        anonymousDeviceId: tempUserId,
      );
    } catch (e) {
      // 容错处理：即使服务端未返回 userId，依然具备本地伪造设备环境
      final fallbackProfile = UserProfile(
        userId: 'fake_$randomHex',
        nickname: '访客设备 (伪造令牌)',
        avatarUrl: '',
        signature: '本地虚拟令牌就绪',
      );
      return AuthState(
        isLoggedIn: true,
        loginMethod: LoginMethod.fakeToken,
        userProfile: fallbackProfile,
        cookies: _client.cookies,
        anonymousDeviceId: fallbackProfile.userId,
      );
    }
  }

  /// 2. 抓包登录（导入 capture.json 或抓包参数 JSON）
  ///
  /// 导入 mitmproxy 抓取的 capture.json（含 Cookies、Headers、EApiHeaders），
  /// 自动继承官方客户端授权，完成静默无感登录
  Future<AuthState> loginWithPacketCapture(String jsonString) async {
    try {
      final parsed = json.decode(jsonString);
      if (parsed is! Map<String, dynamic>) {
        throw const FormatException('抓包数据格式不正确，需为有效 JSON 对象');
      }

      // 将附加参数载入网络通信客户端
      _client.setAdditionalParameters(parsed);

      // 验证登录会话有效性并拉取个人信息
      final profile = await fetchCurrentUserProfile();
      if (profile != null) {
        return AuthState(
          isLoggedIn: true,
          loginMethod: LoginMethod.packetCapture,
          userProfile: profile,
          cookies: _client.cookies,
          additionalParameters: parsed,
        );
      }

      // 如果抓包中包含 MUSIC_U，即便接口超时仍视为已导入授权
      if (_client.cookies['MUSIC_U'] != null && _client.cookies['MUSIC_U']!.isNotEmpty) {
        return AuthState(
          isLoggedIn: true,
          loginMethod: LoginMethod.packetCapture,
          userProfile: const UserProfile(
            userId: 'imported_user',
            nickname: '已导入抓包授权用户',
            avatarUrl: '',
          ),
          cookies: _client.cookies,
          additionalParameters: parsed,
        );
      }

      throw Exception('抓包数据中未检测到有效登录令牌 (MUSIC_U)');
    } catch (e) {
      rethrow;
    }
  }

  /// 3. 手动 Cookie 粘贴登录
  ///
  /// 支持粘贴如 "MUSIC_U=xxxx; __csrf=yyyy" 的原生 Cookie 字符串
  Future<AuthState> loginWithRawCookie(String cookieString) async {
    final pairs = cookieString.split(';');
    final map = <String, String>{};
    for (final pair in pairs) {
      final parts = pair.trim().split('=');
      if (parts.length >= 2) {
        map[parts[0].trim()] = parts.sublist(1).join('=').trim();
      }
    }

    if (map.isEmpty) {
      throw const FormatException('未解析到任何有效 Cookie 键值对');
    }

    _client.importCookies(map);
    final profile = await fetchCurrentUserProfile();

    return AuthState(
      isLoggedIn: true,
      loginMethod: LoginMethod.cookie,
      userProfile: profile ??
          UserProfile(
            userId: map['MUSIC_A'] ?? 'custom_user',
            nickname: 'Cookie 登录用户',
            avatarUrl: '',
          ),
      cookies: _client.cookies,
    );
  }

  /// 4. 扫码登录：第一步，获取 UniKey
  Future<String> getQrKey() async {
    final res = await _client.postWeApi(
      url: 'https://music.163.com/weapi/login/qrcode/unikey',
      actualRequest: {'type': 1},
    );
    final key = res['unikey']?.toString();
    if (key == null || key.isEmpty) {
      throw Exception('获取二维码 UniKey 失败: ${res['message'] ?? '未知错误'}');
    }
    return key;
  }

  /// 5. 扫码登录：第二步，轮询扫码状态
  ///
  /// 返回 code 码状态:
  /// - 800: 二维码已过期，需要刷新
  /// - 801: 等待用户扫码
  /// - 802: 手机端已扫描，等待确认授权
  /// - 803: 授权成功，会话建立完成
  Future<int> checkQrStatus(String unikey) async {
    final res = await _client.postWeApi(
      url: 'https://music.163.com/weapi/login/qrcode/client/login',
      actualRequest: {
        'key': unikey,
        'type': 1,
      },
    );
    return res['code'] is int ? res['code'] as int : 801;
  }

  /// 6. 拉取当前已登录用户的详细资料
  Future<UserProfile?> fetchCurrentUserProfile() async {
    try {
      final res = await _client.postWeApi(
        url: 'https://music.163.com/weapi/w/nuser/account/get',
        actualRequest: {},
      );

      if (res['profile'] is Map<String, dynamic>) {
        return UserProfile.fromJson(res['profile'] as Map<String, dynamic>);
      }
    } catch (_) {
      // 容错调用备用状态接口
      try {
        final res2 = await _client.postWeApi(
          url: 'https://music.163.com/weapi/nuser/account/get',
          actualRequest: {},
        );
        if (res2['profile'] is Map<String, dynamic>) {
          return UserProfile.fromJson(res2['profile'] as Map<String, dynamic>);
        }
      } catch (_) {}
    }
    return null;
  }

  /// 退出登录并清除客户端会话 Cookies
  Future<void> logout() async {
    _client.clearCookies();
    _client.setAdditionalParameters({});
    _client.fakeCheckToken = false;
  }
}
