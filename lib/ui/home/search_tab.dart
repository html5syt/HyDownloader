import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/search_result.dart';
import '../../providers/home_provider.dart';
import '../widgets/song_tile.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/app_network_image.dart';
import '../detail/playlist_detail_screen.dart';
import '../detail/podcast_detail_screen.dart';

/// 首页“搜索发现”展示 Tab
/// 提供单曲、歌单、播客三维度的全网在线检索
class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final TextEditingController _searchController = TextEditingController();
  SearchType _selectedType = SearchType.song;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _executeSearch() {
    final text = _searchController.text.trim();
    if (text.isNotEmpty) {
      context.read<HomeProvider>().search(text, _selectedType);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final home = context.watch<HomeProvider>();

    return Column(
      children: [
        // 顶部搜索框与分类选择器
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _executeSearch(),
                decoration: InputDecoration(
                  hintText: '搜索歌曲、歌手、歌单或播客...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            home.clearSearch();
                          },
                        )
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              SegmentedButton<SearchType>(
                segments: const [
                  ButtonSegment(value: SearchType.song, label: Text('单曲'), icon: Icon(Icons.music_note)),
                  ButtonSegment(value: SearchType.playlist, label: Text('歌单'), icon: Icon(Icons.queue_music)),
                  ButtonSegment(value: SearchType.podcast, label: Text('播客'), icon: Icon(Icons.podcasts)),
                ],
                selected: {_selectedType},
                onSelectionChanged: (newSelection) {
                  setState(() {
                    _selectedType = newSelection.first;
                  });
                  _executeSearch();
                },
              ),
            ],
          ),
        ),

        // 搜索结果展示区
        Expanded(
          child: home.isSearching
              ? const Center(child: CircularProgressIndicator())
              : home.errorMessage != null
                  ? EmptyStateView(
                      icon: Icons.error_outline,
                      title: '搜索异常',
                      subtitle: home.errorMessage,
                      actionText: '重试',
                      onAction: _executeSearch,
                    )
                  : _buildResultsView(home, colorScheme),
        ),
      ],
    );
  }

  Widget _buildResultsView(HomeProvider home, ColorScheme colorScheme) {
    final result = home.searchResult;

    if (result.keyword.isEmpty) {
      return const EmptyStateView(
        icon: Icons.manage_search,
        title: '输入关键词搜索',
        subtitle: '支持搜索网易云音乐全部在线歌曲、歌单与播客电台',
      );
    }

    switch (_selectedType) {
      case SearchType.song:
        if (result.songs.isEmpty) {
          return const EmptyStateView(icon: Icons.music_off, title: '未找到相关歌曲');
        }
        return ListView.builder(
          itemCount: result.songs.length,
          itemBuilder: (context, index) {
            return SongTile(
              song: result.songs[index],
              index: index + 1,
              playlistContext: result.songs,
            );
          },
        );

      case SearchType.playlist:
        if (result.playlists.isEmpty) {
          return const EmptyStateView(icon: Icons.queue_music, title: '未找到相关歌单');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: result.playlists.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final pl = result.playlists[index];
            return ListTile(
              leading: AppNetworkImage(
                url: pl.coverImgUrl,
                width: 48,
                height: 48,
                borderRadius: BorderRadius.circular(8),
              ),
              title: Text(pl.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${pl.creatorName} · ${pl.trackCount} 首歌曲'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlist: pl)),
                );
              },
            );
          },
        );

      case SearchType.podcast:
        if (result.podcasts.isEmpty) {
          return const EmptyStateView(icon: Icons.podcasts, title: '未找到相关播客');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: result.podcasts.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final pod = result.podcasts[index];
            return ListTile(
              leading: AppNetworkImage(
                url: pod.coverUrl,
                width: 48,
                height: 48,
                borderRadius: BorderRadius.circular(8),
              ),
              title: Text(pod.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('主播: ${pod.djName} · ${pod.programCount} 期'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PodcastDetailScreen(podcast: pod)),
                );
              },
            );
          },
        );
    }
  }
}
