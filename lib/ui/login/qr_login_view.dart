import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../services/netease/auth_service.dart';

/// 扫码登录专用组件
/// 负责拉取 UniKey、绘制二维码、定时轮询扫码状态并在成功时通知外部
class QrLoginView extends StatefulWidget {
  final VoidCallback onSuccess;

  const QrLoginView({super.key, required this.onSuccess});

  @override
  State<QrLoginView> createState() => _QrLoginViewState();
}

class _QrLoginViewState extends State<QrLoginView> {
  final NeteaseAuthService _auth = NeteaseAuthService.instance;
  String? _qrUrl;
  String _statusText = '正在生成二维码...';
  bool _isLoading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _initQrCode();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _initQrCode() async {
    _pollTimer?.cancel();
    setState(() {
      _isLoading = true;
      _statusText = '正在生成登录二维码...';
    });

    try {
      final key = await _auth.getQrKey();
      if (!mounted) return;
      setState(() {
        _qrUrl = 'https://music.163.com/login?codekey=$key';
        _isLoading = false;
        _statusText = '请使用网易云音乐 App 扫描下方二维码';
      });
      _startPolling(key);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _statusText = '二维码生成失败: $e';
      });
    }
  }

  void _startPolling(String key) {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final code = await _auth.checkQrStatus(key);
        if (!mounted) return;

        if (code == 800) {
          // 二维码过期
          _pollTimer?.cancel();
          setState(() {
            _statusText = '二维码已过期，点击重新获取';
          });
        } else if (code == 801) {
          setState(() {
            _statusText = '等待扫描中...';
          });
        } else if (code == 802) {
          setState(() {
            _statusText = '已扫描！请在手机上点击“确认登录”';
          });
        } else if (code == 803) {
          // 授权成功
          _pollTimer?.cancel();
          setState(() {
            _statusText = '登录成功！正在同步账户信息...';
          });
          await context.read<AuthProvider>().completeQrLogin();
          if (mounted) {
            widget.onSuccess();
          }
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 二维码卡片容器
          Container(
            width: 200,
            height: 200,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(20),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _qrUrl != null
                    ? QrImageView(
                        data: _qrUrl!,
                        version: QrVersions.auto,
                        size: 176,
                        backgroundColor: Colors.white,
                      )
                    : Center(
                        child: IconButton(
                          icon: const Icon(Icons.refresh, size: 40),
                          onPressed: _initQrCode,
                        ),
                      ),
          ),
          const SizedBox(height: 16),
          Text(
            _statusText,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('刷新二维码'),
            onPressed: _initQrCode,
          ),
        ],
      ),
    );
  }
}
