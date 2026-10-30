import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/podcast.dart';
import '../../providers/home_provider.dart';
import '../../providers/auth_provider.dart';
import '../widgets/empty_state_view.dart';
import '../detail/podcast_detail_screen.dart';
import '../login/login_dialog.dart';

/// 首页“收藏播客”展示 Tab
/// 展示用户收藏的网易云电台与播客节目专栏
class PodcastTab extends StatelessWidget {
  const PodcastTab({super.key});

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();
    final auth = context.watch<AuthProvider>();

    if (!auth.isLoggedIn) {
      return EmptyStateView(
        icon: Icons.podcasts,
        title: '尚未登录账号',
        subtitle: '登录后即可同步您收藏的播客电台与声音节目',
        actionText: '立即登录',
        onAction: () => LoginDialog.show(context),
      );
    }

    if (home.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (home.podcasts.isEmpty) {
      return const EmptyStateView(
        icon: Icons.podcasts_outlined,
        title: '暂未收藏任何播客',
        subtitle: '您可以在网易云音乐中收藏电台，或使用搜索功能查找电台节目',
      );
    }

    return RefreshIndicator(
      onRefresh: () => home.loadUserLibrary(auth.currentUser?.userId),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: home.podcasts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final podcast = home.podcasts[index];
          return _buildPodcastItem(context, podcast);
        },
      ),
    );
  }

  Widget _buildPodcastItem(BuildContext context, Podcast podcast) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PodcastDetailScreen(podcast: podcast)),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant.withAlpha(50)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: podcast.coverUrl.isNotEmpty
                  ? Image.network(
                      podcast.coverUrl,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => _buildFallback(colorScheme),
                    )
                  : _buildFallback(colorScheme),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    podcast.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '主播: ${podcast.djName.isEmpty ? "电台主播" : podcast.djName}',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '共 ${podcast.programCount} 期声音节目',
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.primary, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildFallback(ColorScheme colorScheme) {
    return Container(
      width: 60,
      height: 60,
      color: colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.podcasts, size: 28),
    );
  }
}
