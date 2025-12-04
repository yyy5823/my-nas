import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 支持流式加载的图片组件
///
/// 优先使用 HTTP URL，如果 URL 无效则通过流加载图片数据
class StreamImage extends StatefulWidget {
  const StreamImage({
    super.key,
    this.url,
    this.path,
    this.fileSystem,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.width,
    this.height,
    this.cacheKey,
  });

  /// HTTP URL（如果可用）
  final String? url;

  /// 文件路径（用于流式加载）
  final String? path;

  /// 文件系统（用于流式加载）
  final NasFileSystem? fileSystem;

  /// 图片填充模式
  final BoxFit fit;

  /// 加载中占位符
  final Widget? placeholder;

  /// 错误时显示的组件
  final Widget? errorWidget;

  /// 宽度
  final double? width;

  /// 高度
  final double? height;

  /// 缓存键
  final String? cacheKey;

  @override
  State<StreamImage> createState() => _StreamImageState();
}

class _StreamImageState extends State<StreamImage> {
  Uint8List? _imageBytes;
  bool _isLoading = false;
  bool _hasError = false;

  // 内存缓存（简单实现）
  static final Map<String, Uint8List> _memoryCache = {};
  static const int _maxCacheSize = 50; // 最多缓存50张图片

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(StreamImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.path != widget.path) {
      _loadImage();
    }
  }

  String get _cacheKey => widget.cacheKey ?? widget.path ?? widget.url ?? '';

  bool get _hasValidHttpUrl {
    final url = widget.url;
    if (url == null || url.isEmpty) return false;
    // 检查是否是有效的 HTTP/HTTPS URL
    return url.startsWith('http://') || url.startsWith('https://');
  }

  bool get _hasValidFileUrl {
    final url = widget.url;
    if (url == null || url.isEmpty) return false;
    // 检查是否是有效的 file:// URL
    return url.startsWith('file://');
  }

  /// 在iOS/macOS平台上，file:// URL应该使用流式加载
  /// 因为沙盒限制可能导致直接文件访问失败
  bool get _shouldUseStreamForFileUrl {
    if (!_hasValidFileUrl) return false;
    // 如果没有提供 fileSystem 和 path，无法使用流式加载
    if (widget.fileSystem == null || widget.path == null) return false;
    // iOS/macOS 平台优先使用流式加载
    return Platform.isIOS || Platform.isMacOS;
  }

  /// 从 file:// URL 获取本地文件路径
  String? get _localFilePath {
    final url = widget.url;
    if (url == null || !url.startsWith('file://')) return null;
    try {
      final uri = Uri.parse(url);
      return uri.toFilePath();
    } catch (e) {
      logger.w('StreamImage: 无法解析 file:// URL: $url', e);
      return null;
    }
  }

  Future<void> _loadImage() async {
    logger.d(
      'StreamImage: _loadImage called, url=${widget.url}, path=${widget.path}, hasFileSystem=${widget.fileSystem != null}',
    );

    // 如果有有效的 HTTP URL，使用 CachedNetworkImage
    if (_hasValidHttpUrl) {
      logger.d('StreamImage: Using HTTP URL: ${widget.url}');
      setState(() {
        _imageBytes = null;
        _hasError = false;
      });
      return;
    }

    // 如果有有效的 file:// URL，在非iOS/macOS平台使用 Image.file
    // 在iOS/macOS平台，由于沙盒限制，优先使用流式加载
    if (_hasValidFileUrl && !_shouldUseStreamForFileUrl) {
      logger.d('StreamImage: Using file:// URL: ${widget.url}');
      setState(() {
        _imageBytes = null;
        _hasError = false;
      });
      return;
    }

    // 检查内存缓存
    if (_cacheKey.isNotEmpty && _memoryCache.containsKey(_cacheKey)) {
      logger.d('StreamImage: Using cached image for $_cacheKey');
      setState(() {
        _imageBytes = _memoryCache[_cacheKey];
        _isLoading = false;
        _hasError = false;
      });
      return;
    }

    // 需要通过流加载
    if (widget.path == null || widget.fileSystem == null) {
      logger.w(
        'StreamImage: Cannot stream - path=${widget.path}, fileSystem=${widget.fileSystem != null ? "exists" : "null"}, url=${widget.url}',
      );
      setState(() {
        _hasError = true;
      });
      return;
    }

    logger.d('StreamImage: Starting stream load for ${widget.path}');
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final stream = await widget.fileSystem!.getFileStream(widget.path!);
      final bytes = <int>[];

      await for (final chunk in stream) {
        bytes.addAll(chunk);
        // 限制图片大小，防止内存溢出
        if (bytes.length > 50 * 1024 * 1024) {
          // 50MB 限制
          throw Exception('图片文件过大');
        }
      }

      logger.d(
        'StreamImage: Stream loaded ${bytes.length} bytes for ${widget.path}',
      );
      final imageData = Uint8List.fromList(bytes);

      // 添加到缓存
      if (_cacheKey.isNotEmpty) {
        // 如果缓存满了，清除一半
        if (_memoryCache.length >= _maxCacheSize) {
          final keysToRemove = _memoryCache.keys
              .take(_maxCacheSize ~/ 2)
              .toList();
          for (final key in keysToRemove) {
            _memoryCache.remove(key);
          }
        }
        _memoryCache[_cacheKey] = imageData;
      }

      if (mounted) {
        setState(() {
          _imageBytes = imageData;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      logger.e('StreamImage: 加载图片失败 ${widget.path}', e, stackTrace);
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 优先使用 HTTP URL
    if (_hasValidHttpUrl) {
      return CachedNetworkImage(
        imageUrl: widget.url!,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        placeholder: (_, __) => widget.placeholder ?? _buildPlaceholder(),
        errorWidget: (_, __, ___) => widget.errorWidget ?? _buildError(),
      );
    }

    // 使用本地文件 (file:// URL)
    // 在iOS/macOS上，如果有fileSystem和path，会fallback到流式加载
    if (_hasValidFileUrl && !_shouldUseStreamForFileUrl) {
      final filePath = _localFilePath;
      if (filePath != null) {
        return Image.file(
          File(filePath),
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          errorBuilder: (_, __, ___) => widget.errorWidget ?? _buildError(),
        );
      }
    }

    // 显示加载中
    if (_isLoading) {
      return widget.placeholder ?? _buildPlaceholder();
    }

    // 显示错误
    if (_hasError || _imageBytes == null) {
      return widget.errorWidget ?? _buildError();
    }

    // 显示流式加载的图片
    return Image.memory(
      _imageBytes!,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      errorBuilder: (_, __, ___) => widget.errorWidget ?? _buildError(),
    );
  }

  Widget _buildPlaceholder() => Container(
    width: widget.width,
    height: widget.height,
    color: Colors.grey[300],
    child: const Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );

  Widget _buildError() => Container(
    width: widget.width,
    height: widget.height,
    color: Colors.grey[200],
    child: Icon(Icons.broken_image_rounded, color: Colors.grey[400], size: 32),
  );

  /// 清除所有内存缓存
  static void clearCache() {
    _memoryCache.clear();
  }
}

/// 带缩略图的流式图片组件
///
/// 先显示缩略图，然后加载原图
class StreamImageWithThumbnail extends StatelessWidget {
  const StreamImageWithThumbnail({
    super.key,
    this.thumbnailUrl,
    this.fullUrl,
    this.path,
    this.fileSystem,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.width,
    this.height,
  });

  final String? thumbnailUrl;
  final String? fullUrl;
  final String? path;
  final NasFileSystem? fileSystem;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    // 使用缩略图 URL 或原图 URL 或流式加载
    return StreamImage(
      url: thumbnailUrl ?? fullUrl,
      path: path,
      fileSystem: fileSystem,
      fit: fit,
      placeholder: placeholder,
      errorWidget: errorWidget,
      width: width,
      height: height,
      cacheKey: path,
    );
  }
}
