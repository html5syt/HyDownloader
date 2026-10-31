import 'package:flutter/foundation.dart';
import '../models/auth_state.dart';
import '../models/user_profile.dart';
import '../services/netease/auth_service.dart';
import '../services/storage/storage_service.dart';
import '../services/netease/netease_client.dart';

/// 全局用户认证与登录状态 Provider
/// 管理登录凭证、抓包数据、扫码状态与自动加载
class AuthProvider extends ChangeNotifier {
  final NeteaseAuthService _authService = NeteaseAuthService.instance;
  final StorageService _storage = StorageService.instance;
  final NeteaseClient _client = NeteaseClient.instance;

  AuthState _state = AuthState.unauthenticated();
  bool _isLoading = false;
  String? _errorMessage;

  AuthState get state => _state;
  bool get isLoggedIn => _state.isLoggedIn;
  UserProfile? get currentUser => _state.userProfile;
  LoginMethod get loginMethod => _state.loginMethod;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// 初始化自动恢复已保存的登录凭证
  Future<void> restoreSavedLogin() async {
    _isLoading = true;
    notifyListeners();

    try {
      final savedCookies = _storage.getSavedCookies();
      final savedAdditional = _storage.getSavedAdditionalParameters();

      if (savedAdditional.isNotEmpty) {
        _client.setAdditionalParameters(savedAdditional);
      }
      if (savedCookies.isNotEmpty) {
        _client.importCookies(savedCookies);
      }

      // 如果有 MUSIC_U 或有效 cookies，尝试拉取用户信息
      if (_client.cookies['MUSIC_U'] != null && _client.cookies['MUSIC_U']!.isNotEmpty) {
        final profile = await _authService.fetchCurrentUserProfile();
        _state = AuthState(
          isLoggedIn: true,
          loginMethod: savedAdditional.isNotEmpty ? LoginMethod.packetCapture : LoginMethod.cookie,
          userProfile: profile ?? const UserProfile(userId: 'saved_user', nickname: '网易云音乐用户', avatarUrl: ''),
          cookies: _client.cookies,
          additionalParameters: savedAdditional,
        );
      } else if (_client.cookies['deviceId'] != null) {
        // 恢复伪造令牌会话
        _client.fakeCheckToken = true;
        _state = AuthState(
          isLoggedIn: true,
          loginMethod: LoginMethod.fakeToken,
          userProfile: const UserProfile(
            userId: 'guest_user',
            nickname: '访客设备 (伪造令牌)',
            avatarUrl: '',
            signature: '已启用虚拟设备令牌',
          ),
          cookies: _client.cookies,
        );
      }
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  /// 伪造令牌登录
  Future<bool> loginWithFakeToken() async {
    _setLoading(true);
    _errorMessage = null;

    try {
      final newState = await _authService.loginWithFakeToken();
      _state = newState;
      await _storage.saveCookies(newState.cookies);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = '伪造令牌初始化失败: $e';
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// 抓包数据导入登录
  Future<bool> loginWithPacketCapture(String jsonString) async {
    _setLoading(true);
    _errorMessage = null;

    try {
      final newState = await _authService.loginWithPacketCapture(jsonString);
      _state = newState;
      await _storage.saveCookies(newState.cookies);
      await _storage.saveAdditionalParameters(newState.additionalParameters);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = '抓包数据导入失败: $e';
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Cookie 导入登录
  Future<bool> loginWithCookie(String cookieString) async {
    _setLoading(true);
    _errorMessage = null;

    try {
      final newState = await _authService.loginWithRawCookie(cookieString);
      _state = newState;
      await _storage.saveCookies(newState.cookies);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Cookie 登录失败: $e';
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// 完成扫码登录认证
  Future<void> completeQrLogin() async {
    final profile = await _authService.fetchCurrentUserProfile();
    _state = AuthState(
      isLoggedIn: true,
      loginMethod: LoginMethod.qrCode,
      userProfile: profile ?? const UserProfile(userId: 'qr_user', nickname: '扫码登录用户', avatarUrl: ''),
      cookies: _client.cookies,
    );
    await _storage.saveCookies(_client.cookies);
    notifyListeners();
  }

  /// 退出登录
  Future<void> logout() async {
    await _authService.logout();
    await _storage.clearCookies();
    await _storage.clearAdditionalParameters();
    _state = AuthState.unauthenticated();
    notifyListeners();
  }

  void _setLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }
}
