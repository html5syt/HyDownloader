import 'package:flutter/material.dart';

/// 专为网易云音乐 CDN 设计的跨平台高可靠网络图片加载组件
/// 自动注入官方浏览器 User-Agent 与 Referer 请求头，避免被网易 CDN 拦截返回 403
/// 自动升级 http 为 https，提供优雅占位与异常回退
class AppNetworkImage extends StatelessWidget {
  /// 图片网络直链
  final String url;

  /// 显示宽度
  final double? width;

  /// 显示高度
  final double? height;

  /// 图片缩放裁剪模式
  final BoxFit fit;

  /// 圆角半径
  final BorderRadius? borderRadius;

  /// 加载失败或 URL 为空时的自定义占位组件
  final Widget? fallback;

  /// 网易云音乐图片防盗链与反爬验证所需的请求头
  static const Map<String, String> neteaseHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
    'Referer': 'https://music.163.com/',
    'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
  };

  const AppNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallback,
  });

  /// 规整图片链接：升级 https 并移除无效前后缀
  String get _secureUrl {
    var u = url.trim();
    if (u.startsWith('http://')) {
      u = u.replaceFirst('http://', 'https://');
    }
    return u;
  }

  @override
  Widget build(BuildContext context) {
    final cleanUrl = _secureUrl;
    final defaultFallback = fallback ?? _buildDefaultFallback(context);

    if (cleanUrl.isEmpty) {
      return _wrapRadius(defaultFallback);
    }

    final imageWidget = Image.network(
      cleanUrl,
      width: width,
      height: height,
      fit: fit,
      headers: neteaseHeaders,
      errorBuilder: (context, error, stackTrace) {
        return defaultFallback;
      },
    );

    return _wrapRadius(imageWidget);
  }

  Widget _wrapRadius(Widget child) {
    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: child,
      );
    }
    return child;
  }

  Widget _buildDefaultFallback(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      color: colorScheme.surfaceContainerHighest.withAlpha(80),
      child: Icon(
        Icons.music_note,
        color: colorScheme.primary.withAlpha(120),
        size: (width != null && height != null) ? (width! * 0.45).clamp(16.0, 48.0) : 24.0,
      ),
    );
  }
}
