import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../models/download_task.dart';
import '../services/download/download_service.dart';

/// 全局下载任务管理 Provider
/// 驱动下载列表展示、并发控制与进度刷新
class DownloadProvider extends ChangeNotifier {
  final DownloadService _service = DownloadService.instance;

  DownloadProvider() {
    _service.addListener(_onTaskChanged);
  }

  void _onTaskChanged(DownloadTask task) {
    notifyListeners();
  }

  List<DownloadTask> get tasks => _service.tasks;

  /// 进行中的下载任务数
  int get activeCount => _service.tasks
      .where((t) =>
          t.status == DownloadStatus.downloading ||
          t.status == DownloadStatus.tagging ||
          t.status == DownloadStatus.lyrics)
      .length;

  /// 排队等待的任务数
  int get pendingCount =>
      _service.tasks.where((t) => t.status == DownloadStatus.pending).length;

  /// 已完成的任务数
  int get completedCount =>
      _service.tasks.where((t) => t.status == DownloadStatus.completed).length;

  /// 添加单曲下载
  Future<DownloadTask> downloadSong(Song song, {String? quality}) async {
    final task = await _service.enqueueSong(song, quality: quality);
    notifyListeners();
    return task;
  }

  /// 批量下载歌曲列表
  Future<void> downloadSongs(List<Song> songs, {String? quality}) async {
    await _service.enqueueSongs(songs, quality: quality);
    notifyListeners();
  }

  /// 暂停任务
  void pauseTask(DownloadTask task) {
    _service.pauseTask(task);
    notifyListeners();
  }

  /// 恢复任务
  void resumeTask(DownloadTask task) {
    _service.resumeTask(task);
    notifyListeners();
  }

  /// 重试失败任务
  void retryTask(DownloadTask task) {
    _service.retryTask(task);
    notifyListeners();
  }

  /// 取消并移除任务
  void cancelTask(DownloadTask task) {
    _service.cancelTask(task);
    notifyListeners();
  }

  /// 清理已完成的任务项
  void clearCompleted() {
    _service.clearCompleted();
    notifyListeners();
  }

  /// 全部暂停
  void pauseAll() {
    _service.pauseAll();
    notifyListeners();
  }

  /// 全部恢复
  void resumeAll() {
    _service.resumeAll();
    notifyListeners();
  }

  @override
  void dispose() {
    _service.removeListener(_onTaskChanged);
    super.dispose();
  }
}
