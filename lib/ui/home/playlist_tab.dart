import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/playlist.dart';
import '../../providers/home_provider.dart';
import '../../providers/auth_provider.dart';
import '../widgets/empty_state_view.dart';
import '../detail/playlist_detail_screen.dart';
import '../login/login_dialog.dart';

/// 首页“我的歌单”展示 Tab
/// 重点突出“我喜欢的音乐”，网格与列表自适应展示用户的全部歌单
class PlaylistTab extends StatelessWidget {
  const PlaylistTab({super.key});

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();
    final auth = context.watch<AuthProvider>();

    if (!auth.isLoggedIn) {
      return EmptyStateView(
        icon: Icons.account_circle_outlined,
        title: '尚未登录账号',
        subtitle: '登录后即可浏览您的网易云歌单，包含“我喜欢的音乐”',
        actionText: '立即登录',
        onAction: () => LoginDialog.show(context),
      );
    }

    if (home.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (home.errorMessage != null) {
      return EmptyStateView(
        icon: Icons.error_outline,
        title: '加载歌单失败',
        subtitle: home.errorMessage,
        actionText: '重试',
        onAction: () => home.loadUserLibrary(auth.currentUser?.userId),
      );
    }

    if (home.playlists.isEmpty) {
      return const EmptyStateView(
        icon: Icons.queue_music,
        title: '暂未获取到歌单',
        subtitle: '如果您使用了虚拟设备令牌，可通过上方搜索栏直接检索任意歌单或单曲',
      );
    }

    final likedSongs = home.likedSongsPlaylist;
    final otherPlaylists = home.playlists.where((p) => !p.isLikedSongs).toList();

    return RefreshIndicator(
      onRefresh: () => home.loadUserLibrary(auth.currentUser?.userId),
      child: CustomScrollView(
        slivers: [
          // 顶部“我喜欢的音乐”特型展示卡片
          if (likedSongs != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: _buildLikedSongsCard(context, likedSongs),
              ),
            ),

          // 其它歌单网格展示
          SliverPadding(
            padding: const EdgeInsets.all(16.0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.76,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final playlist = otherPlaylists[index];
                  return _buildPlaylistCard(context, playlist);
                },
                childCount: otherPlaylists.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建“我喜欢的音乐”特色卡片
  Widget _buildLikedSongsCard(BuildContext context, Playlist playlist) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlist: playlist)),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE53935), Color(0xFFFF7043)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withAlpha(50),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(50),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.favorite, color: Colors.white, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '我喜欢的音乐',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '共 ${playlist.trackCount} 首歌曲 · 点击进入下载或试听',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    );
  }

  /// 构建普通歌单卡片
  Widget _buildPlaylistCard(BuildContext context, Playlist playlist) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlist: playlist)),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面图片
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  playlist.coverImgUrl.isNotEmpty
                      ? Image.network(
                          playlist.coverImgUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _buildFallback(colorScheme),
                        )
                      : _buildFallback(colorScheme),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(150),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.music_note, size: 12, color: Colors.white70),
                          const SizedBox(width: 2),
                          Text(
                            '${playlist.trackCount}',
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 歌单标题
          Text(
            playlist.name,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFallback(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.queue_music, size: 36),
    );
  }
}

