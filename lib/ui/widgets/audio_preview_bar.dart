import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/player_provider.dart';
import '../detail/fullscreen_player_screen.dart';
import 'app_network_image.dart';

/// 全局底部浮动试听控制栏
/// 支持拖拽进度条调进度、显示时长、点击直接展开类似 HyPlayer 的全屏歌词预览
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
    final sliderMax = durMs > 0 ? durMs : 1.0;
    final sliderVal = posMs.clamp(0.0, sliderMax);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const FullscreenPlayerScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                child: child,
              );
            },
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
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
            // 可拖拽的试听进度条
            SizedBox(
              height: 14,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.5,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                  activeTrackColor: colorScheme.primary,
                  inactiveTrackColor: colorScheme.primary.withAlpha(30),
                  thumbColor: colorScheme.primary,
                ),
                child: Slider(
                  value: sliderVal,
                  min: 0.0,
                  max: sliderMax,
                  onChanged: (val) {
                    player.seek(Duration(milliseconds: val.toInt()));
                  },
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                children: [
                  // 封面 (使用防盗链 AppNetworkImage)
                  AppNetworkImage(
                    url: song.albumCoverUrl,
                    width: 44,
                    height: 44,
                    borderRadius: BorderRadius.circular(8),
                    fallback: _buildFallbackCover(colorScheme),
                  ),
                  const SizedBox(width: 12),

                  // 歌曲名与歌手、时长
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
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                song.artistString,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: theme.textTheme.bodySmall?.color?.withAlpha(160),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 显示具体时长进度 (例如 0:31 / 2:54)
                            Text(
                              '${_formatDuration(player.position)} / ${_formatDuration(player.duration)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 全屏预览图标提示
                  IconButton(
                    tooltip: '全屏歌词预览',
                    icon: const Icon(Icons.fullscreen, size: 24),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const FullscreenPlayerScreen()),
                      );
                    },
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
                            size: 34,
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
      ),
    );
  }

  Widget _buildFallbackCover(ColorScheme colorScheme) {
    return Container(
      width: 44,
      height: 44,
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
