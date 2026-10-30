import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../services/audio/preview_player_service.dart';

/// 全局试听播放器 Provider
/// 将底层的 PreviewPlayerService 桥接至响应式 UI 状态
class PlayerProvider extends ChangeNotifier {
  final PreviewPlayerService _service = PreviewPlayerService.instance;

  PlayerProvider() {
    _service.addListener(_onServiceChanged);
  }

  void _onServiceChanged() {
    notifyListeners();
  }

  Song? get currentSong => _service.currentSong;
  bool get isPlaying => _service.isPlaying;
  bool get isLoading => _service.isLoading;
  Duration get position => _service.position;
  Duration get duration => _service.duration;

  /// 播放或暂停歌曲试听
  Future<void> playSong(Song song) async {
    await _service.playSong(song);
  }

  /// 切换播放/暂停
  Future<void> togglePlayPause() async {
    await _service.togglePlayPause();
  }

  /// 调整播放进度
  Future<void> seek(Duration target) async {
    await _service.seek(target);
  }

  /// 停止试听并关闭播放栏
  Future<void> stop() async {
    await _service.stop();
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }
}
