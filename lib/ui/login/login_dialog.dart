import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../providers/auth_provider.dart';
import '../../providers/home_provider.dart';
import 'qr_login_view.dart';

/// 统一登录认证对话框
/// 整合伪造令牌、抓包导入、手机扫码与 Cookie 四种主流登录方式
class LoginDialog extends StatefulWidget {
  const LoginDialog({super.key});

  /// 静态快捷弹出方法
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const LoginDialog(),
    );
  }

  @override
  State<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _packetCaptureController = TextEditingController();
  final TextEditingController _cookieController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _packetCaptureController.dispose();
    _cookieController.dispose();
    super.dispose();
  }

  void _onLoginSuccess() {
    final auth = context.read<AuthProvider>();
    final home = context.read<HomeProvider>();
    home.loadUserLibrary(auth.currentUser?.userId);

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('欢迎，${auth.currentUser?.nickname ?? "用户"}！'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final auth = context.watch<AuthProvider>();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 头部标题与关闭按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '账号登录',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 分页标签栏
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: colorScheme.primary,
                indicatorColor: colorScheme.primary,
                tabs: const [
                  Tab(text: '虚拟令牌'),
                  Tab(text: '抓包导入'),
                  Tab(text: '手机扫码'),
                  Tab(text: 'Cookie'),
                ],
              ),
              const SizedBox(height: 16),

              // 内容区
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildFakeTokenTab(auth),
                    _buildPacketCaptureTab(auth),
                    QrLoginView(onSuccess: _onLoginSuccess),
                    _buildCookieTab(auth),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 1. 虚拟令牌登录视图
  Widget _buildFakeTokenTab(AuthProvider auth) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.security, size: 56, color: Colors.blueAccent),
        const SizedBox(height: 16),
        const Text(
          '一键生成虚拟设备令牌',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            '模拟车载设备身份免密访问网易云音乐，无需输入账号密码，即可正常搜索试听与下载公共曲目。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: auth.isLoading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.flash_on),
          label: const Text('立即生成并登录'),
          onPressed: auth.isLoading
              ? null
              : () async {
                  final ok = await auth.loginWithFakeToken();
                  if (ok) _onLoginSuccess();
                },
        ),
        if (auth.errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(auth.errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
      ],
    );
  }

  /// 2. 抓包导入登录视图
  Widget _buildPacketCaptureTab(AuthProvider auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '导入抓包生成的 capture.json 数据，自动同步已登录账户。',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: TextField(
            controller: _packetCaptureController,
            maxLines: null,
            expands: true,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              hintText: '在此粘贴 capture.json 内容，或点击下方按钮选择文件...',
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.file_open_outlined, size: 18),
              label: const Text('选择文件'),
              onPressed: () async {
                final files = await FilePicker.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['json', 'txt'],
                );
                final pickedPath = files.firstOrNull?.path;
                if (pickedPath != null) {
                  final text = await File(pickedPath).readAsString();
                  _packetCaptureController.text = text;
                }
              },
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.paste, size: 18),
              label: const Text('粘贴剪贴板'),
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                if (data?.text != null) {
                  _packetCaptureController.text = data!.text!;
                }
              },
            ),
            const Spacer(),
            FilledButton(
              onPressed: auth.isLoading
                  ? null
                  : () async {
                      final text = _packetCaptureController.text.trim();
                      if (text.isEmpty) return;
                      final ok = await auth.loginWithPacketCapture(text);
                      if (ok) _onLoginSuccess();
                    },
              child: const Text('导入登录'),
            ),
          ],
        ),
        if (auth.errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(auth.errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
      ],
    );
  }

  /// 3. Cookie 登录视图
  Widget _buildCookieTab(AuthProvider auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '直接输入网页端 MUSIC_U 或完整 Cookie 字符串：',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TextField(
            controller: _cookieController,
            maxLines: null,
            expands: true,
            decoration: const InputDecoration(
              hintText: '例如: MUSIC_U=xxxx; __csrf=yyyy',
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: auth.isLoading
              ? null
              : () async {
                  final text = _cookieController.text.trim();
                  if (text.isEmpty) return;
                  final ok = await auth.loginWithCookie(text);
                  if (ok) _onLoginSuccess();
                },
          child: const Text('确认登录'),
        ),
        if (auth.errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(auth.errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
      ],
    );
  }
}
