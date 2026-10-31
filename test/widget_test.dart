import 'package:flutter_test/flutter_test.dart';
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
}
