import 'dart:io';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// 仅在访问旧版 Android 外部路径时申请传统权限。
/// 系统选中的目录使用独立授权，不需要音频读取或全部文件管理权限。
class PermissionService {
  static final PermissionService instance = PermissionService._internal();
  PermissionService._internal();
  static const channel = MethodChannel('com.hyplayer.hydownloader/storage');

  Future<void> ensureLegacyPathAccess(String path) async {
    if (!Platform.isAndroid ||
        !(path.startsWith('/storage/') || path.startsWith('/sdcard/'))) {
      return;
    }
    final sdk = await channel.invokeMethod<int>('sdkVersion') ?? 30;
    if (sdk <= 29 && !await Permission.storage.isGranted) {
      if (!((await Permission.storage.request()).isGranted)) {
        throw const FileSystemException('无法访问此文件夹，请重新选择并允许访问');
      }
    }
  }
}
