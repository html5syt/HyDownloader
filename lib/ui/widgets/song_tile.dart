import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../providers/download_provider.dart';
import 'app_network_image.dart';

/// 通用歌曲列表项组件
/// 支持单曲播放试听与一键下载，并支持接收歌单上下文以实现连续切歌
class SongTile extends StatelessWidget {
  /// 歌曲数据模型
  final Song song;

  /// 显示的歌曲序号（可选）
  final int? index;

  /// 当前歌单上下文列表（用于支持上一首/下一首连续播放）
  final List<Song>? playlistContext;

  /// 是否展示多选复选框（用于批量下载场景）
  final bool showCheckbox;

  /// 复选框是否选中
  final bool isSelected;

  /// 复选框状态切换回调
  final ValueChanged<bool?>? onSelectChanged;

  const SongTile({
    super.key,
    required this.song,
    this.index,
    this.playlistContext,
    this.showCheckbox = false,
    this.isSelected = false,
    this.onSelectChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final playerProvider = context.watch<PlayerProvider>();
    final downloadProvider = context.watch<DownloadProvider>();

    final isCurrentPlaying = playerProvider.currentSong?.id == song.id;
    final isPlaying = isCurrentPlaying && playerProvider.isPlaying;
    final isLoading = isCurrentPlaying && playerProvider.isLoading;

    // 检查是否已经在下载队列中
    final isQueued = downloadProvider.tasks.any((t) => t.song.id == song.id);

    return InkWell(
      onTap: () {
        if (showCheckbox) {
          onSelectChanged?.call(!isSelected);
        } else {
          playerProvider.playSong(song, contextPlaylist: playlistContext);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // 序号或复选框
            if (showCheckbox)
              Checkbox(
                value: isSelected,
                onChanged: onSelectChanged,
              )
            else if (index != null)
              SizedBox(
                width: 32,
                child: Text(
                  index.toString().padLeft(2, '0'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isCurrentPlaying ? colorScheme.primary : Colors.grey,
                    fontWeight: isCurrentPlaying ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),

            // 封面（使用 AppNetworkImage 带有 anti-hotlink 请求头）
            if (song.albumCoverUrl.isNotEmpty) ...[
              AppNetworkImage(
                url: song.albumCoverUrl,
                width: 44,
                height: 44,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(width: 12),
            ],

            // 歌名与歌手信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          song.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: isCurrentPlaying ? colorScheme.primary : null,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (song.isVipRequired) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.amber.withAlpha(40),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.amber, width: 0.8),
                          ),
                          child: const Text(
                            'VIP',
                            style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${song.artistString} · ${song.albumName.isEmpty ? "单曲" : song.albumName}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withAlpha(180),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // 试听播放按钮
            IconButton(
              tooltip: isPlaying ? '暂停试听' : '在线试听',
              icon: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      isPlaying ? Icons.pause_circle_filled : Icons.play_circle_outline,
                      color: isCurrentPlaying ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      size: 26,
                    ),
              onPressed: () {
                playerProvider.playSong(song, contextPlaylist: playlistContext);
              },
            ),

            // 单曲下载按钮
            IconButton(
              tooltip: isQueued ? '已在下载队列' : '立即下载',
              icon: Icon(
                isQueued ? Icons.check_circle : Icons.download_rounded,
                color: isQueued ? Colors.green : colorScheme.onSurfaceVariant,
                size: 22,
              ),
              onPressed: () async {
                await downloadProvider.downloadSong(song);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已将《${song.name}》加入下载队列'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
