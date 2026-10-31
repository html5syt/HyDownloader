import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import '../../config/app_constants.dart';
import 'crypto_utils.dart';

/// 网易云音乐网络通信基础客户端
/// 负责处理底层 HTTP 会话、Cookie 维护、附加抓包参数注入以及 EAPI/WEAPI 请求调用
class NeteaseClient {
  /// 底层 Dio 实例
  late final Dio _dio;

  /// 运行时会话 Cookies 映射表
  final Map<String, String> _cookies = {};

  /// 抓包导入的附加参数 (AdditionalParameters)
  Map<String, dynamic> _additionalParameters = {};

  /// 伪造令牌开关
  bool fakeCheckToken = false;

  /// 单例实例
  static final NeteaseClient instance = NeteaseClient._internal();

  NeteaseClient._internal() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
          'Referer': AppConstants.musicBaseUrl,
          'Accept': '*/*',
        },
        responseType: ResponseType.bytes,
      ),
    );
  }

  /// 获取当前所有 Cookies 字典的只读副本
  Map<String, String> get cookies => Map.unmodifiable(_cookies);

  /// 获取当前附加参数配置
  Map<String, dynamic> get additionalParameters => _additionalParameters;

  /// 导入运行时 Cookies
  void importCookies(Map<String, String> newCookies) {
    _cookies.addAll(newCookies);
  }

  /// 清空当前所有 Cookies
  void clearCookies() {
    _cookies.clear();
  }

  /// 设置/更新抓包导入的附加参数 (AdditionalParameters)
  void setAdditionalParameters(Map<String, dynamic> params) {
    _additionalParameters = Map.from(params);

    // 同步提取并合并其中的 Cookies
    if (_additionalParameters['Cookies'] is Map) {
      final additionalCookies = _additionalParameters['Cookies'] as Map;
      for (final entry in additionalCookies.entries) {
        if (entry.value != null && entry.value.toString().isNotEmpty) {
          _cookies[entry.key.toString()] = entry.value.toString();
        }
      }
    }
  }

  /// 将 Cookies 格式化为 HTTP 请求头的 Cookie 字符串
  String _buildCookieHeader() {
    final buffer = StringBuffer();
    _cookies.forEach((key, value) {
      if (value.isNotEmpty) {
        buffer.write('$key=$value; ');
      }
    });
    return buffer.toString();
  }

  /// 解析响应头中的 Set-Cookie 并同步保存至内存
  void _extractSetCookies(Response response) {
    final setCookieList = response.headers['set-cookie'];
    if (setCookieList == null || setCookieList.isEmpty) return;

    for (final rawCookie in setCookieList) {
      final parts = rawCookie.split(';');
      if (parts.isNotEmpty) {
        final pair = parts.first.split('=');
        if (pair.length >= 2) {
          final key = pair[0].trim();
          final val = pair.sublist(1).join('=').trim();
          if (key.isNotEmpty) {
            _cookies[key] = val;
          }
        }
      }
    }
  }

  /// 执行 EAPI 加密请求
  ///
  /// [apiPath] 接口路径，例如 "/api/song/enhance/player/url/v1"
  /// [url] 完整目标 URL（默认组装至 interface.music.163.com/eapi/...）
  /// [actualRequest] 接口实际请求体 Map
  Future<Map<String, dynamic>> postEApi({
    required String apiPath,
    String? url,
    required Map<String, dynamic> actualRequest,
  }) async {
    final targetUrl = url ?? '${AppConstants.interfaceBaseUrl}/eapi${apiPath.replaceFirst('/api', '')}';

    // 1. 组装 EAPI 专用的内置 dataHeader (参照 HyPlayer.NeteaseApi)
    final nowSeconds = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
    final requestId = '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000).toString().padLeft(4, '0')}';

    final dataHeader = <String, dynamic>{
      'osver': _cookies['osver'] ?? '',
      'deviceId': _cookies['deviceId'] ?? '',
      'appver': '8.10.10',
      'versioncode': '140',
      'mobilename': _cookies['mobilename'] ?? 'HyDownloader',
      'buildver': _cookies['buildver'] ?? nowSeconds,
      'resolution': '1920x1080',
      '__csrf': _cookies['__csrf'] ?? '',
      'os': _cookies['os'] ?? 'android',
      'channel': _cookies['channel'] ?? '',
      'requestId': requestId,
    };

    if (_cookies['MUSIC_U'] != null && _cookies['MUSIC_U']!.isNotEmpty) {
      dataHeader['MUSIC_U'] = _cookies['MUSIC_U'];
    }
    if (_cookies['MUSIC_A'] != null && _cookies['MUSIC_A']!.isNotEmpty) {
      dataHeader['MUSIC_A'] = _cookies['MUSIC_A'];
    }

    // 合并抓包导入的 EApiHeaders
    if (_additionalParameters['EApiHeaders'] is Map) {
      final eapiHeaders = _additionalParameters['EApiHeaders'] as Map;
      eapiHeaders.forEach((k, v) {
        if (v != null) dataHeader[k.toString()] = v.toString();
      });
    }

    // 2. 将 dataHeader 转为 json 注入 actualRequest['header']
    final payloadMap = Map<String, dynamic>.from(actualRequest);
    payloadMap['header'] = json.encode(dataHeader);

    // 3. 执行 EAPI 加密
    final jsonPayload = json.encode(payloadMap);
    final encryptedParams = NeteaseCryptoUtils.encryptEApi(apiPath, jsonPayload);

    // 4. 构建 HTTP 请求头（支持抓包 Headers 覆盖）
    final requestHeaders = <String, dynamic>{
      'Content-Type': 'application/x-www-form-urlencoded',
      'Cookie': _buildCookieHeader(),
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
      'Referer': AppConstants.musicBaseUrl,
    };

    if (_additionalParameters['Headers'] is Map) {
      final customHeaders = _additionalParameters['Headers'] as Map;
      customHeaders.forEach((k, v) {
        if (v != null && v.toString().isNotEmpty) {
          requestHeaders[k.toString()] = v.toString();
        }
      });
    }

    // 5. 发起请求
    final response = await _dio.post(
      targetUrl,
      data: 'params=$encryptedParams',
      options: Options(
        headers: requestHeaders,
        responseType: ResponseType.bytes,
      ),
    );

    _extractSetCookies(response);

    // 6. 解密并解析响应
    final responseBytes = response.data as List<int>;
    final decryptedString = NeteaseCryptoUtils.decryptEApi(responseBytes);

    try {
      final decoded = json.decode(decryptedString);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {'data': decoded};
    } catch (e) {
      return {'code': 500, 'message': '解密数据解析失败: $e', 'raw': decryptedString};
    }
  }

  /// 执行 WEAPI 加密请求
  ///
  /// [url] 完整目标 URL，例如 "https://music.163.com/weapi/user/playlist"
  /// [actualRequest] 接口实际请求体 Map
  Future<Map<String, dynamic>> postWeApi({
    required String url,
    required Map<String, dynamic> actualRequest,
  }) async {
    // 注入 __csrf
    final payloadMap = Map<String, dynamic>.from(actualRequest);
    payloadMap['csrf_token'] = _cookies['__csrf'] ?? '';

    // 执行 WEAPI 加密
    final jsonPayload = json.encode(payloadMap);
    final encryptedMap = NeteaseCryptoUtils.encryptWeApi(jsonPayload);

    // 构建请求表单数据
    final formDataString =
        'params=${Uri.encodeQueryComponent(encryptedMap['params']!)}&encSecKey=${Uri.encodeQueryComponent(encryptedMap['encSecKey']!)}';

    // 构建请求头
    final requestHeaders = <String, dynamic>{
      'Content-Type': 'application/x-www-form-urlencoded',
      'Cookie': _buildCookieHeader(),
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
      'Referer': AppConstants.musicBaseUrl,
    };

    if (_additionalParameters['Headers'] is Map) {
      final customHeaders = _additionalParameters['Headers'] as Map;
      customHeaders.forEach((k, v) {
        if (v != null && v.toString().isNotEmpty) {
          requestHeaders[k.toString()] = v.toString();
        }
      });
    }

    final response = await _dio.post(
      url,
      data: formDataString,
      options: Options(
        headers: requestHeaders,
        responseType: ResponseType.bytes,
      ),
    );

    _extractSetCookies(response);

    final responseBytes = response.data as List<int>;
    final jsonString = utf8.decode(responseBytes, allowMalformed: true);

    try {
      final decoded = json.decode(jsonString);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {'data': decoded};
    } catch (e) {
      return {'code': 500, 'message': '返回数据解析异常: $e', 'raw': jsonString};
    }
  }
}
