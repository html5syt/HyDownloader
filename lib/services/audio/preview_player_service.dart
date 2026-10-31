import 'dart:async';
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
      _isPlaying = state == PlayerState.playing;
      _notify();
    });

    _player.onPositionChanged.listen((pos) {
      _position = pos;
      _notify();
    });

    _player.onDurationChanged.listen((dur) {
      _duration = dur;
      _notify();
    });

    _player.onPlayerComplete.listen((_) {
      if (canSwitch) {
        playNext();
      } else {
        _isPlaying = false;
        _position = Duration.zero;
        _notify();
      }
    });
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
    if (_currentSong?.id == song.id && !_isLoading) {
      if (_isPlaying) {
        await pause();
      } else {
        await resume();
      }
      return;
    }

    _currentSong = song;
    _isLoading = true;
    _position = Duration.zero;
    _duration = Duration(milliseconds: song.durationMs);
    _notify();

    try {
      // 按照用户设置的试听音质解析播放链接 (默认 exhigh 320k)
      final previewRate = _storage.getPreviewAudioRate();
      final urlInfo = await _musicService.getSongUrlInfo(
        songId: song.id,
        level: previewRate,
      );

      final url = urlInfo?['url']?.toString();
      if (url == null || url.isEmpty) {
        throw Exception('无法获取试听链接，可能受 VIP 或版权限制');
      }

      await _player.stop();
      await _player.play(UrlSource(url));
      _isPlaying = true;
    } catch (e) {
      _isPlaying = false;
      rethrow;
    } finally {
      _isLoading = false;
      _notify();
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
    if (_isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  /// 恢复播放
  Future<void> resume() async {
    await _player.resume();
    _isPlaying = true;
    _notify();
  }

  /// 暂停播放
  Future<void> pause() async {
    await _player.pause();
    _isPlaying = false;
    _notify();
  }

  /// 跳转至指定播放进度
  Future<void> seek(Duration target) async {
    await _player.seek(target);
  }

  /// 停止播放并释放
  Future<void> stop() async {
    await _player.stop();
    _currentSong = null;
    _currentIndex = -1;
    _isPlaying = false;
    _position = Duration.zero;
    _notify();
  }
}
