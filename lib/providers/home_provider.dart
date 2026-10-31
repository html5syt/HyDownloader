import 'package:flutter/foundation.dart';
import '../models/playlist.dart';
import '../models/podcast.dart';
import '../models/search_result.dart';
import '../services/netease/music_service.dart';

/// 主页数据状态 Provider
/// 管理用户歌单列表、收藏播客、综合检索结果及加载状态
class HomeProvider extends ChangeNotifier {
  final NeteaseMusicService _musicService = NeteaseMusicService.instance;

  /// 用户歌单列表
  List<Playlist> _playlists = [];

  /// 用户收藏的播客列表
  List<Podcast> _podcasts = [];

  /// 综合搜索结果
  SearchResult _searchResult = SearchResult.empty();

  /// 是否正在加载数据
  bool _isLoading = false;

  /// 是否正在搜索中
  bool _isSearching = false;

  /// 错误提示信息
  String? _errorMessage;

  List<Playlist> get playlists => _playlists;
  List<Podcast> get podcasts => _podcasts;
  SearchResult get searchResult => _searchResult;
  bool get isLoading => _isLoading;
  bool get isSearching => _isSearching;
  String? get errorMessage => _errorMessage;

  /// “我喜欢的音乐”歌单（若存在）
  Playlist? get likedSongsPlaylist =>
      _playlists.where((p) => p.isLikedSongs).firstOrNull;

  /// 加载当前登录用户的歌单与播客库
  ///
  /// [userId] 用户数字 ID
  Future<void> loadUserLibrary(String? userId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (userId != null && userId.isNotEmpty && !userId.startsWith('guest_') && !userId.startsWith('fake_')) {
        // 真实用户拉取个人歌单
        final playlists = await _musicService.getUserPlaylists(userId);
        _playlists = playlists;

        // 拉取收藏播客
        final podcasts = await _musicService.getUserSubscribedPodcasts();
        _podcasts = podcasts;
      } else {
        // 访客/伪造令牌模式：展示常用推荐或空提示
        _playlists = [];
        _podcasts = [];
      }
    } catch (e) {
      _errorMessage = '加载音乐库失败: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 执行综合搜索
  ///
  /// [keyword] 检索词
  /// [type] 检索类型
  Future<void> search(String keyword, SearchType type) async {
    if (keyword.trim().isEmpty) {
      _searchResult = SearchResult.empty();
      notifyListeners();
      return;
    }

    _isSearching = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _searchResult = await _musicService.search(keyword: keyword, type: type);
    } catch (e) {
      _errorMessage = '搜索失败: $e';
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  /// 清空搜索结果
  void clearSearch() {
    _searchResult = SearchResult.empty();
    notifyListeners();
  }
}
