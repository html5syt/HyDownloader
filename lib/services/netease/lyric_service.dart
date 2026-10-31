import 'netease_client.dart';

/// 单行歌词数据结构
class LyricLine {
  /// 时间标记对应的毫秒数
  final int timeMs;

  /// 时间标记字符串 (如 01:23.45)
  final String timeTag;

  /// 原始歌词文本
  final String text;

  /// 对应中文翻译文本
  String? translation;

  LyricLine({
    required this.timeMs,
    required this.timeTag,
    required this.text,
    this.translation,
  });
}

/// 歌词服务
/// 负责网易云歌词获取、时间轴对齐解析与标准 LRC 文件内容生成
class NeteaseLyricService {
  final NeteaseClient _client = NeteaseClient.instance;

  /// 单例
  static final NeteaseLyricService instance = NeteaseLyricService._internal();
  NeteaseLyricService._internal();

  /// 从网易云 API 获取歌词原始数据并合成标准 LRC 文本
  ///
  /// [songId] 歌曲 ID
  /// [includeTranslation] 是否合并对应翻译
  Future<String?> getFormattedLrc({
    required String songId,
    bool includeTranslation = true,
  }) async {
    try {
      final res = await _client.postWeApi(
        url: 'https://music.163.com/weapi/song/lyric/v1',
        actualRequest: {
          'id': songId,
          'cp': false,
          'tv': 0,
          'lv': 0,
          'rv': 0,
          'kv': 0,
          'yv': 0,
          'ytv': 0,
          'yrv': 0,
        },
      );

      final lrcObj = res['lrc'];
      final rawLyric = lrcObj is Map ? lrcObj['lyric']?.toString() : null;
      if (rawLyric == null || rawLyric.trim().isEmpty) return null;
      if (rawLyric.contains('纯音乐，请欣赏')) return null;

      final tlyricObj = res['tlyric'];
      final rawTranslation = tlyricObj is Map ? tlyricObj['lyric']?.toString() : null;

      // 解析原版歌词
      final lines = _parseLrcLines(rawLyric);

      // 如果需要合并翻译，且存在翻译文本
      if (includeTranslation && rawTranslation != null && rawTranslation.isNotEmpty) {
        final transLines = _parseLrcLines(rawTranslation);
        final transMap = <int, String>{};
        for (final t in transLines) {
          transMap[t.timeMs] = t.text;
        }

        // 按相近时间轴对齐翻译 (允许 200ms 误差)
        for (final l in lines) {
          if (transMap.containsKey(l.timeMs)) {
            l.translation = transMap[l.timeMs];
          } else {
            for (final entry in transMap.entries) {
              if ((entry.key - l.timeMs).abs() <= 200) {
                l.translation = entry.value;
                break;
              }
            }
          }
        }
      }

      // 生成与 HyPlayer 格式一致的标准 LRC
      final buffer = StringBuffer();
      for (final l in lines) {
        if (l.translation != null && l.translation!.trim().isNotEmpty) {
          buffer.writeln('[${l.timeTag}]${l.text} 「${l.translation}」');
        } else {
          buffer.writeln('[${l.timeTag}]${l.text}');
        }
      }

      return buffer.toString();
    } catch (_) {
      return null;
    }
  }

  /// 解析 LRC 字符串为结构化行列表
  List<LyricLine> _parseLrcLines(String lrcText) {
    final result = <LyricLine>[];
    final regExp = RegExp(r'\[(\d{2}):(\d{2})\.?(\d{2,3})?\](.*)');

    final rawLines = lrcText.split('\n');
    for (final raw in rawLines) {
      final trimmed = raw.trim();
      final match = regExp.firstMatch(trimmed);
      if (match != null) {
        final m = int.tryParse(match.group(1) ?? '0') ?? 0;
        final s = int.tryParse(match.group(2) ?? '0') ?? 0;
        final msPart = match.group(3) ?? '00';
        final ms = int.tryParse(msPart.padRight(3, '0').substring(0, 3)) ?? 0;
        final totalMs = m * 60 * 1000 + s * 1000 + ms;
        final text = (match.group(4) ?? '').trim();
        final tag = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${(ms ~/ 10).toString().padLeft(2, '0')}';

        if (text.isNotEmpty) {
          result.add(LyricLine(
            timeMs: totalMs,
            timeTag: tag,
            text: text,
          ));
        }
      }
    }
    result.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return result;
  }
}
