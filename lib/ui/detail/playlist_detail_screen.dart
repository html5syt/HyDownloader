import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/playlist.dart';
import '../../models/song.dart';
import '../../config/app_constants.dart';
import '../../providers/download_provider.dart';
import '../../providers/sync_provider.dart';
import '../../services/netease/music_service.dart';
import '../widgets/song_tile.dart';
import '../widgets/empty_state_view.dart';
import '../sync/sync_screen.dart';

/// 歌单详情页面
/// 展示歌单全部歌曲，提供单曲试听、单曲下载、批量下载与一键同步入口
class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final NeteaseMusicService _musicService = NeteaseMusicService.instance;
  List<Song> _songs = [];
  bool _isLoading = true;
  String? _errorMessage;

  // 批量选择模式
  bool _isSelectionMode = false;
  final Set<String> _selectedSongIds = {};

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final songs = await _musicService.getPlaylistSongs(widget.playlist.id);
      if (!mounted) return;
      setState(() {
        _songs = songs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '加载歌曲列表失败: $e';
      });
    }
  }

  /// 弹出音质选择弹窗并执行下载
  Future<void> _showQualityPickerAndDownload(List<Song> targetSongs) async {
    if (targetSongs.isEmpty) return;

    final chosenQuality = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('选择下载音质 (${targetSongs.length} 首)'),
        children: AudioQuality.availableQualities.map((q) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, q.level),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.music_note, size: 20),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(q.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(q.description, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );

    if (chosenQuality != null && mounted) {
      final download = context.read<DownloadProvider>();
      await download.downloadSongs(targetSongs, quality: chosenQuality);

      if (mounted) {
        setState(() {
          _isSelectionMode = false;
          _selectedSongIds.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已添加 ${targetSongs.length} 首歌曲至下载队列'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 顶部歌单信息 AppBar
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.playlist.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // 背景封面毛玻璃
                  if (widget.playlist.coverImgUrl.isNotEmpty)
                    Image.network(
                      widget.playlist.coverImgUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(color: colorScheme.surfaceContainerHighest),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withAlpha(100),
                          Colors.black.withAlpha(220),
                        ],
                      ),
                    ),
                  ),
                  // 前景歌单信息
                  Positioned(
                    left: 20,
                    bottom: 50,
                    right: 20,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: widget.playlist.coverImgUrl.isNotEmpty
                              ? Image.network(
                                  widget.playlist.coverImgUrl,
                                  width: 90,
                                  height: 90,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => _buildFallbackCover(colorScheme),
                                )
                              : _buildFallbackCover(colorScheme),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.playlist.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${widget.playlist.creatorName} · 共 ${_songs.isEmpty ? widget.playlist.trackCount : _songs.length} 首歌曲',
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              // 同步此歌单快捷按钮
              IconButton(
                tooltip: '同步此歌单到本地文件夹',
                icon: const Icon(Icons.sync_alt_rounded),
                onPressed: () {
                  final sync = context.read<SyncProvider>();
                  sync.setPlaylist(widget.playlist);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SyncScreen()),
                  );
                },
              ),
            ],
          ),

          // 批量操作控制栏
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  if (_isSelectionMode) ...[
                    Checkbox(
                      value: _selectedSongIds.length == _songs.length && _songs.isNotEmpty,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedSongIds.addAll(_songs.map((s) => s.id));
                          } else {
                            _selectedSongIds.clear();
                          }
                        });
                      },
                    ),
                    Text('已选择 ${_selectedSongIds.length} 首'),
                    const Spacer(),
                    FilledButton.icon(
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('下载所选'),
                      onPressed: _selectedSongIds.isEmpty
                          ? null
                          : () {
                              final targets = _songs.where((s) => _selectedSongIds.contains(s.id)).toList();
                              _showQualityPickerAndDownload(targets);
                            },
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      child: const Text('取消'),
                      onPressed: () {
                        setState(() {
                          _isSelectionMode = false;
                          _selectedSongIds.clear();
                        });
                      },
                    ),
                  ] else ...[
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('全部下载'),
                      onPressed: _songs.isEmpty ? null : () => _showQualityPickerAndDownload(_songs),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.checklist, size: 18),
                      label: const Text('批量选择'),
                      onPressed: _songs.isEmpty
                          ? null
                          : () {
                              setState(() {
                                _isSelectionMode = true;
                              });
                            },
                    ),
                    const Spacer(),
                    Text(
                      '共 ${_songs.length} 首歌',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // 歌曲列表区域
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorMessage != null)
            SliverFillRemaining(
              child: EmptyStateView(
                icon: Icons.error_outline,
                title: '获取歌单失败',
                subtitle: _errorMessage,
                actionText: '重试',
                onAction: _loadSongs,
              ),
            )
          else if (_songs.isEmpty)
            const SliverFillRemaining(
              child: EmptyStateView(
                icon: Icons.music_off_outlined,
                title: '歌单内暂无曲目',
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final song = _songs[index];
                  return SongTile(
                    song: song,
                    index: index + 1,
                    showCheckbox: _isSelectionMode,
                    isSelected: _selectedSongIds.contains(song.id),
                    onSelectChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedSongIds.add(song.id);
                        } else {
                          _selectedSongIds.remove(song.id);
                        }
                      });
                    },
                  );
                },
                childCount: _songs.length,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFallbackCover(ColorScheme colorScheme) {
    return Container(
      width: 90,
      height: 90,
      color: colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.queue_music, size: 40),
    );
  }
}


