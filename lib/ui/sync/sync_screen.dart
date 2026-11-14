import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/sync_item.dart';
import '../../providers/sync_provider.dart';
import '../../providers/home_provider.dart';
import '../../services/storage/permission_service.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/app_network_image.dart';

/// 歌单文件双向同步页面
/// 支持在线歌单与多个本地文件夹比对，比对完成后可灵活折叠展开配置面板，
/// 自适应移动端小屏与桌面端宽屏，主动申请并管理移动端存储卡与 U 盘读写权限
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  SyncDifferenceType? _filterType;

  /// 配置面板展开/收起状态（比对完成后自动收起以最大化列表空间）
  bool _isConfigExpanded = true;

  /// 是否已具备外部存储访问权限（针对移动端 Android）
  bool _hasStoragePermission = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SyncProvider>().loadSavedFolders();
      _checkStoragePermission();
    });
  }

  /// 检查存储权限
  Future<void> _checkStoragePermission() async {
    final granted = await PermissionService.instance.isStoragePermissionGranted();
    if (mounted) {
      setState(() {
        _hasStoragePermission = granted;
      });
    }
  }

  /// 弹出本地文件夹选择器（主动申请并确保存储权限）
  Future<void> _pickFolder() async {
    // 主动检查并申请 Android 存储权限
    final hasPerm = await PermissionService.instance.requestStoragePermission();
    if (mounted) {
      setState(() => _hasStoragePermission = hasPerm);
    }

    try {
      final path = await FilePicker.getDirectoryPath(
        dialogTitle: '选择要参与比对的本地音乐文件夹',
      );
      if (path != null && path.isNotEmpty && mounted) {
        await context.read<SyncProvider>().addFolder(path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择文件夹异常: $e，请检查存储权限')),
        );
      }
    }
  }

  /// 弹出在线歌单选择弹窗
  Future<void> _pickPlaylist() async {
    final home = context.read<HomeProvider>();
    final sync = context.read<SyncProvider>();

    if (home.playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可供选择的歌单，请先登录账号获取歌单')),
      );
      return;
    }

    final chosen = await showModalBottomSheet<dynamic>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('选择比对的在线歌单', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: home.playlists.length,
                  itemBuilder: (_, i) {
                    final pl = home.playlists[i];
                    return ListTile(
                      leading: AppNetworkImage(
                        url: pl.coverImgUrl,
                        width: 44,
                        height: 44,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      title: Text(
                        pl.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('${pl.trackCount} 首歌曲'),
                      onTap: () => Navigator.pop(ctx, pl),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (chosen != null && mounted) {
      sync.setPlaylist(chosen);
    }
  }

  /// 开始对比并在完成时自动收起配置面板
  Future<void> _handleStartComparison() async {
    // 主动检查并申请存储权限
    final hasPerm = await PermissionService.instance.requestStoragePermission();
    if (!mounted) return;
    setState(() => _hasStoragePermission = hasPerm);

    final sync = context.read<SyncProvider>();
    await sync.startComparison();
    if (mounted && sync.syncItems.isNotEmpty) {
      setState(() {
        _isConfigExpanded = false; // 比对完成后自动收起面板，给列表最大展示空间
      });
    }
  }

  /// 确认并执行同步
  Future<void> _confirmAndExecuteSync() async {
    // 确保具备存储写权限
    final hasPerm = await PermissionService.instance.requestStoragePermission();
    if (!mounted) return;
    setState(() => _hasStoragePermission = hasPerm);

    final sync = context.read<SyncProvider>();
    final selectedItems = sync.syncItems.where((i) => i.isSelected).toList();
    if (selectedItems.isEmpty) return;

    final extraCount = selectedItems.where((i) => i.type == SyncDifferenceType.extraInLocal).length;
    final copyCount = selectedItems.where((i) => i.type == SyncDifferenceType.copyFromLocal).length;
    final missingCount = selectedItems.where((i) => i.type == SyncDifferenceType.missingInLocal).length;

    // 如果包含需要删除的本地歌曲，弹出二次确认对话框保证安全
    if (extraCount > 0) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认同步操作'),
          content: Text(
            '本次同步将包含：\n'
            '${missingCount > 0 ? "• 下载 $missingCount 首缺失歌曲（首份入主盘，后台异步拷贝）\n" : ""}'
            '${copyCount > 0 ? "• 跨磁盘免下载直接拷贝 $copyCount 首歌曲\n" : ""}'
            '• 从本地永久删除 $extraCount 首多余歌曲文件及对应歌词\n\n'
            '删除操作不可撤回，是否确认继续？',
          ),
          actions: [
            TextButton(
              child: const Text('取消'),
              onPressed: () => Navigator.pop(ctx, false),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('确认执行'),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    if (mounted) {
      await sync.executeSync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('歌单文件同步处理完成！'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sync = context.watch<SyncProvider>();
    final isNarrow = MediaQuery.of(context).size.width < 450;

    final filteredItems = _filterType == null
        ? sync.syncItems
        : sync.syncItems.where((i) => i.type == _filterType).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('歌单文件同步'),
        actions: [
          IconButton(
            tooltip: '重新比对',
            icon: const Icon(Icons.refresh),
            onPressed: (sync.selectedPlaylist != null && sync.selectedFolders.isNotEmpty && !sync.isComparing)
                ? _handleStartComparison
                : null,
          ),
        ],
      ),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // 0. 移动端存储权限主动提示横幅（若尚未授予）
              if (!_hasStoragePermission && Platform.isAndroid)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.withAlpha(120)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.sd_card_alert_outlined, color: Colors.amber, size: 24),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            '需要外部存储权限以同步读取和写入外部存储卡、U 盘与音乐文件夹',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: () async {
                            final granted = await PermissionService.instance.requestStoragePermission();
                            setState(() => _hasStoragePermission = granted);
                            if (!granted) {
                              await PermissionService.instance.openSettings();
                            }
                          },
                          child: const Text('去授权'),
                        ),
                      ],
                    ),
                  ),
                ),

              // 1. 顶部配置卡片（支持点击折叠与自然滚动收起）
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: _buildConfigCardContent(sync, theme, colorScheme, isNarrow),
                    ),
                  ),
                ),
              ),

              // 2. 比对结果统计徽章与全选操作栏（自适应小屏字号与文案）
              if (sync.syncItems.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        _buildStatBadge(
                          isNarrow ? '待下载' : '待下载 (全缺)',
                          sync.missingCount,
                          Colors.blue,
                          SyncDifferenceType.missingInLocal,
                        ),
                        const SizedBox(width: 6),
                        _buildStatBadge(
                          isNarrow ? '本地拷贝' : '本地拷贝 (免下载)',
                          sync.copyCount,
                          Colors.teal,
                          SyncDifferenceType.copyFromLocal,
                        ),
                        const SizedBox(width: 6),
                        _buildStatBadge(
                          isNarrow ? '多余清理' : '多余 (待清理)',
                          sync.extraCount,
                          Colors.red,
                          SyncDifferenceType.extraInLocal,
                        ),
                        const SizedBox(width: 6),
                        _buildStatBadge(
                          '已同步',
                          sync.matchedCount,
                          Colors.green,
                          SyncDifferenceType.matched,
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    child: Row(
                      children: [
                        Text('共比对出 ${filteredItems.length} 项差异', style: theme.textTheme.bodySmall),
                        const Spacer(),
                        TextButton(
                          onPressed: () => sync.selectAll(true, filterType: _filterType),
                          child: const Text('全选'),
                        ),
                        TextButton(
                          onPressed: () => sync.selectAll(false, filterType: _filterType),
                          child: const Text('取消全选'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // 3. 差异列表区域（直接作为 Sliver 滚动，占满全部剩余视图空间）
              if (sync.isComparing)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (sync.errorMessage != null)
                SliverFillRemaining(
                  child: EmptyStateView(
                    icon: Icons.error_outline,
                    title: '比对失败',
                    subtitle: sync.errorMessage,
                    actionText: '重试',
                    onAction: _handleStartComparison,
                  ),
                )
              else if (sync.syncItems.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyStateView(
                    icon: Icons.compare_arrows_rounded,
                    title: '请配置歌单与文件夹后开始对比',
                    subtitle: '系统将对比分析在线歌单与本地文件，精准找出缺失和多余的歌曲',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: 96, left: 4, right: 4),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = filteredItems[index];
                        return _buildSyncTile(item, sync, isNarrow);
                      },
                      childCount: filteredItems.length,
                    ),
                  ),
                ),
            ],
          ),

          // 底部执行同步浮动栏（自适应防溢出）
          if (sync.syncItems.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 8, offset: const Offset(0, -2)),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '已选中 ${sync.selectedCount} 项操作',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          if (sync.isSyncing)
                            Text(
                              sync.syncProgressText,
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.primary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: sync.isSyncing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.sync, size: 18),
                      label: const Text('开始同步'),
                      onPressed: (sync.selectedCount > 0 && !sync.isSyncing) ? _confirmAndExecuteSync : null,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建配置卡片内容（支持展开完整版与折叠精简条）
  Widget _buildConfigCardContent(SyncProvider sync, ThemeData theme, ColorScheme colorScheme, bool isNarrow) {
    // 比对完成后折叠状态：展示极简条，点击可随时展开
    if (sync.syncItems.isNotEmpty && !_isConfigExpanded) {
      return InkWell(
        onTap: () => setState(() => _isConfigExpanded = true),
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            const Icon(Icons.tune_rounded, size: 18, color: Colors.blueAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '已比对: ${sync.selectedPlaylist?.name ?? ""} · ${sync.selectedFolders.length} 个文件夹',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.expand_more, size: 16),
              label: Text(isNarrow ? '展开' : '展开配置'),
              onPressed: () => setState(() => _isConfigExpanded = true),
            ),
          ],
        ),
      );
    }

    // 展开完整配置界面
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 在线歌单选择行
        Row(
          children: [
            const Icon(Icons.queue_music, size: 20, color: Colors.blueAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                sync.selectedPlaylist != null
                    ? '歌单: ${sync.selectedPlaylist!.name}'
                    : '请选择在线歌单',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              onPressed: _pickPlaylist,
              child: Text(sync.selectedPlaylist != null ? '更改' : '选择歌单'),
            ),
            if (sync.syncItems.isNotEmpty) ...[
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '收起配置卡片',
                icon: const Icon(Icons.expand_less, size: 20),
                onPressed: () => setState(() => _isConfigExpanded = false),
              ),
            ],
          ],
        ),
        const Divider(height: 16),

        // 2. 本地文件夹多选区
        Row(
          children: [
            const Icon(Icons.folder_copy_outlined, size: 20, color: Colors.amber),
            const SizedBox(width: 8),
            const Text('本地文件夹 (可多个):', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
            const Spacer(),
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加'),
              onPressed: _pickFolder,
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (sync.selectedFolders.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('尚未添加任何本地文件夹，请点击“添加”选择文件夹', style: TextStyle(color: Colors.grey, fontSize: 12)),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: sync.selectedFolders.map((path) {
              return Chip(
                avatar: const Icon(Icons.folder, size: 14),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                label: Text(path, style: const TextStyle(fontSize: 11)),
                onDeleted: () => sync.removeFolder(path),
              );
            }).toList(),
          ),
        const SizedBox(height: 10),

        // 3. 开始比对大按钮
        FilledButton.icon(
          icon: sync.isComparing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.search, size: 18),
          label: Text(sync.isComparing ? '正在比对歌曲文件...' : '开始对比歌曲差异'),
          onPressed: (sync.selectedPlaylist != null && sync.selectedFolders.isNotEmpty && !sync.isComparing)
              ? _handleStartComparison
              : null,
        ),
      ],
    );
  }

  Widget _buildStatBadge(String label, int count, Color color, SyncDifferenceType type) {
    final isSelected = _filterType == type;

    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _filterType = isSelected ? null : type;
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: BoxDecoration(
            color: isSelected ? color.withAlpha(40) : color.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? color : Colors.transparent, width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                count.toString(),
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(color: color, fontSize: 9.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyncTile(SyncItem item, SyncProvider sync, bool isNarrow) {
    Color typeColor;
    IconData typeIcon;
    switch (item.type) {
      case SyncDifferenceType.copyFromLocal:
        typeColor = Colors.teal;
        typeIcon = Icons.copy_all_rounded;
        break;
      case SyncDifferenceType.missingInLocal:
        typeColor = Colors.blue;
        typeIcon = Icons.cloud_download_outlined;
        break;
      case SyncDifferenceType.extraInLocal:
        typeColor = Colors.red;
        typeIcon = Icons.delete_outline;
        break;
      case SyncDifferenceType.matched:
        typeColor = Colors.green;
        typeIcon = Icons.check_circle_outline;
        break;
    }

    return CheckboxListTile(
      value: item.isSelected,
      dense: isNarrow,
      contentPadding: EdgeInsets.symmetric(horizontal: isNarrow ? 8 : 12, vertical: 0),
      onChanged: item.type == SyncDifferenceType.matched ? null : (_) => sync.toggleItemSelection(item),
      secondary: Icon(typeIcon, color: typeColor, size: isNarrow ? 20 : 24),
      title: Text(
        item.displayTitle,
        style: TextStyle(fontWeight: FontWeight.w500, fontSize: isNarrow ? 13 : 14),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.displaySubtitle, style: TextStyle(fontSize: isNarrow ? 10.5 : 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (item.executionMessage != null)
            Text(item.executionMessage!, style: TextStyle(fontSize: isNarrow ? 10 : 10.5, color: typeColor)),
        ],
      ),
    );
  }
}