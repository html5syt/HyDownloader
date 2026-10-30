import 'package:flutter/foundation.dart';
import '../models/playlist.dart';
import '../models/sync_item.dart';
import '../services/sync/playlist_sync_service.dart';
import '../services/storage/storage_service.dart';

/// 歌单文件同步交互 Provider
/// 负责驱动在线歌单与本地多文件夹的比对计算、勾选项管理与执行同步
class SyncProvider extends ChangeNotifier {
  final PlaylistSyncService _syncService = PlaylistSyncService.instance;
  final StorageService _storage = StorageService.instance;

  /// 当前选择参与比对的在线歌单
  Playlist? _selectedPlaylist;

  /// 当前选定的本地文件夹路径列表
  List<String> _selectedFolders = [];

  /// 比对生成的差异项列表
  List<SyncItem> _syncItems = [];

  /// 是否正在比对分析中
  bool _isComparing = false;

  /// 是否正在执行同步中
  bool _isSyncing = false;

  /// 同步执行进度说明
  String _syncProgressText = '';

  /// 错误提示
  String? _errorMessage;

  Playlist? get selectedPlaylist => _selectedPlaylist;
  List<String> get selectedFolders => _selectedFolders;
  List<SyncItem> get syncItems => _syncItems;
  bool get isComparing => _isComparing;
  bool get isSyncing => _isSyncing;
  String get syncProgressText => _syncProgressText;
  String? get errorMessage => _errorMessage;

  /// 统计：缺失项数量
  int get missingCount =>
      _syncItems.where((i) => i.type == SyncDifferenceType.missingInLocal).length;

  /// 统计：多余项数量
  int get extraCount =>
      _syncItems.where((i) => i.type == SyncDifferenceType.extraInLocal).length;

  /// 统计：已匹配项数量
  int get matchedCount =>
      _syncItems.where((i) => i.type == SyncDifferenceType.matched).length;

  /// 已勾选的项总数
  int get selectedCount => _syncItems.where((i) => i.isSelected).length;

  /// 从持久化中载入已保存的文件夹列表
  void loadSavedFolders() {
    _selectedFolders = _storage.getSyncFolders();
    notifyListeners();
  }

  /// 设定在线歌单
  void setPlaylist(Playlist playlist) {
    _selectedPlaylist = playlist;
    _syncItems.clear();
    _errorMessage = null;
    notifyListeners();
  }

  /// 添加本地对比文件夹
  Future<void> addFolder(String path) async {
    if (!_selectedFolders.contains(path)) {
      _selectedFolders.add(path);
      await _storage.saveSyncFolders(_selectedFolders);
      _syncItems.clear();
      notifyListeners();
    }
  }

  /// 移除本地文件夹
  Future<void> removeFolder(String path) async {
    _selectedFolders.remove(path);
    await _storage.saveSyncFolders(_selectedFolders);
    _syncItems.clear();
    notifyListeners();
  }

  /// 切换指定项的勾选状态
  void toggleItemSelection(SyncItem item) {
    item.isSelected = !item.isSelected;
    notifyListeners();
  }

  /// 全选或全不选指定类型的项
  void selectAll(bool select, {SyncDifferenceType? filterType}) {
    for (final item in _syncItems) {
      if (filterType == null || item.type == filterType) {
        item.isSelected = select;
      }
    }
    notifyListeners();
  }

  /// 执行对比计算
  Future<void> startComparison() async {
    if (_selectedPlaylist == null) {
      _errorMessage = '请先选择需要比对的在线歌单';
      notifyListeners();
      return;
    }
    if (_selectedFolders.isEmpty) {
      _errorMessage = '请添加至少一个本地文件夹';
      notifyListeners();
      return;
    }

    _isComparing = true;
    _errorMessage = null;
    _syncItems.clear();
    notifyListeners();

    try {
      final items = await _syncService.comparePlaylistWithLocalFolders(
        playlistId: _selectedPlaylist!.id,
        localFolderPaths: _selectedFolders,
      );
      _syncItems = items;
    } catch (e) {
      _errorMessage = '歌单文件比对失败: $e';
    } finally {
      _isComparing = false;
      notifyListeners();
    }
  }

  /// 执行同步操作
  Future<void> executeSync({String? customTargetFolder}) async {
    final targetFolder = customTargetFolder ??
        (_selectedFolders.isNotEmpty ? _selectedFolders.first : await _storage.getDownloadDirectory());

    _isSyncing = true;
    _syncProgressText = '正在处理同步...';
    notifyListeners();

    try {
      await _syncService.executeSync(
        items: _syncItems,
        targetDownloadFolder: targetFolder,
        onProgress: (done, total) {
          _syncProgressText = '已完成 $done / $total';
          notifyListeners();
        },
      );
    } catch (e) {
      _errorMessage = '同步过程中出现错误: $e';
    } finally {
      _isSyncing = false;
      _syncProgressText = '同步已完成';
      notifyListeners();
    }
  }
}
