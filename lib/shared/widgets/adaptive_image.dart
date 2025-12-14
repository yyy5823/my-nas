import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';

/// 自适应图片组件
///
/// 根据 URL 类型自动选择合适的图片加载方式：
/// - file:// 协议：使用 Image.file 加载本地文件
/// - http/https 协议：使用 CachedNetworkImage 加载网络图片
class AdaptiveImage extends StatefulWidget {
  const AdaptiveImage({
    required this.imageUrl, super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
    this.fadeInDuration = const Duration(milliseconds: 300),
  });

  /// 图片 URL（支持 file://、http://、https://）
  final String imageUrl;

  /// 图片填充方式
  final BoxFit fit;

  /// 宽度
  final double? width;

  /// 高度
  final double? height;

  /// 加载中占位组件
  final Widget Function(BuildContext context)? placeholder;

  /// 错误时显示的组件
  final Widget Function(BuildContext context, Object error)? errorWidget;

  /// 淡入动画时长
  final Duration fadeInDuration;

  /// 检查是否是本地文件 URL
  static bool isLocalFile(String url) => url.startsWith('file://');

  /// 检查是否是网络 URL
  static bool isNetworkUrl(String url) => url.startsWith('http://') || url.startsWith('https://');

  /// 检查 URL 是否可以直接加载（支持的协议）
  static bool isSupportedUrl(String url) => isLocalFile(url) || isNetworkUrl(url) || !url.contains('://');

  /// 将 file:// URL 转换为本地文件路径
  static String? toLocalPath(String url) {
    if (!isLocalFile(url)) return null;
    try {
      final uri = Uri.parse(url);
      return uri.toFilePath(windows: Platform.isWindows);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'toLocalPath');
      return null;
    }
  }

  @override
  State<AdaptiveImage> createState() => _AdaptiveImageState();
}

class _AdaptiveImageState extends State<AdaptiveImage> {
  // 缓存文件存在检查结果，避免每次 rebuild 时重新检查导致闪烁
  bool? _fileExistsCache;
  String? _cachedPath;

  @override
  void didUpdateWidget(AdaptiveImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果 URL 变了，清除缓存
    if (oldWidget.imageUrl != widget.imageUrl) {
      _fileExistsCache = null;
      _cachedPath = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 检查是否是不支持的协议（如 smb://）
    if (!AdaptiveImage.isSupportedUrl(widget.imageUrl)) {
      return widget.errorWidget?.call(context, 'Unsupported URL scheme') ??
          _buildDefaultError(context);
    }

    if (AdaptiveImage.isLocalFile(widget.imageUrl)) {
      return _buildLocalImage(context);
    } else if (AdaptiveImage.isNetworkUrl(widget.imageUrl)) {
      return _buildNetworkImage(context);
    } else {
      // 假设是本地路径
      return _buildLocalPathImage(context, widget.imageUrl);
    }
  }

  Widget _buildLocalImage(BuildContext context) {
    final localPath = AdaptiveImage.toLocalPath(widget.imageUrl);
    if (localPath == null) {
      return widget.errorWidget?.call(context, 'Invalid file URL') ??
          _buildDefaultError(context);
    }
    return _buildLocalPathImage(context, localPath);
  }

  Widget _buildLocalPathImage(BuildContext context, String path) {
    // 如果已经缓存了这个路径的检查结果，直接使用
    if (_cachedPath == path && _fileExistsCache != null) {
      return _buildLocalPathImageContent(context, path, _fileExistsCache!);
    }

    final file = File(path);

    return FutureBuilder<bool>(
      future: file.exists(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // 第一次加载时显示占位符
          return widget.placeholder?.call(context) ?? _buildDefaultPlaceholder();
        }

        final exists = snapshot.data ?? false;
        // 缓存结果，避免后续重建时闪烁
        _fileExistsCache = exists;
        _cachedPath = path;

        return _buildLocalPathImageContent(context, path, exists);
      },
    );
  }

  Widget _buildLocalPathImageContent(BuildContext context, String path, bool exists) {
    if (!exists) {
      return widget.errorWidget?.call(context, 'File not found') ??
          _buildDefaultError(context);
    }

    return Image.file(
      File(path),
      key: ValueKey(path),
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      // 使用 frameBuilder 实现平滑加载，避免闪烁
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return widget.placeholder?.call(context) ?? _buildDefaultPlaceholder();
      },
      errorBuilder: (context, error, stackTrace) =>
          widget.errorWidget?.call(context, error) ?? _buildDefaultError(context),
    );
  }

  Widget _buildNetworkImage(BuildContext context) => CachedNetworkImage(
      imageUrl: widget.imageUrl,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      fadeInDuration: widget.fadeInDuration,
      placeholder: (context, _) =>
          widget.placeholder?.call(context) ?? _buildDefaultPlaceholder(),
      errorWidget: (context, _, error) =>
          widget.errorWidget?.call(context, error) ?? _buildDefaultError(context),
    );

  Widget _buildDefaultPlaceholder() => Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[300],
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );

  Widget _buildDefaultError(BuildContext context) => Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[800],
      child: const Icon(
        Icons.broken_image_outlined,
        color: Colors.grey,
        size: 48,
      ),
    );
}
