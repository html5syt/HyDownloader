import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/home_provider.dart';
import '../../providers/download_provider.dart';
import '../widgets/audio_preview_bar.dart';
import '../widgets/settings_dialog.dart';
import '../widgets/app_network_image.dart';
import '../login/login_dialog.dart';
import '../download/download_screen.dart';
import '../sync/sync_screen.dart';
import 'playlist_tab.dart';
import 'podcast_tab.dart';
import 'search_tab.dart';

/// 应用程序主框架视图
/// 包含响应式导航栏、全局头部、试听控制条与功能模块路由，自适应移动端与桌面端
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _tabs = const [
    PlaylistTab(),
    PodcastTab(),
    SearchTab(),
    SyncScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final auth = context.watch<AuthProvider>();
    final download = context.watch<DownloadProvider>();
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 720;
    final isNarrow = screenWidth < 460;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: isNarrow ? 12 : 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/icon.png',
                width: 30,
                height: 30,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.music_note, color: Colors.red),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'HyDownloader',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: isNarrow ? 16 : 17,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        actions: [
          // 下载中心按钮（带活动任务数角标）
          Badge(
            isLabelVisible: download.activeCount > 0,
            label: Text(download.activeCount.toString()),
            child: IconButton(
              tooltip: '下载管理',
              visualDensity: isNarrow ? VisualDensity.compact : null,
              icon: const Icon(Icons.download_rounded),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DownloadScreen()),
                );
              },
            ),
          ),
          const SizedBox(width: 2),

          // 全局设置按钮
          IconButton(
            tooltip: '偏好设置',
            visualDensity: isNarrow ? VisualDensity.compact : null,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => SettingsDialog.show(context),
          ),
          const SizedBox(width: 2),

          // 用户身份状态与登录入口（移动小屏自适应隐藏冗余昵称文本，仅展示头像）
          if (auth.isLoggedIn && auth.currentUser != null)
            PopupMenuButton<String>(
              tooltip: '用户中心',
              padding: EdgeInsets.zero,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: isNarrow ? 6 : 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: isNarrow ? 14 : 16,
                      backgroundColor: colorScheme.primary.withAlpha(40),
                      backgroundImage: auth.currentUser!.avatarUrl.isNotEmpty
                          ? NetworkImage(auth.currentUser!.avatarUrl, headers: AppNetworkImage.neteaseHeaders)
                          : null,
                      child: auth.currentUser!.avatarUrl.isEmpty
                          ? Icon(Icons.person, size: isNarrow ? 16 : 18, color: colorScheme.primary)
                          : null,
                    ),
                    if (!isNarrow) ...[
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 80),
                        child: Text(
                          auth.currentUser!.nickname,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              itemBuilder: (_) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text('用户 ID: ${auth.currentUser!.userId}'),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'logout',
                  child: const Row(
                    children: [
                      Icon(Icons.logout, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('退出登录', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
              onSelected: (val) {
                if (val == 'logout') {
                  auth.logout();
                  context.read<HomeProvider>().loadUserLibrary(null);
                }
              },
            )
          else
            isNarrow
                ? IconButton(
                    tooltip: '登录',
                    icon: const Icon(Icons.login_rounded),
                    onPressed: () => LoginDialog.show(context),
                  )
                : TextButton.icon(
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: const Text('登录'),
                    onPressed: () => LoginDialog.show(context),
                  ),
          SizedBox(width: isNarrow ? 6 : 8),
        ],
      ),
      body: Row(
        children: [
          // 桌面端大屏 NavigationRail
          if (isDesktop)
            NavigationRail(
              selectedIndex: _currentIndex,
              onDestinationSelected: (idx) {
                setState(() => _currentIndex = idx);
              },
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.queue_music_outlined),
                  selectedIcon: Icon(Icons.queue_music),
                  label: Text('歌单'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.podcasts_outlined),
                  selectedIcon: Icon(Icons.podcasts),
                  label: Text('播客'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.search_outlined),
                  selectedIcon: Icon(Icons.search),
                  label: Text('搜索'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.sync_alt_outlined),
                  selectedIcon: Icon(Icons.sync_alt_rounded),
                  label: Text('歌单同步'),
                ),
              ],
            ),

          // 主体分页内容
          Expanded(
            child: Stack(
              children: [
                IndexedStack(
                  index: _currentIndex,
                  children: _tabs,
                ),
                // 底部浮动试听条
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AudioPreviewBar(),
                ),
              ],
            ),
          ),
        ],
      ),
      // 移动端/窄屏底部 NavigationBar
      bottomNavigationBar: isDesktop
          ? null
          : NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (idx) {
                setState(() => _currentIndex = idx);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.queue_music_outlined),
                  selectedIcon: Icon(Icons.queue_music),
                  label: '歌单',
                ),
                NavigationDestination(
                  icon: Icon(Icons.podcasts_outlined),
                  selectedIcon: Icon(Icons.podcasts),
                  label: '播客',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search_outlined),
                  selectedIcon: Icon(Icons.search),
                  label: '搜索',
                ),
                NavigationDestination(
                  icon: Icon(Icons.sync_alt_outlined),
                  selectedIcon: Icon(Icons.sync_alt_rounded),
                  label: '歌单同步',
                ),
              ],
            ),
    );
  }
}