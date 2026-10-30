import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../config/app_constants.dart';
import '../../services/storage/storage_service.dart';

/// 应用全局设置对话框
/// 支持自定义试听预览音质、默认下载音质、任意并发下载线程数与文件保存路径
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  /// 静态快捷弹出方法
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const SettingsDialog(),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final StorageService _storage = StorageService.instance;

  late String _downloadQuality;
  late String _previewQuality;
  late int _maxConcurrentThreads;
  late String _downloadDir;
  late bool _downloadLyrics;
  late bool _downloadTranslation;
  late bool _writeMetadata;

  final TextEditingController _threadController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _downloadQuality = _storage.getAudioRate();
    _previewQuality = _storage.getPreviewAudioRate();
    _maxConcurrentThreads = _storage.getMaxConcurrentDownloads();
    _downloadLyrics = _storage.getDownloadLyrics();
    _downloadTranslation = _storage.getDownloadTranslation();
    _writeMetadata = _storage.getWriteMetadata();
    _threadController.text = _maxConcurrentThreads.toString();
    _downloadDir = '';
    _loadDir();
  }

  @override
  void dispose() {
    _threadController.dispose();
    super.dispose();
  }

  Future<void> _loadDir() async {
    final dir = await _storage.getDownloadDirectory();
    if (mounted) {
      setState(() {
        _downloadDir = dir;
      });
    }
  }

  Future<void> _pickDir() async {
    final selected = await FilePicker.getDirectoryPath(dialogTitle: '选择音乐下载保存位置');
    if (selected != null && selected.isNotEmpty) {
      await _storage.saveDownloadDirectory(selected);
      setState(() {
        _downloadDir = selected;
      });
    }
  }

  Future<void> _saveAndClose() async {
    final parsedThreads = int.tryParse(_threadController.text.trim()) ?? _maxConcurrentThreads;
    final effectiveThreads = parsedThreads < 1 ? 1 : parsedThreads;

    await _storage.saveAudioRate(_downloadQuality);
    await _storage.savePreviewAudioRate(_previewQuality);
    await _storage.saveMaxConcurrentDownloads(effectiveThreads);
    await _storage.saveDownloadLyrics(_downloadLyrics);
    await _storage.saveDownloadTranslation(_downloadTranslation);
    await _storage.saveWriteMetadata(_writeMetadata);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存'), duration: Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 头部
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '偏好设置',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 16),

              Expanded(
                child: ListView(
                  children: [
                    // 1. 默认下载音质设置
                    _buildSectionHeader('下载音质'),
                    DropdownButtonFormField<String>(
                      initialValue: _downloadQuality,
                      decoration: const InputDecoration(
                        labelText: '默认下载品质',
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      items: AudioQuality.availableQualities.map((q) {
                        return DropdownMenuItem(
                          value: q.level,
                          child: Text('${q.label} (${q.level})'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _downloadQuality = val);
                      },
                    ),
                    const SizedBox(height: 16),

                    // 2. 试听预览音质设置
                    _buildSectionHeader('在线试听音质'),
                    DropdownButtonFormField<String>(
                      initialValue: _previewQuality,
                      decoration: const InputDecoration(
                        labelText: '默认试听品质',
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'standard', child: Text('标准品质 (128Kbps - 极速缓冲)')),
                        DropdownMenuItem(value: 'higher', child: Text('较高品质 (192Kbps)')),
                        DropdownMenuItem(value: 'exhigh', child: Text('极高品质 (320Kbps - 推荐平衡)')),
                        DropdownMenuItem(value: 'lossless', child: Text('无损品质 (FLAC)')),
                        DropdownMenuItem(value: 'hires', child: Text('Hi-Res 高解析度')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _previewQuality = val);
                      },
                    ),
                    const SizedBox(height: 16),

                    // 3. 并发下载线程数（完美对齐 +- 号）
                    _buildSectionHeader('并发下载线程数'),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _threadController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '同时下载的最大任务数',
                              hintText: '例如: 3, 5, 8, 16...',
                              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: '减少线程',
                          icon: const Icon(Icons.remove),
                          onPressed: () {
                            final current = int.tryParse(_threadController.text) ?? 1;
                            if (current > 1) {
                              _threadController.text = (current - 1).toString();
                            }
                          },
                        ),
                        const SizedBox(width: 4),
                        IconButton.filledTonal(
                          tooltip: '增加线程',
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            final current = int.tryParse(_threadController.text) ?? 1;
                            _threadController.text = (current + 1).toString();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '允许根据您的带宽与设备性能任意设定',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),

                    // 4. 下载保存目录
                    _buildSectionHeader('存储目录'),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withAlpha(40),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.folder, size: 20, color: Colors.amber),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _downloadDir.isEmpty ? '加载中...' : _downloadDir,
                              style: const TextStyle(fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            onPressed: _pickDir,
                            child: const Text('更改'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 5. 歌词与元数据开关
                    _buildSectionHeader('歌词与歌曲信息'),
                    SwitchListTile(
                      title: const Text('下载同步歌词文件 (.lrc)', style: TextStyle(fontSize: 14)),
                      value: _downloadLyrics,
                      onChanged: (val) => setState(() => _downloadLyrics = val),
                    ),
                    SwitchListTile(
                      title: const Text('合并翻译歌词至时间轴', style: TextStyle(fontSize: 14)),
                      value: _downloadTranslation,
                      onChanged: _downloadLyrics
                          ? (val) => setState(() => _downloadTranslation = val)
                          : null,
                    ),
                    SwitchListTile(
                      title: const Text('写入音频 ID3 标签与高清封面', style: TextStyle(fontSize: 14)),
                      value: _writeMetadata,
                      onChanged: (val) => setState(() => _writeMetadata = val),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saveAndClose,
                child: const Text('保存配置'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
