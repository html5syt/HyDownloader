import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/sync_item.dart';
import '../../providers/sync_provider.dart';
import '../../providers/home_provider.dart';
import '../widgets/empty_state_view.dart';

/// 歌单文件双向同步页面
/// 允许用户选定一个在线歌单与多个本地文件夹进行歌曲比对，
/// 智能找出云端缺失与本地多余曲目，支持全选/部分勾选同步与清理
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  SyncDifferenceType? _filterType;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SyncProvider>().loadSavedFolders();
    });
  }

  /// 弹出本地文件夹选择器
  Future<void> _pickFolder() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: '选择要参与比对的本地音乐文件夹',
    );
    if (path != null && path.isNotEmpty && mounted) {
      await context.read<SyncProvider>().addFolder(path);
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
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: pl.coverImgUrl.isNotEmpty
                            ? Image.network(pl.coverImgUrl, width: 40, height: 40, fit: BoxFit.cover)
                            : Container(width: 40, height: 40, color: Colors.grey),
                      ),
                      title: Text(pl.name, maxLines: 1, overflow: TextOverflow.ellipsis),
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

  /// 确认并执行同步
  Future<void> _confirmAndExecuteSync() async {
    final sync = context.read<SyncProvider>();
    final selectedItems = sync.syncItems.where((i) => i.isSelected).toList();
    if (selectedItems.isEmpty) return;

    final extraCount = selectedItems.where((i) => i.type == SyncDifferenceType.extraInLocal).length;
    final missingCount = selectedItems.where((i) => i.type == SyncDifferenceType.missingInLocal).length;

    // 如果包含需要删除的本地歌曲，弹出二次确认对话框保证安全
    if (extraCount > 0) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认同步操作'),
          content: Text(
            '本次同步将包含：\n'
            '• 下载 $missingCount 首缺失歌曲到本地\n'
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
    final sync = context.watch<SyncProvider>();

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
                ? () => sync.startComparison()
                : null,
          ),
        ],
      ),
      body: Column(
        children: [
          // 顶部配置面板：选择歌单与本地文件夹
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. 在线歌单选择行
                  Row(
                    children: [
                      const Icon(Icons.queue_music, size: 22, color: Colors.blueAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sync.selectedPlaylist != null
                              ? '已选歌单: ${sync.selectedPlaylist!.name}'
                              : '请选择一个在线歌单参与比对',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.arrow_drop_down, size: 18),
                        label: Text(sync.selectedPlaylist != null ? '更改' : '选择歌单'),
                        onPressed: _pickPlaylist,
                      ),
                    ],
                  ),
                  const Divider(height: 20),

                  // 2. 本地文件夹多选区
                  Row(
                    children: [
                      const Icon(Icons.folder_copy_outlined, size: 22, color: Colors.amber),
                      const SizedBox(width: 8),
                      const Text('本地比对文件夹 (可添加多个):', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('添加文件夹'),
                        onPressed: _pickFolder,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (sync.selectedFolders.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text('尚未添加任何本地文件夹，请点击上方“添加文件夹”', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: sync.selectedFolders.map((path) {
                        return Chip(
                          avatar: const Icon(Icons.folder, size: 16),
                          label: Text(path, style: const TextStyle(fontSize: 12)),
                          onDeleted: () => sync.removeFolder(path),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 12),

                  // 3. 开始比对大按钮
                  FilledButton.icon(
                    icon: sync.isComparing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.search),
                    label: Text(sync.isComparing ? '正在比对歌曲文件...' : '开始对比歌曲差异'),
                    onPressed: (sync.selectedPlaylist != null && sync.selectedFolders.isNotEmpty && !sync.isComparing)
                        ? () => sync.startComparison()
                        : null,
                  ),
                ],
              ),
            ),
          ),

          // 差异统计卡片与筛选 Chips
          if (sync.syncItems.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  _buildStatBadge('缺失歌曲 (待下载)', sync.missingCount, Colors.blue, SyncDifferenceType.missingInLocal),
                  const SizedBox(width: 8),
                  _buildStatBadge('本地多余 (待清理)', sync.extraCount, Colors.red, SyncDifferenceType.extraInLocal),
                  const SizedBox(width: 8),
                  _buildStatBadge('已同步', sync.matchedCount, Colors.green, SyncDifferenceType.matched),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 全选与全不选快捷栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
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
          ],

          // 差异对比列表
          Expanded(
            child: sync.isComparing
                ? const Center(child: CircularProgressIndicator())
                : sync.errorMessage != null
                    ? EmptyStateView(
                        icon: Icons.error_outline,
                        title: '比对失败',
                        subtitle: sync.errorMessage,
                        actionText: '重试',
                        onAction: () => sync.startComparison(),
                      )
                    : sync.syncItems.isEmpty
                        ? const EmptyStateView(
                            icon: Icons.compare_arrows_rounded,
                            title: '请配置歌单与文件夹后开始对比',
                            subtitle: '系统将对比分析在线歌单与本地文件，精准找出缺失和多余的歌曲',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            itemCount: filteredItems.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = filteredItems[index];
                              return _buildSyncTile(item, sync);
                            },
                          ),
          ),

          // 底部执行同步浮动栏
          if (sync.syncItems.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.cardColor,
                boxShadow: [
                  BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 8, offset: const Offset(0, -2)),
                ],
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '已选中 ${sync.selectedCount} 项操作',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (sync.isSyncing)
                        Text(sync.syncProgressText, style: TextStyle(fontSize: 12, color: theme.colorScheme.primary)),
                    ],
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    icon: sync.isSyncing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.sync),
                    label: const Text('开始同步'),
                    onPressed: (sync.selectedCount > 0 && !sync.isSyncing) ? _confirmAndExecuteSync : null,
                  ),
                ],
              ),
            ),
        ],
      ),
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
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withAlpha(40) : color.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? color : Colors.transparent, width: 1.5),
          ),
          child: Column(
            children: [
              Text(count.toString(), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: color, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyncTile(SyncItem item, SyncProvider sync) {
    Color typeColor;
    IconData typeIcon;
    switch (item.type) {
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
      onChanged: item.type == SyncDifferenceType.matched ? null : (_) => sync.toggleItemSelection(item),
      secondary: Icon(typeIcon, color: typeColor),
      title: Text(
        item.displayTitle,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.displaySubtitle, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (item.executionMessage != null)
            Text(item.executionMessage!, style: TextStyle(fontSize: 11, color: typeColor)),
        ],
      ),
    );
  }
}
