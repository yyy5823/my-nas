import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 自适应图片组件
///
/// 根据 URL 类型自动选择合适的图片加载方式：
/// - file:// 协议：使用 Image.file 加载本地文件
/// - http/https 协议：使用 CachedNetworkImage 加载网络图片
class AdaptiveImage extends StatelessWidget {
  const AdaptiveImage({
    super.key,
    required this.imageUrl,
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
  static bool isLocalFile(String url) {
    return url.startsWith('file://');
  }

  /// 检查是否是网络 URL
  static bool isNetworkUrl(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  /// 检查 URL 是否可以直接加载（支持的协议）
  static bool isSupportedUrl(String url) {
    return isLocalFile(url) || isNetworkUrl(url) || !url.contains('://');
  }

  /// 将 file:// URL 转换为本地文件路径
  static String? toLocalPath(String url) {
    if (!isLocalFile(url)) return null;
    try {
      final uri = Uri.parse(url);
      return uri.toFilePath(windows: Platform.isWindows);
    } on Exception catch (e) {
      logger.e('转换本地文件路径失败', e);
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 检查是否是不支持的协议（如 smb://）
    if (!isSupportedUrl(imageUrl)) {
      return errorWidget?.call(context, 'Unsupported URL scheme') ??
          _buildDefaultError(context);
    }

    if (isLocalFile(imageUrl)) {
      return _buildLocalImage(context);
    } else if (isNetworkUrl(imageUrl)) {
      return _buildNetworkImage(context);
    } else {
      // 假设是本地路径
      return _buildLocalPathImage(context, imageUrl);
    }
  }

  Widget _buildLocalImage(BuildContext context) {
    final localPath = toLocalPath(imageUrl);
    if (localPath == null) {
      return errorWidget?.call(context, 'Invalid file URL') ??
          _buildDefaultError(context);
    }
    return _buildLocalPathImage(context, localPath);
  }

  Widget _buildLocalPathImage(BuildContext context, String path) {
    final file = File(path);

    return FutureBuilder<bool>(
      future: file.exists(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return placeholder?.call(context) ?? _buildDefaultPlaceholder();
        }

        if (snapshot.data != true) {
          return errorWidget?.call(context, 'File not found') ??
              _buildDefaultError(context);
        }

        return AnimatedSwitcher(
          duration: fadeInDuration,
          child: Image.file(
            file,
            key: ValueKey(path),
            fit: fit,
            width: width,
            height: height,
            errorBuilder: (context, error, stackTrace) =>
                errorWidget?.call(context, error) ?? _buildDefaultError(context),
          ),
        );
      },
    );
  }

  Widget _buildNetworkImage(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      width: width,
      height: height,
      fadeInDuration: fadeInDuration,
      placeholder: (context, _) =>
          placeholder?.call(context) ?? _buildDefaultPlaceholder(),
      errorWidget: (context, _, error) =>
          errorWidget?.call(context, error) ?? _buildDefaultError(context),
    );
  }

  Widget _buildDefaultPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[300],
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _buildDefaultError(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[800],
      child: const Icon(
        Icons.broken_image_outlined,
        color: Colors.grey,
        size: 48,
      ),
    );
  }
}
