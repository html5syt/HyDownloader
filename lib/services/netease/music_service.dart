import 'dart:convert';
import '../../models/song.dart';
import '../../models/playlist.dart';
import '../../models/podcast.dart';
import '../../models/search_result.dart';
import 'netease_client.dart';

/// 歌单详情数据复合封装
class PlaylistDetailResult {
  final Playlist playlist;
  final List<Song> songs;

  const PlaylistDetailResult({
    required this.playlist,
    required this.songs,
  });
}

/// 网易云音乐业务数据接口服务
/// 提供歌单、单曲详情、播客电台、搜索以及高解析音频直链解析能力
class NeteaseMusicService {
  final NeteaseClient _client = NeteaseClient.instance;

  /// 单例
  static final NeteaseMusicService instance = NeteaseMusicService._internal();
  NeteaseMusicService._internal();

  /// 获取指定用户的歌单列表（含“我喜欢的音乐”）
  ///
  /// [userId] 用户数字 ID
  Future<List<Playlist>> getUserPlaylists(String userId) async {
    final res = await _client.postWeApi(
      url: 'https://music.163.com/weapi/user/playlist',
      actualRequest: {
        'uid': userId,
        'limit': 1000,
        'offset': 0,
        'includeVideo': true,
      },
    );

    final list = <Playlist>[];
    if (res['playlist'] is List) {
      for (final item in res['playlist']) {
        if (item is Map<String, dynamic>) {
          list.add(Playlist.fromJson(item));
        }
      }
    }
    return list;
  }

  /// 获取歌单完整详情及内部歌曲列表
  ///
  /// [playlistId] 歌单数字 ID
  /// [initialPlaylist] 基础歌单对象（可选）
  Future<PlaylistDetailResult> getPlaylistDetailWithSongs(
    String playlistId, {
    Playlist? initialPlaylist,
  }) async {
    Playlist currentPlaylist = initialPlaylist ??
        Playlist(
          id: playlistId,
          name: '加载中...',
          coverImgUrl: '',
          trackCount: 0,
          playCount: 0,
        );
    List<Song> songs = [];

    try {
      // 优先调用 EAPI v6 歌单详情接口
      final res = await _client.postEApi(
        apiPath: '/api/v6/playlist/detail',
        actualRequest: {
          'id': playlistId,
          'n': 100000,
          's': 8,
        },
      );

      final playlistMap = res['playlist'];
      if (playlistMap is Map<String, dynamic>) {
        currentPlaylist = Playlist.fromJson(playlistMap);

        final tracks = playlistMap['tracks'];
        if (tracks is List && tracks.isNotEmpty) {
          for (final t in tracks) {
            if (t is Map<String, dynamic>) {
              songs.add(Song.fromJson(t));
            }
          }
        } else {
          // 若 tracks 截断，使用 trackIds 批量拉取
          final trackIds = playlistMap['trackIds'];
          if (trackIds is List && trackIds.isNotEmpty) {
            final ids = trackIds
                .take(500)
                .map((e) => (e is Map ? e['id'] : e).toString())
                .toList();
            songs = await getSongsDetail(ids);
          }
        }
      }
    } catch (_) {
      // 容错调用 WEAPI
      try {
        final resWe = await _client.postWeApi(
          url: 'https://music.163.com/weapi/v3/playlist/detail',
          actualRequest: {
            'id': playlistId,
            'n': 100000,
            's': 8,
          },
        );
        if (resWe['playlist'] is Map<String, dynamic>) {
          currentPlaylist = Playlist.fromJson(resWe['playlist'] as Map<String, dynamic>);
          final tracks = resWe['playlist']['tracks'];
          if (tracks is List) {
            songs = tracks.whereType<Map<String, dynamic>>().map(Song.fromJson).toList();
          }
        }
      } catch (_) {}
    }

    return PlaylistDetailResult(playlist: currentPlaylist, songs: songs);
  }

  /// 获取歌单内歌曲列表
  Future<List<Song>> getPlaylistSongs(String playlistId) async {
    final result = await getPlaylistDetailWithSongs(playlistId);
    return result.songs;
  }

  /// 批量获取歌曲详情
  ///
  /// [songIds] 歌曲 ID 列表
  Future<List<Song>> getSongsDetail(List<String> songIds) async {
    if (songIds.isEmpty) return [];

    final idObjects = songIds.map((id) => {'id': id}).toList();
    final res = await _client.postWeApi(
      url: 'https://music.163.com/weapi/v3/song/detail',
      actualRequest: {
        'c': json.encode(idObjects),
      },
    );

    final songs = <Song>[];
    if (res['songs'] is List) {
      for (final s in res['songs']) {
        if (s is Map<String, dynamic>) {
          songs.add(Song.fromJson(s));
        }
      }
    }
    return songs;
  }

  /// 获取用户收藏的播客 / 声音电台列表
  Future<List<Podcast>> getUserSubscribedPodcasts() async {
    final res = await _client.postWeApi(
      url: 'https://music.163.com/weapi/djradio/sublist',
      actualRequest: {
        'limit': 100,
        'offset': 0,
        'total': true,
      },
    );

    final podcasts = <Podcast>[];
    if (res['djRadios'] is List) {
      for (final p in res['djRadios']) {
        if (p is Map<String, dynamic>) {
          podcasts.add(Podcast.fromJson(p));
        }
      }
    }
    return podcasts;
  }

  /// 获取指定电台的所有声音节目列表
  ///
  /// [radioId] 播客电台 ID
  Future<List<PodcastProgram>> getPodcastPrograms(String radioId) async {
    final res = await _client.postWeApi(
      url: 'https://music.163.com/weapi/dj/program/byradio',
      actualRequest: {
        'radioId': radioId,
        'limit': 200,
        'offset': 0,
        'asc': false,
      },
    );

    final programs = <PodcastProgram>[];
    if (res['programs'] is List) {
      for (final p in res['programs']) {
        if (p is Map<String, dynamic>) {
          programs.add(PodcastProgram.fromJson(p));
        }
      }
    }
    return programs;
  }

  /// 综合搜索接口 (采用 EAPI /cloudsearch/pc 接口，与 HyPlayer 保持一致)
  ///
  /// [keyword] 关键词
  /// [type] 检索类型（单曲、歌单、播客）
  Future<SearchResult> search({
    required String keyword,
    required SearchType type,
  }) async {
    if (keyword.trim().isEmpty) return SearchResult.empty();

    final res = await _client.postEApi(
      apiPath: '/api/cloudsearch/pc',
      url: 'https://interface.music.163.com/eapi/cloudsearch/pc',
      actualRequest: {
        's': keyword,
        'type': type.value,
        'limit': 30,
        'offset': 0,
        'total': true,
      },
    );

    final result = res['result'];
    if (result is! Map<String, dynamic>) return SearchResult.empty();

    switch (type) {
      case SearchType.song:
        final songs = <Song>[];
        if (result['songs'] is List) {
          for (final s in result['songs']) {
            if (s is Map<String, dynamic>) songs.add(Song.fromJson(s));
          }
        }
        return SearchResult(songs: songs, keyword: keyword);

      case SearchType.playlist:
        final playlists = <Playlist>[];
        if (result['playlists'] is List) {
          for (final p in result['playlists']) {
            if (p is Map<String, dynamic>) playlists.add(Playlist.fromJson(p));
          }
        }
        return SearchResult(playlists: playlists, keyword: keyword);

      case SearchType.podcast:
        final podcasts = <Podcast>[];
        if (result['djRadios'] is List) {
          for (final d in result['djRadios']) {
            if (d is Map<String, dynamic>) podcasts.add(Podcast.fromJson(d));
          }
        }
        return SearchResult(podcasts: podcasts, keyword: keyword);
    }
  }

  /// 解析单曲音频真实播放/下载链接
  ///
  /// [songId] 歌曲数字 ID
  /// [level] 目标音质等级 (standard, exhigh, lossless, hires, jymaster 等)
  Future<Map<String, dynamic>?> getSongUrlInfo({
    required String songId,
    required String level,
  }) async {
    final res = await _client.postEApi(
      apiPath: '/api/song/enhance/player/url/v1',
      actualRequest: {
        'ids': json.encode([songId]),
        'level': level,
        'encodeType': 'flac',
        'immerseType': 'c51',
      },
    );

    if (res['data'] is List && (res['data'] as List).isNotEmpty) {
      final item = (res['data'] as List).first;
      if (item is Map<String, dynamic>) {
        final url = item['url']?.toString();
        if (url != null && url.isNotEmpty) {
          return {
            'url': url,
            'type': item['type']?.toString().toLowerCase() ?? 'mp3',
            'size': item['size'] is int ? item['size'] as int : 0,
            'bitrate': item['br']?.toString() ?? '320000',
            'md5': item['md5']?.toString() ?? '',
            'level': item['level']?.toString() ?? level,
          };
        }
      }
    }
    return null;
  }
}
