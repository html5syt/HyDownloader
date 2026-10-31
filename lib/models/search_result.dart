import 'song.dart';
import 'playlist.dart';
import 'podcast.dart';

/// 搜索类型定义
enum SearchType {
  /// 单曲搜索 (type=1)
  song(1, '单曲'),

  /// 歌单搜索 (type=1000)
  playlist(1000, '歌单'),

  /// 播客电台搜索 (type=1009)
  podcast(1009, '播客');

  final int value;
  final String label;
  const SearchType(this.value, this.label);
}

/// 综合搜索返回结果封装模型
class SearchResult {
  /// 匹配到的歌曲列表
  final List<Song> songs;

  /// 匹配到的歌单列表
  final List<Playlist> playlists;

  /// 匹配到的播客列表
  final List<Podcast> podcasts;

  /// 当前检索的关键词
  final String keyword;

  const SearchResult({
    this.songs = const [],
    this.playlists = const [],
    this.podcasts = const [],
    this.keyword = '',
  });

  /// 空结果工厂方法
  factory SearchResult.empty() => const SearchResult();
}
