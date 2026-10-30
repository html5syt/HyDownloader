import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/download_task.dart';
import '../../providers/download_provider.dart';
import '../../services/storage/storage_service.dart';
import '../widgets/empty_state_view.dart';

/// 下载中心页面
/// 管理正在下载与已完成的任务队列，支持速度监测、并发管理与文件目录更改
class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final StorageService _storage = StorageService.instance;
  String _currentDownloadDir = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDir();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDir() async {
    final dir = await _storage.getDownloadDirectory();
    if (mounted) {
      setState(() {
        _currentDownloadDir = dir;
      });
    }
  }

  Future<void> _pickDownloadDir() async {
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: '选择音乐下载保存目录',
    );
    if (selected != null && selected.isNotEmpty) {
      await _storage.saveDownloadDirectory(selected);
      setState(() {
        _currentDownloadDir = selected;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final download = context.watch<DownloadProvider>();

    final activeTasks = download.tasks.where((t) => t.status != DownloadStatus.completed).toList();
    final completedTasks = download.tasks.where((t) => t.status == DownloadStatus.completed).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('下载管理'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorScheme.primary,
          indicatorColor: colorScheme.primary,
          tabs: [
            Tab(text: '进行中 (${activeTasks.length})'),
            Tab(text: '已完成 (${completedTasks.length})'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '全部暂停',
            icon: const Icon(Icons.pause_circle_outline),
            onPressed: activeTasks.isEmpty ? null : () => download.pauseAll(),
          ),
          IconButton(
            tooltip: '全部继续',
            icon: const Icon(Icons.play_circle_outline),
            onPressed: activeTasks.isEmpty ? null : () => download.resumeAll(),
          ),
          IconButton(
            tooltip: '清空已完成记录',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: completedTasks.isEmpty ? null : () => download.clearCompleted(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 顶部下载存储路径提示条
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: colorScheme.surfaceContainerHighest.withAlpha(50),
            child: Row(
              children: [
                const Icon(Icons.folder_outlined, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '存储位置: $_currentDownloadDir',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: _pickDownloadDir,
                  child: const Text('更改目录'),
                ),
              ],
            ),
          ),

          // 列表视图
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTaskList(activeTasks, isCompletedTab: false),
                _buildTaskList(completedTasks, isCompletedTab: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList(List<DownloadTask> tasks, {required bool isCompletedTab}) {
    if (tasks.isEmpty) {
      return EmptyStateView(
        icon: isCompletedTab ? Icons.done_all : Icons.download_done,
        title: isCompletedTab ? '暂无已完成的下载' : '当前没有正在下载的任务',
        subtitle: isCompletedTab ? '下载完成的曲目将展示在此处' : '前往歌单或播客添加歌曲开始下载',
      );
    }

    final download = context.read<DownloadProvider>();

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.song.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${task.song.artistString} · ${task.qualityLevel.toUpperCase()}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusBadge(task),
                  const SizedBox(width: 8),
                  _buildActionButtons(task, download),
                ],
              ),
              const SizedBox(height: 8),

              // 进度条
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: task.status == DownloadStatus.completed ? 1.0 : task.progress,
                  minHeight: 4,
                  backgroundColor: Colors.grey.withAlpha(30),
                  valueColor: AlwaysStoppedAnimation(
                    task.status == DownloadStatus.failed
                        ? Colors.red
                        : task.status == DownloadStatus.paused
                            ? Colors.orange
                            : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // 底部状态与速度数据
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    task.errorMessage ??
                        (task.status == DownloadStatus.downloading
                            ? '${(task.progress * 100).toStringAsFixed(1)}%'
                            : task.status.label),
                    style: TextStyle(
                      fontSize: 11,
                      color: task.errorMessage != null ? Colors.red : Colors.grey,
                    ),
                  ),
                  if (task.status == DownloadStatus.downloading && task.speedBytesPerSec > 0)
                    Text(
                      task.formattedSpeed,
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary),
                    )
                  else
                    Text(
                      task.formattedTotalSize,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(DownloadTask task) {
    Color color;
    switch (task.status) {
      case DownloadStatus.completed:
        color = Colors.green;
        break;
      case DownloadStatus.downloading:
        color = Colors.blue;
        break;
      case DownloadStatus.paused:
        color = Colors.orange;
        break;
      case DownloadStatus.failed:
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(100), width: 0.8),
      ),
      child: Text(
        task.status.label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildActionButtons(DownloadTask task, DownloadProvider download) {
    if (task.status == DownloadStatus.completed) {
      return IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: () => download.cancelTask(task),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (task.status == DownloadStatus.downloading)
          IconButton(
            icon: const Icon(Icons.pause, size: 20),
            onPressed: () => download.pauseTask(task),
          )
        else if (task.status == DownloadStatus.paused)
          IconButton(
            icon: const Icon(Icons.play_arrow, size: 20),
            onPressed: () => download.resumeTask(task),
          )
        else if (task.status == DownloadStatus.failed)
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => download.retryTask(task),
          ),
        IconButton(
          icon: const Icon(Icons.close, size: 20),
          onPressed: () => download.cancelTask(task),
        ),
      ],
    );
  }
}
