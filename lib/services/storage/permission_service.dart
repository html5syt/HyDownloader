import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// 跨平台权限管理服务
/// 针对 Android 各版本（传统存储权限、Android 11+ 全部文件管理权限、Android 13+ 媒体音频权限）
/// 提供主动请求、状态探测与设置跳转引导
class PermissionService {
  static final PermissionService instance = PermissionService._internal();
  PermissionService._internal();

  /// 主动检查并申请外部存储与媒体读写权限
  /// 确保移动端对内部存储、外部 SD 卡及 USB OTG 磁盘均具备完整读写能力
  Future<bool> requestStoragePermission() async {
    if (kIsWeb) return true;

    // 仅在移动平台（主要是 Android）进行动态存储权限申请
    if (Platform.isAndroid) {
      try {
        // 1. Android 13+ (API 33) 音频媒体权限
        final audioStatus = await Permission.audio.status;
        if (!audioStatus.isGranted) {
          await Permission.audio.request();
        }

        // 2. 传统存储读写权限 (Android 10 及以下)
        final storageStatus = await Permission.storage.status;
        if (!storageStatus.isGranted) {
          await Permission.storage.request();
        }

        // 3. Android 11+ (API 30+) 全局外部存储管理权限 (MANAGE_EXTERNAL_STORAGE)
        // 该权限是自由读写外置 SD 卡或自选歌曲同步目录所必需
        final manageStatus = await Permission.manageExternalStorage.status;
        if (!manageStatus.isGranted) {
          final res = await Permission.manageExternalStorage.request();
          if (res.isGranted) return true;
        }

        // 综合判断是否具备基本存储操作能力
        final finalStorage = await Permission.storage.isGranted;
        final finalManage = await Permission.manageExternalStorage.isGranted;
        final finalAudio = await Permission.audio.isGranted;

        return finalStorage || finalManage || finalAudio;
      } catch (e) {
        debugPrint('请求存储权限异常: $e');
        return false;
      }
    } else if (Platform.isIOS) {
      // iOS 由沙盒及 Documents 管理，可直接读写应用内目录
      return true;
    }

    return true;
  }

  /// 检查当前是否已具备外部存储读写权限
  Future<bool> isStoragePermissionGranted() async {
    if (kIsWeb || !Platform.isAndroid) return true;

    final manage = await Permission.manageExternalStorage.isGranted;
    if (manage) return true;

    final storage = await Permission.storage.isGranted;
    final audio = await Permission.audio.isGranted;
    return storage || audio;
  }

  /// 跳转至系统应用设置页（供用户手动开启所有文件管理权限）
  Future<bool> openSettings() async {
    return openAppSettings();
  }
}