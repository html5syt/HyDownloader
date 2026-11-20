import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/song.dart';
import 'app_network_image.dart';

/// 根据实际可用高度缩放封面，放大字体或极矮窗口下仍可滚动查看曲目信息。
class PlayerCover extends StatelessWidget {
  final Song song;
  final bool compact;
  const PlayerCover({super.key, required this.song, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final titleSize = compact ? 18.0 : 22.0;
    final gap = compact ? 12.0 : 24.0;
    final verticalPadding = compact ? 8.0 : 24.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 为两行歌名、一行歌手及间距预留高度，封面不能再固定占用 160/260px。
        final textHeight =
            scaler.scale(titleSize) * 2.5 + scaler.scale(14) * 1.25;
        final availableHeight =
            constraints.maxHeight - verticalPadding * 2 - textHeight - gap - 8;
        final size = math.min(
          math.min(
            compact ? 160.0 : 260.0,
            math.max(0.0, constraints.maxWidth - 48),
          ),
          math.max(48.0, availableHeight),
        );
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 24,
                vertical: verticalPadding,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.cyanAccent.withAlpha(80),
                          blurRadius: 36,
                          spreadRadius: 4,
                        ),
                        BoxShadow(
                          color: Colors.blue.withAlpha(120),
                          blurRadius: 20,
                        ),
                      ],
                      border: Border.all(
                        color: Colors.white.withAlpha(180),
                        width: 3,
                      ),
                    ),
                    child: ClipOval(
                      child: song.albumCoverUrl.isNotEmpty
                          ? AppNetworkImage(
                              url: song.albumCoverUrl,
                              fit: BoxFit.cover,
                            )
                          : Container(color: Colors.blueGrey),
                    ),
                  ),
                  SizedBox(height: gap),
                  Text(
                    song.name,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: titleSize,
                      height: 1.25,
                      letterSpacing: 0.5,
                      fontFamilyFallback: AppTheme.fontFallbacks,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${song.artistString}${song.albumName.isEmpty ? '' : ' · ${song.albumName}'}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.25,
                      fontFamilyFallback: AppTheme.fontFallbacks,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
