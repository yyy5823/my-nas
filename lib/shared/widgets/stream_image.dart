import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:photo_view/photo_view.dart';

/// 支持流式加载的图片组件
///
/// 优先使用 HTTP URL，如果 URL 无效则通过流加载图片数据
///
/// 注意：在 iOS 平台上，对于 HTTPS URL（可能使用自签名证书），
/// 会自动降级到流式加载以避免证书验证问题。
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
    this.forceStream = false,
    this.enableZoom = false,
    this.minScale,
    this.maxScale,
    this.initialScale,
    this.backgroundColor,
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

  /// 强制使用流式加载（即使有有效的 HTTP URL）
  /// 用于解决自签名证书等问题
  final bool forceStream;

  /// 是否启用缩放功能（使用 PhotoView）
  final bool enableZoom;

  /// 最小缩放比例（仅在 enableZoom 为 true 时有效）
  final PhotoViewComputedScale? minScale;

  /// 最大缩放比例（仅在 enableZoom 为 true 时有效）
  final PhotoViewComputedScale? maxScale;

  /// 初始缩放比例（仅在 enableZoom 为 true 时有效）
  final PhotoViewComputedScale? initialScale;

  /// 背景颜色（仅在 enableZoom 为 true 时有效）
  final Color? backgroundColor;

  // 内存缓存（简单实现）
  static final Map<String, Uint8List> _memoryCache = {};
  static const int _maxCacheSize = 50; // 最多缓存50张图片

  /// 清除所有内存缓存
  static void clearCache() {
    _memoryCache.clear();
  }

  @override
  State<StreamImage> createState() => _StreamImageState();
}

class _StreamImageState extends State<StreamImage> {
  Uint8List? _imageBytes;
  bool _isLoading = false;
  bool _hasError = false;

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

  /// 检查是否应该使用流式加载
  ///
  /// 在以下情况下使用流式加载：
  /// 1. forceStream = true（强制流式加载）
  /// 2. iOS 平台有 HTTP/HTTPS URL（避免自签名证书和其他兼容性问题）
  /// 3. iOS/macOS 平台 + file:// URL（沙盒限制）
  ///
  /// 注意：iOS 上的 CachedNetworkImage 可能存在以下问题：
  /// - 自签名证书不被接受
  /// - 某些 NAS 的 HTTP 响应格式可能不兼容
  /// - 网络超时处理不一致
  /// 因此，对于 NAS 图片，统一使用流式加载以确保兼容性
  bool get _shouldUseStream {
    // 如果没有提供 fileSystem 和 path，无法使用流式加载
    if (widget.fileSystem == null || widget.path == null) return false;

    // 强制流式加载
    if (widget.forceStream) return true;

    // iOS 平台特殊处理：对于 NAS 的 HTTP/HTTPS URL，优先使用流式加载
    // 这样可以利用 Dio 的自签名证书支持和更好的错误处理
    if (Platform.isIOS) {
      if (_hasValidHttpUrl) {
        logger.d('StreamImage: iOS 平台 HTTP(S) URL，使用流式加载以确保兼容性');
        return true;
      }
      // file:// URL 由于沙盒限制需要流式加载
      if (_hasValidFileUrl) {
        return true;
      }
    }

    // macOS 平台对 HTTPS 自签名证书也有问题
    if (Platform.isMacOS) {
      if (_hasValidHttpUrl && widget.url!.startsWith('https://')) {
        logger.d('StreamImage: macOS HTTPS URL，使用流式加载以支持自签名证书');
        return true;
      }
      if (_hasValidFileUrl) {
        return true;
      }
    }

    return false;
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
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '无效的 file:// URL: $url');
      return null;
    }
  }

  Future<void> _loadImage() async {
    logger.d(
      'StreamImage: _loadImage called, url=${widget.url}, path=${widget.path}, hasFileSystem=${widget.fileSystem != null}, shouldUseStream=$_shouldUseStream',
    );

    // 检查是否应该使用流式加载（iOS/macOS 自签名证书、file:// URL、forceStream）
    if (_shouldUseStream) {
      await _loadImageViaStream();
      return;
    }

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

    // 需要通过流加载
    await _loadImageViaStream();
  }

  /// 通过流式加载图片
  ///
  /// 加载策略：
  /// 1. 如果有 URL，优先通过 getUrlStream 加载（可以加载缩略图）
  /// 2. 如果 URL 加载失败或没有 URL，通过 getFileStream 加载原文件
  Future<void> _loadImageViaStream() async {
    // 检查内存缓存
    if (_cacheKey.isNotEmpty && StreamImage._memoryCache.containsKey(_cacheKey)) {
      logger.d('StreamImage: Using cached image for $_cacheKey');
      setState(() {
        _imageBytes = StreamImage._memoryCache[_cacheKey];
        _isLoading = false;
        _hasError = false;
      });
      return;
    }

    // 需要通过流加载
    if (widget.fileSystem == null) {
      logger.w(
        'StreamImage: Cannot stream - fileSystem is null, url=${widget.url}',
      );
      setState(() {
        _hasError = true;
      });
      return;
    }

    logger.d('StreamImage: Starting stream load, url=${widget.url}, path=${widget.path}');
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      Stream<List<int>>? stream;

      // 优先使用 URL 加载（可以加载缩略图）
      if (_hasValidHttpUrl) {
        try {
          stream = await widget.fileSystem!.getUrlStream(widget.url!);
          logger.d('StreamImage: Using URL stream for ${widget.url}');
        } on Exception catch (e, st) {
          AppError.ignore(e, st, 'URL stream 失败，降级到 file stream');
          // URL 加载失败，继续尝试文件流
        }
      }

      // 如果 URL 加载失败或没有 URL，使用文件流
      if (stream == null) {
        if (widget.path == null) {
          throw Exception('无法加载图片：没有可用的 URL 或路径');
        }
        stream = await widget.fileSystem!.getFileStream(widget.path!);
        logger.d('StreamImage: Using file stream for ${widget.path}');
      }

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
        'StreamImage: Stream loaded ${bytes.length} bytes',
      );
      final imageData = Uint8List.fromList(bytes);

      // 添加到缓存
      if (_cacheKey.isNotEmpty) {
        // 如果缓存满了，清除一半
        if (StreamImage._memoryCache.length >= StreamImage._maxCacheSize) {
          final keysToRemove = StreamImage._memoryCache.keys
              .take(StreamImage._maxCacheSize ~/ 2)
              .toList();
          for (final key in keysToRemove) {
            StreamImage._memoryCache.remove(key);
          }
        }
        StreamImage._memoryCache[_cacheKey] = imageData;
      }

      if (mounted) {
        setState(() {
          _imageBytes = imageData;
          _isLoading = false;
        });
      }
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'loadImageViaStream');
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
    // 如果使用流式加载（iOS/macOS HTTPS、file:// URL、forceStream）
    if (_shouldUseStream) {
      return _buildStreamImage();
    }

    // 优先使用 HTTP URL（非 iOS/macOS HTTPS 或无 fileSystem）
    if (_hasValidHttpUrl) {
      return CachedNetworkImage(
        imageUrl: widget.url!,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        placeholder: (_, _) => widget.placeholder ?? _buildPlaceholder(),
        errorWidget: (_, _, _) => widget.errorWidget ?? _buildError(),
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
          errorBuilder: (_, _, _) => widget.errorWidget ?? _buildError(),
        );
      }
    }

    // 默认使用流式加载
    return _buildStreamImage();
  }

  /// 构建流式加载的图片组件
  Widget _buildStreamImage() {
    // 显示加载中
    if (_isLoading) {
      return widget.placeholder ?? _buildPlaceholder();
    }

    // 显示错误
    if (_hasError || _imageBytes == null) {
      return widget.errorWidget ?? _buildError();
    }

    // 如果启用缩放，使用 PhotoView
    if (widget.enableZoom) {
      return PhotoView(
        imageProvider: MemoryImage(_imageBytes!),
        minScale: widget.minScale ?? PhotoViewComputedScale.contained,
        maxScale: widget.maxScale ?? PhotoViewComputedScale.covered * 3,
        initialScale: widget.initialScale ?? PhotoViewComputedScale.contained,
        backgroundDecoration: BoxDecoration(
          color: widget.backgroundColor ?? Colors.black,
        ),
        loadingBuilder: (context, event) => widget.placeholder ?? _buildPlaceholder(),
        errorBuilder: (context, error, stackTrace) => widget.errorWidget ?? _buildError(),
      );
    }

    // 显示流式加载的图片
    return Image.memory(
      _imageBytes!,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      errorBuilder: (_, _, _) => widget.errorWidget ?? _buildError(),
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
  Widget build(BuildContext context) => StreamImage(
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
