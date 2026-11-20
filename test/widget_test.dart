import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:hydownloader/ui/widgets/player_cover.dart';
import 'package:hydownloader/models/song.dart';
import 'package:provider/provider.dart';
import 'package:hydownloader/providers/auth_provider.dart';
import 'package:hydownloader/ui/login/login_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hydownloader/main.dart';
import 'package:hydownloader/config/app_constants.dart';
import 'package:hydownloader/services/storage/storage_service.dart';

void main() {
  testWidgets('HyDownloader smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.init();

    await tester.pumpWidget(const HyDownloaderApp());
    await tester.pump();

    // 验证应用标题栏
    expect(find.text(AppConstants.appName), findsOneWidget);
  });
  testWidgets('移动端抓包导入在窄屏及键盘弹出时不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: const MaterialApp(home: Scaffold(body: LoginDialog())),
      ),
    );
    await tester.tap(find.text('抓包导入'));
    await tester.pumpAndSettle();
    expect(find.text('选择文件'), findsOneWidget);
    expect(find.text('粘贴剪贴板'), findsOneWidget);
    expect(find.text('导入登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('导入登录'));
    await tester.pumpAndSettle();
    expect(find.text('导入登录').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('全屏播放器封面适配有限高度与放大字体', (tester) async {
    const song = Song(
      id: 'test',
      name: 'Amore Lunita 长曲名测试',
      artists: ['Z8phyR'],
      albumName: 'Spirit of Color',
      albumCoverUrl: '',
      durationMs: 180000,
    );
    for (final height in [230.0, 140.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: SizedBox(
                width: 320,
                height: height,
                child: const PlayerCover(song: song, compact: true),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Z8phyR · Spirit of Color'));
      expect(tester.takeException(), isNull);
    }
  });
}
