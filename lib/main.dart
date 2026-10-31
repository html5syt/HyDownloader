import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/app_constants.dart';
import 'config/app_theme.dart';
import 'services/storage/storage_service.dart';
import 'providers/auth_provider.dart';
import 'providers/home_provider.dart';
import 'providers/player_provider.dart';
import 'providers/download_provider.dart';
import 'providers/sync_provider.dart';
import 'ui/home/home_screen.dart';

/// 应用程序入口主函数
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化本地持久化配置
  await StorageService.instance.init();

  runApp(const HyDownloaderApp());
}

/// HyDownloader 根应用组件
class HyDownloaderApp extends StatelessWidget {
  const HyDownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..restoreSavedLogin()),
        ChangeNotifierProvider(create: (_) => HomeProvider()),
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ChangeNotifierProvider(create: (_) => DownloadProvider()),
        ChangeNotifierProvider(create: (_) => SyncProvider()),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          // 首次启动若恢复了登录，自动同步音乐库
          if (auth.isLoggedIn && auth.currentUser != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final home = context.read<HomeProvider>();
              if (home.playlists.isEmpty && !home.isLoading) {
                home.loadUserLibrary(auth.currentUser!.userId);
              }
            });
          }

          return MaterialApp(
            title: AppConstants.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.system,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
