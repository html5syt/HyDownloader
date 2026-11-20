import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'permission_service.dart';

/// 目录授权保留为 saf: 标识，绝不转换成未经授权的磁盘路径。
class FileAccess {
  static const channel = PermissionService.channel;
  static bool isSaf(String path) => path.startsWith('saf:');

  static String join(String directory, String name) => isSaf(directory)
      ? '$directory/${Uri.encodeComponent(name)}'
      : p.join(directory, name);

  static String displayPath(String path) =>
      isSaf(path) ? Uri.decodeComponent(path.split('/').last) : path;

  static String fileName(String path) => isSaf(path)
      ? Uri.decodeComponent(path.split('/').last)
      : p.basename(path);

  static String withExtension(String path, String extension) {
    if (!isSaf(path)) return p.setExtension(path, extension);
    final parent = path.substring(0, path.lastIndexOf('/'));
    return join(parent, p.setExtension(fileName(path), extension));
  }

  static Future<String?> pickDirectory({required String title}) async {
    if (Platform.isAndroid) {
      final selected = await channel.invokeMapMethod<String, String>(
        'pickDirectory',
      );
      if (selected == null) return null;
      final uri = selected['uri']!;
      final name = selected['name'] ?? '音乐文件夹';
      return 'saf:${base64Url.encode(utf8.encode(uri))}/${Uri.encodeComponent(name)}';
    }
    final selected = await FilePicker.pickDirectory(dialogTitle: title);
    if (selected == null) return null;
    // Android 仍使用上面的持久化 SAF 授权桥接；其他平台返回 file: URI。
    if (selected.scheme != 'file') {
      throw const FileSystemException('无法访问此文件夹，请选择本地文件夹');
    }
    return selected.toFilePath();
  }

  static Future<void> ensureDirectory(String path) async {
    if (isSaf(path)) {
      await invoke<void>('checkDirectory', {'path': path});
    } else {
      await PermissionService.instance.ensureLegacyPathAccess(path);
      await Directory(path).create(recursive: true);
    }
  }

  /// 授权失效、拔卡等错误必须上报，不能将读取失败当成空目录继续同步。
  static Future<List<StoredFile>> listFiles(String directory) async {
    if (isSaf(directory)) {
      final names = await invoke<List<Object?>>('listFiles', {
        'path': directory,
      });
      return (names ?? [])
          .cast<String>()
          .map((name) => StoredFile(join(directory, name)))
          .toList();
    }
    await PermissionService.instance.ensureLegacyPathAccess(directory);
    return Directory(directory)
        .list(followLinks: false)
        .where((entry) => entry is File)
        .map((entry) => StoredFile(entry.path))
        .toList();
  }

  static Future<T?> invoke<T>(String method, Map<String, Object> args) async {
    try {
      return await channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw FileSystemException(e.message ?? '无法访问此文件夹，请重新选择并允许访问');
    }
  }
}

/// 对普通文件与已授权目录提供一致的流式文件操作。
class StoredFile {
  final String path;
  StoredFile(this.path);

  Future<bool> exists() async => FileAccess.isSaf(path)
      ? await FileAccess.invoke<bool>('exists', {'path': path}) ?? false
      : File(path).exists();

  Future<int> length() async => FileAccess.isSaf(path)
      ? await FileAccess.invoke<int>('length', {'path': path}) ?? 0
      : File(path).length();

  Future<void> writeAsString(String text, {bool flush = false}) async {
    if (FileAccess.isSaf(path)) {
      await FileAccess.invoke<void>('writeText', {'path': path, 'text': text});
    } else {
      await PermissionService.instance.ensureLegacyPathAccess(path);
      await File(path).writeAsString(text, flush: flush);
    }
  }

  Future<void> copy(String destination) async {
    if (FileAccess.isSaf(path) || FileAccess.isSaf(destination)) {
      await FileAccess.invoke<void>('copy', {
        'source': path,
        'destination': destination,
      });
    } else {
      await PermissionService.instance.ensureLegacyPathAccess(destination);
      await File(path).copy(destination);
    }
  }

  Future<void> delete() async {
    if (FileAccess.isSaf(path)) {
      await FileAccess.invoke<void>('delete', {'path': path});
    } else {
      await PermissionService.instance.ensureLegacyPathAccess(path);
      await File(path).delete();
    }
  }
}
