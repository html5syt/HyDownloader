import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:hydownloader/services/storage/file_access.dart';

class DirectoryPickerStub extends FilePickerPlatform {
  Uri? selection;

  @override
  Future<Uri?> pickDirectory({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => selection;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('目录选择使用 URI 接口，保留本地路径并处理取消和异常 URI', () async {
    final original = FilePickerPlatform.instance;
    final picker = DirectoryPickerStub();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = original);

    final directory = Directory(
      '${Directory.systemTemp.path}/音乐文件夹 with spaces',
    );
    picker.selection = Uri.directory(directory.path);
    final selected = await FileAccess.pickDirectory(title: '选择文件夹');
    expect(p.equals(selected!, directory.path), isTrue);

    picker.selection = null;
    expect(await FileAccess.pickDirectory(title: '选择文件夹'), isNull);

    picker.selection = Uri.parse('content://example/tree/music');
    expect(
      FileAccess.pickDirectory(title: '选择文件夹'),
      throwsA(isA<FileSystemException>()),
    );
  });
}
