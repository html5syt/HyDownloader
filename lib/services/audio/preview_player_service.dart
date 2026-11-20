import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../../config/app_constants.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../models/song.dart';
import '../netease/music_service.dart';
import '../storage/storage_service.dart';

/// 试听播放器服务
/// 允许用户在下载前在线试听歌曲，并提供播放进度与播放状态管理
class PreviewPlayerService {
  final AudioPlayer _player = AudioPlayer();
  final NeteaseMusicService _musicService = NeteaseMusicService.instance;
  final StorageService _storage = StorageService.instance;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  CancelToken? _previewCancelToken;
  Directory? _activeCacheDirectory;
  Future<void> _playerActions = Future<void>.value();
  int _playRequest = 0;
  bool _hasSource = false;
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// 原生播放器调用串行化，快速切歌时旧请求不能覆盖新歌曲。
  Future<void> _withPlayer(Future<void> Function() action) {
    final operation = _playerActions.then((_) => action());
    _playerActions = operation.catchError((Object _) {});
    return operation;
  }

  void _handlePlayerError(Object error, [StackTrace? stack]) {
    _isPlaying = false;
    _hasSource = false;
    _errorMessage = '试听失败，点播放重试';
    _notify();
  }

  Future<void> _clearCache() async {
    final directory = _activeCacheDirectory;
    _activeCacheDirectory = null;
    if (directory != null) {
      try {
        await directory.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// 当前正在播放或试听的歌曲
  Song? _currentSong;

  /// 试听播放列表
  List<Song> _playlist = [];

  /// 当前歌曲在列表中的索引
  int _currentIndex = -1;

  /// 是否正在播放中
  bool _isPlaying = false;

  /// 是否正在缓冲加载音频直链
  bool _isLoading = false;

  /// 当前播放进度
  Duration _position = Duration.zero;

  /// 音频总时长
  Duration _duration = Duration.zero;

  /// 状态监听回调
  final List<void Function()> _listeners = [];

  /// 单例实例
  static final PreviewPlayerService instance = PreviewPlayerService._internal();

  PreviewPlayerService._internal() {
    _initPlayerListeners();
  }

  /// 获取当前试听歌曲
  Song? get currentSong => _currentSong;

  /// 获取播放列表
  List<Song> get playlist => List.unmodifiable(_playlist);

  /// 获取播放状态
  bool get isPlaying => _isPlaying;

  /// 获取加载缓冲状态
  bool get isLoading => _isLoading;

  /// 当前播放进度
  Duration get position => _position;

  /// 获取音频总时长
  Duration get duration => _duration;

  /// 是否有多首歌曲可供切换
  bool get canSwitch => _playlist.length > 1;

  /// 添加播放状态监听器
  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  /// 移除监听器
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void _notify() {
    for (final l in _listeners) {
      try {
        l();
      } catch (_) {}
    }
  }

  void _initPlayerListeners() {
    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing && _hasSource;
      _notify();
    }, onError: _handlePlayerError);

    _player.onPositionChanged.listen((pos) {
      _position = pos;
      _notify();
    }, onError: _handlePlayerError);

    _player.onDurationChanged.listen((dur) {
      _duration = dur;
      _notify();
    }, onError: _handlePlayerError);

    _player.onPlayerComplete.listen((_) {
      _hasSource = false;
      if (canSwitch) {
        playNext();
      } else {
        _isPlaying = false;
        _position = Duration.zero;
        _notify();
      }
    }, onError: _handlePlayerError);
  }

  /// 设置当前播放列表上下文
  void setPlaylist(List<Song> songs) {
    _playlist = List.from(songs);
    if (_currentSong != null) {
      _currentIndex = _playlist.indexWhere((s) => s.id == _currentSong!.id);
    }
  }

  /// 播放指定单曲
  ///
  /// [song] 目标歌曲
  /// [contextPlaylist] 可选提供当前歌单上下文，支持连贯切歌
  Future<void> playSong(Song song, {List<Song>? contextPlaylist}) async {
    if (contextPlaylist != null) {
      _playlist = List.from(contextPlaylist);
      _currentIndex = _playlist.indexWhere((s) => s.id == song.id);
    } else if (!_playlist.any((s) => s.id == song.id)) {
      _playlist = [song];
      _currentIndex = 0;
    } else {
      _currentIndex = _playlist.indexWhere((s) => s.id == song.id);
    }

    // 若点击同一首正在播放的歌曲，则切换暂停/播放
    if (_currentSong?.id == song.id &&
        !_isLoading &&
        _hasSource &&
        _errorMessage == null) {
      if (_isPlaying) {
        await pause();
      } else {
        await resume();
      }
      return;
    }

    final request = ++_playRequest;
    _previewCancelToken?.cancel();
    final token = CancelToken();
    _previewCancelToken = token;
    _currentSong = song;
    _hasSource = false;
    _isPlaying = false;
    _errorMessage = null;
    _isLoading = true;
    _position = Duration.zero;
    _duration = Duration(milliseconds: song.durationMs);
    _notify();

    Directory? cacheDirectory;
    try {
      // 按照用户设置的试听音质解析播放链接 (默认 exhigh 320k)
      final previewRate = _storage.getPreviewAudioRate();
      final urlInfo = await _musicService.getSongUrlInfo(
        songId: song.id,
        level: previewRate,
      );

      if (request != _playRequest) return;
      final url = urlInfo?['url']?.toString();
      if (url == null || url.isEmpty) {
        throw Exception('无法获取试听链接，可能受 VIP 或版权限制');
      }

      Source source = UrlSource(url);
      if (Platform.isAndroid) {
        // Android 原生网络播放器不支持应用请求头，且部分设备加载 HTTP 源失败。
        // 使用应用网络栈和私有缓存播放，无需媒体库或外部存储权限。
        final temporary = await getTemporaryDirectory();
        cacheDirectory = await temporary.createTemp('hydownloader-preview-');
        final type = urlInfo?['type']?.toString() ?? 'mp3';
        final extension = RegExp(r'^[a-z0-9]+$').hasMatch(type) ? type : 'mp3';
        final filePath = '${cacheDirectory.path}/preview.$extension';
        await _dio.download(
          url,
          filePath,
          cancelToken: token,
          options: Options(headers: AppConstants.neteaseImageHeaders),
        );
        source = DeviceFileSource(filePath);
      }
      if (request != _playRequest) return;
      await _withPlayer(() async {
        if (request != _playRequest) return;
        await _player.stop();
        await _clearCache();
        if (request != _playRequest) return;
        _activeCacheDirectory = cacheDirectory;
        await _player.play(source);
        if (request == _playRequest) {
          _hasSource = true;
          _isPlaying = true;
          _errorMessage = null;
        }
      });
    } catch (e) {
      if (request == _playRequest && !token.isCancelled) {
        _handlePlayerError(e);
      }
    } finally {
      if (cacheDirectory != null &&
          !identical(cacheDirectory, _activeCacheDirectory)) {
        try {
          await cacheDirectory.delete(recursive: true);
        } catch (_) {}
      }
      if (request == _playRequest) {
        _isLoading = false;
        _notify();
      }
    }
  }

  /// 播放上一首 (支持循环轮播)
  Future<void> playPrevious() async {
    if (_playlist.isEmpty) return;
    if (_currentIndex > 0) {
      _currentIndex--;
    } else {
      _currentIndex = _playlist.length - 1;
    }
    _currentSong = null; // 确保触发重新加载
    await playSong(_playlist[_currentIndex], contextPlaylist: _playlist);
  }

  /// 播放下一首 (支持循环轮播)
  Future<void> playNext() async {
    if (_playlist.isEmpty) return;
    if (_currentIndex < _playlist.length - 1) {
      _currentIndex++;
    } else {
      _currentIndex = 0;
    }
    _currentSong = null; // 确保触发重新加载
    await playSong(_playlist[_currentIndex], contextPlaylist: _playlist);
  }

  /// 切换播放与暂停
  Future<void> togglePlayPause() async {
    if (_isLoading) return;
    if (_isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  /// 恢复播放
  Future<void> resume() async {
    final song = _currentSong;
    if (!_hasSource || _errorMessage != null) {
      if (song != null) await playSong(song);
      return;
    }
    try {
      await _withPlayer(_player.resume);
      _isPlaying = true;
      _notify();
    } catch (e) {
      _handlePlayerError(e);
    }
  }

  /// 暂停播放
  Future<void> pause() async {
    try {
      await _withPlayer(_player.pause);
      _isPlaying = false;
      _notify();
    } catch (e) {
      _handlePlayerError(e);
    }
  }

  /// 跳转至指定播放进度
  Future<void> seek(Duration target) async {
    if (!_hasSource || _isLoading) return;
    try {
      await _withPlayer(() => _player.seek(target));
    } catch (e) {
      _handlePlayerError(e);
    }
  }

  /// 停止播放并释放
  Future<void> stop() async {
    ++_playRequest;
    _previewCancelToken?.cancel();
    _isLoading = false;
    _hasSource = false;
    _errorMessage = null;
    await _withPlayer(() async {
      await _player.stop();
      await _clearCache();
    });
    _currentSong = null;
    _currentIndex = -1;
    _isPlaying = false;
    _position = Duration.zero;
    _notify();
  }
}
