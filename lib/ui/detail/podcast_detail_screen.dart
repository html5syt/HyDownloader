import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/podcast.dart';
import '../../providers/download_provider.dart';
import '../../services/netease/music_service.dart';
import '../widgets/song_tile.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/audio_preview_bar.dart';
import '../widgets/app_network_image.dart';

/// 播客/电台详情页面
/// 展示播客包含的声音节目列表，提供试听与单期/批量下载
class PodcastDetailScreen extends StatefulWidget {
  final Podcast podcast;

  const PodcastDetailScreen({super.key, required this.podcast});

  @override
  State<PodcastDetailScreen> createState() => _PodcastDetailScreenState();
}

class _PodcastDetailScreenState extends State<PodcastDetailScreen> {
  final NeteaseMusicService _musicService = NeteaseMusicService.instance;
  List<PodcastProgram> _programs = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPrograms();
  }

  Future<void> _loadPrograms() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final progs = await _musicService.getPodcastPrograms(widget.podcast.id);
      if (!mounted) return;
      setState(() {
        _programs = progs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '加载播客节目失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final download = context.read<DownloadProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.podcast.name),
        actions: [
          if (_programs.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('下载全部节目'),
              onPressed: () async {
                final songs = _programs.map((p) => p.mainSong).toList();
                await download.downloadSongs(songs);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已添加 ${songs.length} 个节目至下载队列')),
                  );
                }
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? EmptyStateView(
                      icon: Icons.error_outline,
                      title: '加载失败',
                      subtitle: _errorMessage,
                      actionText: '重试',
                      onAction: _loadPrograms,
                    )
                  : _programs.isEmpty
                      ? const EmptyStateView(
                          icon: Icons.podcasts,
                          title: '暂无声音节目',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 96),
                          itemCount: _programs.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              // 顶部电台信息头部
                              return Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Row(
                                  children: [
                                    AppNetworkImage(
                                      url: widget.podcast.coverUrl,
                                      width: 80,
                                      height: 80,
                                      borderRadius: BorderRadius.circular(12),
                                      fallback: Container(
                                        width: 80,
                                        height: 80,
                                        color: colorScheme.surfaceContainerHighest,
                                        child: const Icon(Icons.podcasts, size: 36),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            widget.podcast.name,
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '主播: ${widget.podcast.djName.isEmpty ? "电台主播" : widget.podcast.djName}',
                                            style: theme.textTheme.bodySmall,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '共 ${_programs.length} 期声音节目',
                                            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.primary),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final program = _programs[index - 1];
                            return SongTile(
                              song: program.mainSong,
                              index: index,
                              playlistContext: _programs.map((p) => p.mainSong).toList(),
                            );
                          },
                        ),

          // 底部试听浮动条
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AudioPreviewBar(),
          ),
        ],
      ),
    );
  }
}
