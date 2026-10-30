import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// 网易云音乐 API 加解密工具类
/// 严格参照 HyPlayer.NeteaseApi 中的密码学实现
/// 包含 EAPI (AES-128-ECB) 与 WEAPI (AES-128-CBC + RSA-1024) 两种核心算法
class NeteaseCryptoUtils {
  /// EAPI 加密使用的固定 16 字节 AES 密钥: e82ckenh8dichen8
  static const String eapiKey = 'e82ckenh8dichen8';

  /// WEAPI 加密使用的固定 16 字节 AES 预设密钥: 0CoJUm6Qyw8W8jud
  static const String weapiPresetKey = '0CoJUm6Qyw8W8jud';

  /// WEAPI AES 初始向量 IV: 0102030405060708
  static const String weapiIv = '0102030405060708';

  /// WEAPI RSA 公钥模数 (1024 位，128 字节)
  static const String weapiRsaModulus =
      '00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7';

  /// WEAPI RSA 公钥指数 (65537 / 0x10001)
  static const int weapiRsaExponent = 65537;

  /// Base62 字符集，用于生成随机 16 位会话密钥
  static const String _base62Chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  /// 对 EAPI 请求参数进行加密
  ///
  /// [apiPath] 接口路由地址，例如 "/api/song/enhance/player/url/v1"
  /// [jsonPayload] 包含请求体与 header 的 JSON 字符串
  ///
  /// 返回大写的十六进制密文字符串，用于填充表单 params 字段
  static String encryptEApi(String apiPath, String jsonPayload) {
    // 1. 计算 md5 摘要: md5("nobody" + apiPath + "use" + jsonPayload + "md5forencrypt")
    final messageForMd5 = 'nobody${apiPath}use${jsonPayload}md5forencrypt';
    final digest = md5.convert(utf8.encode(messageForMd5)).toString().toLowerCase();

    // 2. 拼接加密前明文字符串
    final requestData = '$apiPath-36cd479b6b5-$jsonPayload-36cd479b6b5-$digest';

    // 3. 使用 AES-128-ECB PKCS7 进行加密
    final key = enc.Key.fromUtf8(eapiKey);
    final encrypter = enc.Encrypter(
      enc.AES(key, mode: enc.AESMode.ecb, padding: 'PKCS7'),
    );
    final encrypted = encrypter.encrypt(requestData);

    // 4. 转为大写十六进制字符串返回
    return encrypted.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();
  }

  /// 对 EAPI 返回的响应数据进行解密
  ///
  /// 若原始数据已经为明文 JSON（以 "{" 开头），则直接返回明文；
  /// 否则使用 AES-128-ECB 进行解密并转换为 UTF-8 字符串
  static String decryptEApi(List<int> responseBytes) {
    if (responseBytes.isEmpty) return '{}';

    // 判断首字节是否为 '{' (0x7B)
    if (responseBytes[0] == 0x7B) {
      try {
        return utf8.decode(responseBytes);
      } catch (_) {
        // 如果虽然是 0x7B 但解码失败，继续尝试解密
      }
    }

    try {
      final key = enc.Key.fromUtf8(eapiKey);
      final encrypter = enc.Encrypter(
        enc.AES(key, mode: enc.AESMode.ecb, padding: 'PKCS7'),
      );
      final decryptedText = encrypter.decrypt(
        enc.Encrypted(Uint8List.fromList(responseBytes)),
      );
      return decryptedText;
    } catch (e) {
      // 容错：若解密失败直接尝试 utf8 解码
      return utf8.decode(responseBytes, allowMalformed: true);
    }
  }

  /// 对 WEAPI 请求参数进行二次 AES + RSA 混合加密
  ///
  /// [jsonPayload] 待发送的 JSON 字符串
  /// 返回包含 params 与 encSecKey 的键值对 Map
  static Map<String, String> encryptWeApi(String jsonPayload) {
    // 1. 生成 16 字节随机密钥
    final random = Random();
    final secretKeyString = List.generate(
      16,
      (_) => _base62Chars[random.nextInt(_base62Chars.length)],
    ).join();

    final iv = enc.IV.fromUtf8(weapiIv);
    final presetKey = enc.Key.fromUtf8(weapiPresetKey);
    final secretKey = enc.Key.fromUtf8(secretKeyString);

    // 2. 第一次 AES-CBC 加密 (使用预设密钥)
    final encrypter1 = enc.Encrypter(
      enc.AES(presetKey, mode: enc.AESMode.cbc, padding: 'PKCS7'),
    );
    final firstEncryptedBase64 = encrypter1.encrypt(jsonPayload, iv: iv).base64;

    // 3. 第二次 AES-CBC 加密 (使用随机密钥)
    final encrypter2 = enc.Encrypter(
      enc.AES(secretKey, mode: enc.AESMode.cbc, padding: 'PKCS7'),
    );
    final paramsBase64 =
        encrypter2.encrypt(firstEncryptedBase64, iv: iv).base64;

    // 4. RSA 加密随机密钥 (随机密钥反转字节序后进行大数模幂运算)
    final reversedBytes = utf8.encode(secretKeyString).reversed.toList();
    var secretBigInt = BigInt.zero;
    for (final b in reversedBytes) {
      secretBigInt = (secretBigInt << 8) | BigInt.from(b);
    }

    final n = BigInt.parse(weapiRsaModulus, radix: 16);
    final e = BigInt.from(weapiRsaExponent);
    final encSecKey = secretBigInt.modPow(e, n).toRadixString(16).padLeft(256, '0');

    return {
      'params': paramsBase64,
      'encSecKey': encSecKey,
    };
  }

  /// 生成模拟设备 ID (对应 HyPlayer 中 NeteaseUtils.GetDeviceId)
  ///
  /// 格式: Base64(imei + "\t" + mac + "\t" + androidId + "\t" + localId) 并经过 URL 转义
  static String generateDeviceId({
    String? imei,
    String? mac,
    String? androidId,
    String? localId,
  }) {
    final effectiveImei = imei ?? 'null';
    final effectiveMac = mac ?? '02:00:00:00:00:00';
    final effectiveAndroidId = androidId ?? _generateRandomHex(16);
    final effectiveLocalId = localId ?? 'null';

    final raw = '$effectiveImei\t$effectiveMac\t$effectiveAndroidId\t$effectiveLocalId';
    final base64String = base64.encode(utf8.encode(raw));
    return Uri.encodeComponent(base64String);
  }

  /// 内部辅助：生成指定长度随机十六进制字符串
  static String _generateRandomHex(int length) {
    final random = Random();
    const hexChars = '0123456789abcdef';
    return List.generate(length, (_) => hexChars[random.nextInt(16)]).join();
  }
}
