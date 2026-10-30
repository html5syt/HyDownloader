import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../providers/download_provider.dart';
import '../../services/netease/lyric_service.dart';
import '../widgets/app_network_image.dart';

/// 类似 HyPlayer 沉浸式全屏试听与歌词预览视图
/// 包含全景毛玻璃背景、左侧发光黑胶/圆形封面、右侧实时滚动歌词与底部沉浸式播放控制条
class FullscreenPlayerScreen extends StatefulWidget {
  const FullscreenPlayerScreen({super.key});

  @override
  State<FullscreenPlayerScreen> createState() => _FullscreenPlayerScreenState();
}

class _FullscreenPlayerScreenState extends State<FullscreenPlayerScreen> {
  final NeteaseLyricService _lyricService = NeteaseLyricService.instance;
  final ScrollController _lyricScrollController = ScrollController();

  /// 每一行歌词的标准行高，用于精确计算垂直居中偏移
  static const double _lyricItemHeight = 56.0;

  String? _loadedSongId;
  List<LyricLine> _lyrics = [];
  bool _isLoadingLyrics = true;
  int _currentLyricIndex = -1;

  @override
  void initState() {
    super.initState();
    _fetchLyrics();
  }

  @override
  void dispose() {
    _lyricScrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchLyrics() async {
    final player = context.read<PlayerProvider>();
    final song = player.currentSong;
    if (song == null) return;

    if (_loadedSongId == song.id) return;
    _loadedSongId = song.id;

    setState(() {
      _isLoadingLyrics = true;
      _lyrics = [];
      _currentLyricIndex = -1;
    });

    try {
      final lrc = await _lyricService.getFormattedLrc(songId: song.id);
      if (!mounted) return;
      if (lrc != null && lrc.trim().isNotEmpty) {
        final parsed = _parseLrc(lrc);
        setState(() {
          _lyrics = parsed;
          _isLoadingLyrics = false;
        });
      } else {
        setState(() {
          _lyrics = [LyricLine(timeMs: 0, timeTag: '00:00.00', text: '纯音乐，请欣赏')];
          _isLoadingLyrics = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lyrics = [LyricLine(timeMs: 0, timeTag: '00:00.00', text: '暂无歌词')];
        _isLoadingLyrics = false;
      });
    }
  }

  List<LyricLine> _parseLrc(String text) {
    final lines = <LyricLine>[];
    final regExp = RegExp(r'\[(\d{2}):(\d{2})\.?(\d{2,3})?\](.*)');
    for (final raw in text.split('\n')) {
      final trimmed = raw.trim();
      final match = regExp.firstMatch(trimmed);
      if (match != null) {
        final m = int.tryParse(match.group(1) ?? '0') ?? 0;
        final s = int.tryParse(match.group(2) ?? '0') ?? 0;
        final msPart = match.group(3) ?? '00';
        final ms = int.tryParse(msPart.padRight(3, '0').substring(0, 3)) ?? 0;
        final timeMs = m * 60 * 1000 + s * 1000 + ms;
        var lineText = (match.group(4) ?? '').trim();
        // 规整全角标点符号周围的空格，防止字体渲染时产生异常空隙
        lineText = lineText
            .replaceAll(' ，', '，')
            .replaceAll(' ,', '，')
            .replaceAll(' , ', '，')
            .replaceAll('  ', ' ')
            .trim();

        if (lineText.isNotEmpty) {
          lines.add(LyricLine(
            timeMs: timeMs,
            timeTag: '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
            text: lineText,
          ));
        }
      }
    }
    lines.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return lines;
  }

  void _updateActiveLyric(Duration position) {
    if (_lyrics.isEmpty) return;

    final posMs = position.inMilliseconds;
    int activeIdx = -1;
    for (int i = 0; i < _lyrics.length; i++) {
      if (_lyrics[i].timeMs <= posMs) {
        activeIdx = i;
      } else {
        break;
      }
    }

    if (activeIdx != _currentLyricIndex && activeIdx >= 0) {
      _currentLyricIndex = activeIdx;
      // 自动平滑滚动使得当前歌词精确在垂直中线对齐
      if (_lyricScrollController.hasClients) {
        final targetOffset = activeIdx * _lyricItemHeight;
        _lyricScrollController.animateTo(
          targetOffset.clamp(0.0, _lyricScrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final download = context.read<DownloadProvider>();
    final song = player.currentSong;

    if (song == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return const SizedBox.shrink();
    }

    // 若切歌则重新拉取歌词
    if (_loadedSongId != song.id) {
      _fetchLyrics();
    }

    _updateActiveLyric(player.position);

    final isWide = MediaQuery.of(context).size.width >= 720;
    final posMs = player.position.inMilliseconds.toDouble();
    final durMs = player.duration.inMilliseconds.toDouble();
    final sliderMax = durMs > 0 ? durMs : 1.0;
    final sliderVal = posMs.clamp(0.0, sliderMax);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. 全屏毛玻璃虚化背景
          if (song.albumCoverUrl.isNotEmpty)
            AppNetworkImage(
              url: song.albumCoverUrl,
              fit: BoxFit.cover,
            )
          else
            Container(color: const Color(0xFF0D1B2A)),

          // 渐变与模糊遮罩
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF0A192F).withAlpha(220),
                    const Color(0xFF0D253F).withAlpha(240),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

          // 2. 主体区域
          SafeArea(
            child: Column(
              children: [
                // 顶部工具栏 (缩小返回)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '收起全屏',
                        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 28),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '下载此曲',
                        icon: const Icon(Icons.download_rounded, color: Colors.white70),
                        onPressed: () async {
                          await download.downloadSong(song);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已将《${song.name}》加入下载队列')),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),

                // 中间展示区：左侧圆形封面 + 右侧垂直居中对齐歌词
                Expanded(
                  child: isWide
                      ? Row(
                          children: [
                            // 左侧：封面与歌曲大标题 (类似 HyPlayer 经典设计)
                            Expanded(
                              flex: 5,
                              child: _buildCoverAndTitle(song),
                            ),
                            // 右侧：实时歌词（中间垂直对齐）
                            Expanded(
                              flex: 5,
                              child: _buildLyricsView(player),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(flex: 4, child: _buildCoverAndTitle(song, compact: true)),
                            Expanded(flex: 5, child: _buildLyricsView(player)),
                          ],
                        ),
                ),

                // 3. 底部进度条与控制栏
                _buildBottomControls(player, sliderVal, sliderMax),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建左侧圆形发光封面与曲目信息
  Widget _buildCoverAndTitle(Song song, {bool compact = false}) {
    final size = compact ? 160.0 : 260.0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 圆形带发光光晕的封面 (完全还原 Image 1 视觉特点)
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
                border: Border.all(color: Colors.white.withAlpha(180), width: 3),
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
            const SizedBox(height: 24),

            // 歌曲名
            Text(
              song.name,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: compact ? 18 : 22,
                letterSpacing: 0.5,
                fontFamilyFallback: AppTheme.fontFallbacks,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),

            // 歌手名与专辑
            Text(
              '${song.artistString}  ${song.albumName.isEmpty ? "" : "· ${song.albumName}"}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontFamilyFallback: AppTheme.fontFallbacks,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建右侧歌词滚动区域 (通过动态内边距实现当前歌词行在视口正中垂直对齐)
  Widget _buildLyricsView(PlayerProvider player) {
    if (_isLoadingLyrics) {
      return const Center(child: CircularProgressIndicator(color: Colors.white70));
    }

    if (_lyrics.isEmpty) {
      return const Center(
        child: Text(
          '纯音乐，请欣赏',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamilyFallback: AppTheme.fontFallbacks,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = constraints.maxHeight;
        // 计算上下留白高度：使得第 i 行 offset = i * _lyricItemHeight 时，该行刚好位于视口正中垂直线
        final verticalPadding = ((viewportHeight - _lyricItemHeight) / 2).clamp(20.0, 600.0);

        return ListView.builder(
          controller: _lyricScrollController,
          padding: EdgeInsets.symmetric(
            horizontal: 24,
            vertical: verticalPadding,
          ),
          itemCount: _lyrics.length,
          itemBuilder: (context, index) {
            final line = _lyrics[index];
            final isActive = index == _currentLyricIndex;

            return InkWell(
              onTap: () {
                player.seek(Duration(milliseconds: line.timeMs));
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: _lyricItemHeight,
                alignment: Alignment.center,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.white38,
                    fontSize: isActive ? 20 : 15,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    height: 1.4,
                    fontFamilyFallback: AppTheme.fontFallbacks,
                  ),
                  textAlign: TextAlign.center,
                  child: Text(
                    line.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 构建底部拖拽进度条与播放控制按钮
  Widget _buildBottomControls(PlayerProvider player, double sliderVal, double sliderMax) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动进度条
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
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

          // 时长显示 (当前播放时长 / 总时长)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(player.position),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontFamilyFallback: AppTheme.fontFallbacks,
                  ),
                ),
                Text(
                  _formatDuration(player.duration),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontFamilyFallback: AppTheme.fontFallbacks,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 核心控制按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '上一首',
                icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 36),
                onPressed: player.canSwitch ? () => player.playPrevious() : null,
              ),
              const SizedBox(width: 24),
              IconButton(
                tooltip: player.isPlaying ? '暂停' : '播放',
                icon: Icon(
                  player.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  color: Colors.white,
                  size: 56,
                ),
                onPressed: () => player.togglePlayPause(),
              ),
              const SizedBox(width: 24),
              IconButton(
                tooltip: '下一首',
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 36),
                onPressed: player.canSwitch ? () => player.playNext() : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
