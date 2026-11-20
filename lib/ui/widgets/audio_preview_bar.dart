import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/player_provider.dart';
import '../detail/fullscreen_player_screen.dart';
import 'app_network_image.dart';

/// 全局底部浮动试听控制栏
/// 支持拖拽进度条调进度、显示时长、上一首/暂停/下一首完整切歌控制，点击直接展开全屏歌词预览
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

    final isNarrow = MediaQuery.of(context).size.width < 400;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const FullscreenPlayerScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position:
                        Tween<Offset>(
                          begin: const Offset(0, 1),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                    child: child,
                  );
                },
          ),
        );
      },
      child: Container(
        margin: EdgeInsets.fromLTRB(
          isNarrow ? 8 : 12,
          4,
          isNarrow ? 8 : 12,
          isNarrow ? 6 : 10,
        ),
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
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 10,
                  ),
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
              padding: EdgeInsets.symmetric(
                horizontal: isNarrow ? 8 : 12,
                vertical: 4,
              ),
              child: Row(
                children: [
                  // 封面
                  AppNetworkImage(
                    url: song.albumCoverUrl,
                    width: isNarrow ? 38 : 42,
                    height: isNarrow ? 38 : 42,
                    borderRadius: BorderRadius.circular(8),
                    fallback: _buildFallbackCover(
                      colorScheme,
                      isNarrow ? 38 : 42,
                    ),
                  ),
                  SizedBox(width: isNarrow ? 8 : 12),

                  // 歌曲名与歌手、时长（自适应弹性布局，防小屏溢出）
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          song.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: isNarrow ? 13 : 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                player.errorMessage ?? song.artistString,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 10.5,
                                  color: player.errorMessage != null
                                      ? colorScheme.error
                                      : theme.textTheme.bodySmall?.color
                                            ?.withAlpha(160),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${_formatDuration(player.position)} / ${_formatDuration(player.duration)}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 上一首按钮
                  IconButton(
                    tooltip: '上一首',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    icon: Icon(
                      Icons.skip_previous_rounded,
                      size: isNarrow ? 22 : 24,
                      color: player.canSwitch
                          ? colorScheme.onSurface
                          : colorScheme.onSurface.withAlpha(80),
                    ),
                    onPressed: player.canSwitch
                        ? () => player.playPrevious()
                        : null,
                  ),

                  // 播放 / 暂停按钮
                  IconButton(
                    tooltip: player.isPlaying ? '暂停' : '播放',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: player.isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            player.isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            color: colorScheme.primary,
                            size: isNarrow ? 30 : 34,
                          ),
                    onPressed: () => player.togglePlayPause(),
                  ),

                  // 下一首按钮
                  IconButton(
                    tooltip: '下一首',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    icon: Icon(
                      Icons.skip_next_rounded,
                      size: isNarrow ? 22 : 24,
                      color: player.canSwitch
                          ? colorScheme.onSurface
                          : colorScheme.onSurface.withAlpha(80),
                    ),
                    onPressed: player.canSwitch
                        ? () => player.playNext()
                        : null,
                  ),

                  // 关闭试听条
                  IconButton(
                    tooltip: '关闭试听',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    icon: const Icon(Icons.close, size: 18),
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

  Widget _buildFallbackCover(ColorScheme colorScheme, double size) {
    return Container(
      width: size,
      height: size,
      color: colorScheme.primary.withAlpha(30),
      child: Icon(
        Icons.music_note,
        color: colorScheme.primary,
        size: size * 0.5,
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
