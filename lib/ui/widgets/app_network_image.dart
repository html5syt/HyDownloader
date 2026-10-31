import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../config/app_constants.dart';

/// 全局内存图片缓存，避免重复拉取并实现即时呈现
final Map<String, Uint8List> _globalImageMemoryCache = {};

/// 单例 Dio 客户端，预设官方防盗链 Header 与连接超时限制
final Dio _imageDio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 10),
    headers: AppConstants.neteaseImageHeaders,
    responseType: ResponseType.bytes,
  ),
);

/// 专为网易云音乐 CDN 设计的跨平台高可靠网络图片加载组件
/// 采用 Dio 底层通信以规避 Windows/Flutter 原生 HttpClient 偶发 IPv6 握手挂起与 403 拦截，
/// 并提供内存快速缓存、智能 HTTPS 升序与优雅占位
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
  static const Map<String, String> neteaseHeaders = AppConstants.neteaseImageHeaders;

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

  Future<Uint8List?> _loadImageBytes(String cleanUrl) async {
    if (cleanUrl.isEmpty) return null;
    if (_globalImageMemoryCache.containsKey(cleanUrl)) {
      return _globalImageMemoryCache[cleanUrl];
    }

    try {
      final res = await _imageDio.get<List<int>>(cleanUrl);
      if (res.data != null && res.data!.isNotEmpty) {
        final bytes = Uint8List.fromList(res.data!);
        _globalImageMemoryCache[cleanUrl] = bytes;
        return bytes;
      }
    } catch (_) {
      // 若 HTTPS 失败则降级尝试 HTTP
      if (cleanUrl.startsWith('https://')) {
        try {
          final httpUrl = cleanUrl.replaceFirst('https://', 'http://');
          final res2 = await _imageDio.get<List<int>>(httpUrl);
          if (res2.data != null && res2.data!.isNotEmpty) {
            final bytes2 = Uint8List.fromList(res2.data!);
            _globalImageMemoryCache[cleanUrl] = bytes2;
            return bytes2;
          }
        } catch (_) {}
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cleanUrl = _secureUrl;
    final defaultFallback = fallback ?? _buildDefaultFallback(context);

    if (cleanUrl.isEmpty) {
      return _wrapRadius(defaultFallback);
    }

    // 优先命中内存缓存
    if (_globalImageMemoryCache.containsKey(cleanUrl)) {
      return _wrapRadius(
        Image.memory(
          _globalImageMemoryCache[cleanUrl]!,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, _, _) => defaultFallback,
        ),
      );
    }

    return _wrapRadius(
      FutureBuilder<Uint8List?>(
        future: _loadImageBytes(cleanUrl),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              snapshot.hasData &&
              snapshot.data != null) {
            return Image.memory(
              snapshot.data!,
              width: width,
              height: height,
              fit: fit,
              errorBuilder: (_, _, _) => defaultFallback,
            );
          }

          // 加载中或错误时展示占位
          return defaultFallback;
        },
      ),
    );
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
        size: (width != null && height != null)
            ? (width! * 0.45).clamp(16.0, 48.0)
            : 24.0,
      ),
    );
  }
}