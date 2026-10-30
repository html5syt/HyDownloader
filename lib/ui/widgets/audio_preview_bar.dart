import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/player_provider.dart';

/// 全局底部浮动试听控制栏
/// 用户在任何页面试听曲目时，底部平滑滑出展示当前进度与控制按钮
class AudioPreviewBar extends StatelessWidget {
  const AudioPreviewBar({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final song = player.currentSong;

    if (song == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final posMs = player.position.inMilliseconds.toDouble();
    final durMs = player.duration.inMilliseconds.toDouble();
    final progress = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(30),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(60)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 细进度条
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 2.5,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(colorScheme.primary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                // 封面
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: song.albumCoverUrl.isNotEmpty
                      ? Image.network(
                          song.albumCoverUrl,
                          width: 42,
                          height: 42,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _buildFallbackCover(colorScheme),
                        )
                      : _buildFallbackCover(colorScheme),
                ),
                const SizedBox(width: 12),

                // 歌曲名与歌手
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        song.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${song.artistString}  ${_formatDuration(player.position)} / ${_formatDuration(player.duration)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.textTheme.bodySmall?.color?.withAlpha(160),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // 播放 / 暂停按钮
                IconButton(
                  icon: player.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          player.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                          color: colorScheme.primary,
                          size: 32,
                        ),
                  onPressed: () => player.togglePlayPause(),
                ),

                // 关闭试听条
                IconButton(
                  tooltip: '关闭试听',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => player.stop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackCover(ColorScheme colorScheme) {
    return Container(
      width: 42,
      height: 42,
      color: colorScheme.primary.withAlpha(30),
      child: Icon(Icons.music_note, color: colorScheme.primary, size: 22),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}


