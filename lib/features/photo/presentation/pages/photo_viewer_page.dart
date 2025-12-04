import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:my_nas/core/utils/platform_capabilities.dart';
import 'package:my_nas/features/photo/data/services/photo_save_service.dart';
import 'package:my_nas/features/photo/domain/entities/photo_item.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';

/// 照片 URL 获取回调
typedef PhotoUrlGetter = Future<String?> Function(String path, String sourceId);

/// 文件系统获取回调
typedef FileSystemGetter = NasFileSystem? Function(String sourceId);

/// 照片查看器页面
class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({
    super.key,
    required this.photos,
    required this.initialIndex,
    this.getPhotoUrl,
    this.getFileSystem,
  });

  final List<PhotoItem> photos;
  final int initialIndex;
  final PhotoUrlGetter? getPhotoUrl;
  final FileSystemGetter? getFileSystem;

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late int _currentIndex;
  bool _showOverlay = true;
  late AnimationController _overlayController;
  late Animation<double> _overlayAnimation;
  Timer? _autoHideTimer;

  /// 自动隐藏延迟（秒）
  static const _autoHideDelay = Duration(seconds: 3);

  /// 缓存已加载的原图 URL
  final Map<String, String> _loadedUrls = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);

    _overlayController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: 1.0,
    );
    _overlayAnimation = CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeInOut,
    );

    // 设置沉浸模式
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // 初始化当前照片的 URL（如果已有）
    final currentPhoto = widget.photos[_currentIndex];
    if (currentPhoto.url.isNotEmpty) {
      _loadedUrls[currentPhoto.path] = currentPhoto.url;
    }

    // 启动自动隐藏定时器
    _startAutoHideTimer();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _overlayController.dispose();
    _autoHideTimer?.cancel();
    // 恢复系统 UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _startAutoHideTimer() {
    _autoHideTimer?.cancel();
    if (_showOverlay) {
      _autoHideTimer = Timer(_autoHideDelay, () {
        if (mounted && _showOverlay) {
          _hideOverlay();
        }
      });
    }
  }

  void _showOverlayWithTimer() {
    setState(() {
      _showOverlay = true;
      _overlayController.forward();
    });
    _startAutoHideTimer();
  }

  void _hideOverlay() {
    setState(() {
      _showOverlay = false;
      _overlayController.reverse();
    });
    _autoHideTimer?.cancel();
  }

  void _toggleOverlay() {
    if (_showOverlay) {
      _hideOverlay();
    } else {
      _showOverlayWithTimer();
    }
  }

  void _goToNext() {
    if (_currentIndex < widget.photos.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToPrevious() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// 加载照片原图 URL
  Future<String?> _loadPhotoUrl(int index) async {
    final photo = widget.photos[index];

    // 如果已缓存，直接返回
    if (_loadedUrls.containsKey(photo.path)) {
      return _loadedUrls[photo.path];
    }

    // 如果照片已有 URL 且不为空，缓存并返回
    if (photo.url.isNotEmpty) {
      _loadedUrls[photo.path] = photo.url;
      return photo.url;
    }

    // 尝试通过回调获取原图 URL（使用 PhotoItem 中的 sourceId）
    if (widget.getPhotoUrl != null && photo.sourceId.isNotEmpty) {
      final url = await widget.getPhotoUrl!(photo.path, photo.sourceId);
      if (url != null && url.isNotEmpty) {
        _loadedUrls[photo.path] = url;
        if (mounted) setState(() {});
        return url;
      }
    }

    // 如果都失败，使用缩略图
    return photo.thumbnailUrl;
  }

  /// 预加载照片 URL
  void _preloadPhotoUrl(int index) {
    _loadPhotoUrl(index);
    // 预加载前后各一张
    if (index > 0) _loadPhotoUrl(index - 1);
    if (index < widget.photos.length - 1) _loadPhotoUrl(index + 1);
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_currentIndex];
    final isDesktop = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleOverlay,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // 照片查看器
            PageView.builder(
              controller: _pageController,
              itemCount: widget.photos.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
                // 预加载当前页的原图 URL
                _preloadPhotoUrl(index);
                // 翻页时重置自动隐藏定时器
                if (_showOverlay) {
                  _startAutoHideTimer();
                }
              },
              itemBuilder: (context, index) {
                final item = widget.photos[index];
                final cachedUrl = _loadedUrls[item.path];
                final fileSystem = widget.getFileSystem?.call(item.sourceId);
                return _PhotoPage(
                  photo: item,
                  cachedUrl: cachedUrl,
                  onLoadUrl: () => _loadPhotoUrl(index),
                  fileSystem: fileSystem,
                );
              },
            ),

            // 顶部返回按钮（浮动）
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_showOverlay,
                child: FadeTransition(
                  opacity: _overlayAnimation,
                  child: _buildTopBar(context, photo),
                ),
              ),
            ),

            // 底部操作栏（浮动）
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !_showOverlay,
                child: FadeTransition(
                  opacity: _overlayAnimation,
                  child: _buildBottomBar(context, photo),
                ),
              ),
            ),

            // 左右导航按钮（桌面端）
            if (isDesktop && _showOverlay) ...[
              // 上一张
              if (_currentIndex > 0)
                Positioned(
                  left: 16,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _NavButton(
                      icon: Icons.arrow_back_ios_rounded,
                      onTap: _goToPrevious,
                    ),
                  ),
                ),
              // 下一张
              if (_currentIndex < widget.photos.length - 1)
                Positioned(
                  right: 16,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _NavButton(
                      icon: Icons.arrow_forward_ios_rounded,
                      onTap: _goToNext,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, PhotoItem photo) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black54,
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              // 返回按钮
              IconButton(
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white,
                  size: 32,
                ),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: '返回',
              ),
              // 页码指示器（居中显示）
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_currentIndex + 1} / ${widget.photos.length}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      photo.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              // 占位，保持标题居中
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, PhotoItem photo) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black87,
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 照片信息
            if (photo.modifiedAt != null || photo.size > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 日期
                    if (photo.modifiedAt != null) ...[
                      Icon(
                        Icons.calendar_today_rounded,
                        color: Colors.white.withValues(alpha: 0.7),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('yyyy-MM-dd HH:mm').format(photo.modifiedAt!),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                      if (photo.size > 0) const SizedBox(width: 16),
                    ],
                    // 文件大小（仅当 size > 0 时显示）
                    if (photo.size > 0) ...[
                      Icon(
                        Icons.insert_drive_file_outlined,
                        color: Colors.white.withValues(alpha: 0.7),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        photo.displaySize,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            // 操作按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 详细信息
                  _ActionButton(
                    icon: Icons.info_outline,
                    label: '信息',
                    onTap: () {
                      _startAutoHideTimer();
                      _showPhotoInfo(context, photo);
                    },
                  ),
                  // 收藏
                  _ActionButton(
                    icon: Icons.favorite_border,
                    label: '收藏',
                    onTap: () {
                      _startAutoHideTimer();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('收藏功能开发中'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                  // 下载（所有平台都支持，桌面端用文件选择器，移动端保存到相册）
                  _ActionButton(
                    icon: Icons.download_outlined,
                    label: PlatformCapabilities.isMobile ? '保存' : '下载',
                    onTap: () {
                      _startAutoHideTimer();
                      _downloadPhoto(context, photo);
                    },
                  ),
                  // 分享（仅在支持分享的平台显示）
                  if (PlatformCapabilities.canShare)
                    _ActionButton(
                      icon: Icons.share_outlined,
                      label: '分享',
                      onTap: () {
                        _startAutoHideTimer();
                        _sharePhoto(context, photo);
                      },
                    ),
                  // 删除
                  _ActionButton(
                    icon: Icons.delete_outline,
                    label: '删除',
                    onTap: () {
                      _startAutoHideTimer();
                      _confirmDelete(context, photo);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPhotoInfo(BuildContext context, PhotoItem photo) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.white),
                  const SizedBox(width: 12),
                  const Text(
                    '照片信息',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _InfoRow(label: '文件名', value: photo.name),
              _InfoRow(label: '路径', value: photo.path),
              if (photo.size > 0)
                _InfoRow(label: '大小', value: photo.displaySize),
              if (photo.displayResolution != null)
                _InfoRow(label: '分辨率', value: photo.displayResolution!),
              if (photo.modifiedAt != null)
                _InfoRow(
                  label: '修改时间',
                  value: DateFormat('yyyy-MM-dd HH:mm:ss').format(photo.modifiedAt!),
                ),
              if (photo.takenAt != null)
                _InfoRow(
                  label: '拍摄时间',
                  value: DateFormat('yyyy-MM-dd HH:mm:ss').format(photo.takenAt!),
                ),
              if (photo.cameraInfo != null)
                _InfoRow(label: '相机', value: photo.cameraInfo!),
              if (photo.hasLocation)
                _InfoRow(
                  label: '位置',
                  value: '${photo.latitude?.toStringAsFixed(6)}, ${photo.longitude?.toStringAsFixed(6)}',
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 下载照片
  Future<void> _downloadPhoto(BuildContext context, PhotoItem photo) async {
    // 获取当前照片的 URL
    final url = _loadedUrls[photo.path] ?? photo.url;
    if (url.isEmpty) {
      _showErrorSnackBar(context, '无法获取照片地址');
      return;
    }

    // 移动端需要先请求权限
    final saveService = PhotoSaveService.instance;
    if (saveService.canSaveToGallery) {
      final hasPermission = await saveService.requestGalleryPermission();
      if (!hasPermission) {
        if (!context.mounted) return;
        _showErrorSnackBar(context, '需要相册访问权限才能保存照片');
        return;
      }
    }

    if (!context.mounted) return;

    // 创建取消令牌
    final cancelToken = CancelToken();
    final progressNotifier = ValueNotifier<double>(0);

    // 显示下载进度对话框
    final dialogCompleter = Completer<void>();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: Colors.grey[900],
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: progressNotifier,
                builder: (_, progress, __) => Column(
                  children: [
                    CircularProgressIndicator(
                      value: progress > 0 ? progress : null,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      progress > 0
                          ? '${saveService.isMobile ? "保存中" : "下载中"} ${(progress * 100).toInt()}%'
                          : '正在连接...',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  // 取消下载
                  cancelToken.cancel('用户取消');
                  if (!dialogCompleter.isCompleted) {
                    dialogCompleter.complete();
                  }
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );

    // 执行下载
    final result = await saveService.downloadPhoto(
      url: url,
      fileName: photo.name,
      cancelToken: cancelToken,
      onProgress: (progress) {
        if (!cancelToken.isCancelled) {
          progressNotifier.value = progress;
        }
      },
    );

    // 关闭进度对话框（如果还没关闭）
    if (context.mounted && !dialogCompleter.isCompleted) {
      dialogCompleter.complete();
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }

    // 显示结果（取消时不显示）
    if (!context.mounted || result.isCancelled) return;

    if (result.isSuccess) {
      _showSuccessSnackBar(context, result.message);
    } else if (result.isFailure) {
      _showErrorSnackBar(context, result.message);
    }
  }

  /// 分享照片
  Future<void> _sharePhoto(BuildContext context, PhotoItem photo) async {
    final url = _loadedUrls[photo.path] ?? photo.url;

    if (url.isEmpty) {
      _showErrorSnackBar(context, '无法获取照片地址');
      return;
    }

    // 检查分享功能是否可用
    final saveService = PhotoSaveService.instance;
    if (!saveService.canShare) {
      _showErrorSnackBar(context, '当前平台不支持分享功能');
      return;
    }

    // 在桌面端，提供选择：分享文件或复制链接
    if (saveService.isDesktop) {
      _showShareOptionsDialog(context, photo, url);
      return;
    }

    // 移动端直接使用系统分享
    final cancelToken = CancelToken();
    final progressNotifier = ValueNotifier<double>(0);
    final dialogCompleter = Completer<void>();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: Colors.grey[900],
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: progressNotifier,
                builder: (_, progress, __) => Column(
                  children: [
                    CircularProgressIndicator(
                      value: progress > 0 ? progress : null,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      progress > 0
                          ? '准备分享 ${(progress * 100).toInt()}%'
                          : '正在准备...',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  // 取消下载
                  cancelToken.cancel('用户取消');
                  if (!dialogCompleter.isCompleted) {
                    dialogCompleter.complete();
                  }
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );

    // 执行分享
    final result = await saveService.sharePhoto(
      url: url,
      fileName: photo.name,
      cancelToken: cancelToken,
      onProgress: (progress) {
        if (!cancelToken.isCancelled) {
          progressNotifier.value = progress;
        }
      },
    );

    // 关闭进度对话框（如果还没关闭）
    if (context.mounted && !dialogCompleter.isCompleted) {
      dialogCompleter.complete();
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }

    // 显示结果（取消时不显示）
    if (!context.mounted || result.isCancelled) return;

    if (result.isFailure) {
      _showErrorSnackBar(context, result.error ?? '分享失败');
    }
  }

  /// 显示桌面端分享选项对话框
  void _showShareOptionsDialog(BuildContext context, PhotoItem photo, String url) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.share_outlined, color: Colors.white),
                  const SizedBox(width: 12),
                  const Text(
                    '分享照片',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // 复制链接
              _ShareOptionTile(
                icon: Icons.link,
                title: '复制链接',
                subtitle: '将照片链接复制到剪贴板',
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: url));
                  _showSuccessSnackBar(context, '链接已复制');
                },
              ),
              const Divider(color: Colors.white24),
              // 分享文件
              _ShareOptionTile(
                icon: Icons.file_present_outlined,
                title: '分享文件',
                subtitle: '下载后使用系统分享功能',
                onTap: () async {
                  Navigator.pop(context);
                  await _sharePhotoFile(context, photo, url);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 分享照片文件（桌面端）
  Future<void> _sharePhotoFile(BuildContext context, PhotoItem photo, String url) async {
    final saveService = PhotoSaveService.instance;
    final cancelToken = CancelToken();
    final progressNotifier = ValueNotifier<double>(0);
    final dialogCompleter = Completer<void>();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: Colors.grey[900],
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: progressNotifier,
                builder: (_, progress, __) => Column(
                  children: [
                    CircularProgressIndicator(
                      value: progress > 0 ? progress : null,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      progress > 0
                          ? '准备分享 ${(progress * 100).toInt()}%'
                          : '正在准备...',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  cancelToken.cancel('用户取消');
                  if (!dialogCompleter.isCompleted) {
                    dialogCompleter.complete();
                  }
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );

    final result = await saveService.sharePhoto(
      url: url,
      fileName: photo.name,
      cancelToken: cancelToken,
      onProgress: (progress) {
        if (!cancelToken.isCancelled) {
          progressNotifier.value = progress;
        }
      },
    );

    // 关闭进度对话框（如果还没关闭）
    if (context.mounted && !dialogCompleter.isCompleted) {
      dialogCompleter.complete();
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }

    // 显示结果（取消时不显示）
    if (!context.mounted || result.isCancelled) return;

    if (result.isFailure) {
      _showErrorSnackBar(context, result.error ?? '分享失败');
    }
  }

  void _showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green[700],
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red[700],
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// 确认删除
  void _confirmDelete(BuildContext context, PhotoItem photo) {
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          '删除照片',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '确定要删除 "${photo.name}" 吗？\n此操作不可恢复。',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        // TODO: 实现实际删除功能
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('删除功能开发中'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    });
  }
}

class _PhotoPage extends StatefulWidget {
  const _PhotoPage({
    required this.photo,
    this.cachedUrl,
    this.onLoadUrl,
    this.fileSystem,
  });

  final PhotoItem photo;
  final String? cachedUrl;
  final Future<String?> Function()? onLoadUrl;
  final NasFileSystem? fileSystem;

  @override
  State<_PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<_PhotoPage> {
  final _transformController = TransformationController();
  String? _loadedUrl;
  bool _isLoading = false;
  bool _hasError = false;
  String? _errorMessage;



  /// 构建适合 URL 类型的图片组件
  /// 使用 StreamImage 统一处理所有类型的图片加载
  Widget _buildImageFromUrl({
    required String url,
    required BoxFit fit,
    Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder,
    Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
  }) {
    // 使用 StreamImage 统一处理
    // StreamImage 会自动处理 HTTP、file:// URL，以及在 iOS/macOS 上的流式加载
    return StreamImage(
      url: url,
      path: widget.photo.path,
      fileSystem: widget.fileSystem,
      fit: fit,
      placeholder: loadingBuilder != null
          ? Builder(
              builder: (context) => loadingBuilder(
                context,
                const SizedBox.shrink(),
                null,
              ),
            )
          : null,
      errorWidget: errorBuilder != null
          ? Builder(
              builder: (context) => errorBuilder(
                context,
                Exception('图片加载失败'),
                StackTrace.current,
              ),
            )
          : null,
      cacheKey: widget.photo.path,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadedUrl = widget.cachedUrl;
    // 如果没有原图 URL，则加载
    if (_loadedUrl == null || _loadedUrl!.isEmpty) {
      // 检查 photo.url 是否有效（不是缩略图）
      if (widget.photo.url.isNotEmpty && widget.photo.url != widget.photo.thumbnailUrl) {
        _loadedUrl = widget.photo.url;
      } else {
        _loadUrl();
      }
    }
  }

  @override
  void didUpdateWidget(_PhotoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cachedUrl != oldWidget.cachedUrl && widget.cachedUrl != null) {
      setState(() {
        _loadedUrl = widget.cachedUrl;
        _hasError = false;
        _errorMessage = null;
      });
    }
  }

  Future<void> _loadUrl() async {
    if (_isLoading || widget.onLoadUrl == null) return;
    _isLoading = true;
    setState(() {
      _hasError = false;
      _errorMessage = null;
    });

    try {
      final url = await widget.onLoadUrl!();
      if (mounted && url != null && url.isNotEmpty) {
        setState(() {
          _loadedUrl = url;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
    _isLoading = false;
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 优先使用已加载的 URL，其次使用 photo.url
    final displayUrl = _loadedUrl ?? widget.photo.url;
    final hasThumbnail = widget.photo.thumbnailUrl != null && widget.photo.thumbnailUrl!.isNotEmpty;
    final hasDisplayUrl = displayUrl.isNotEmpty;
    // 检查是否有原图（不是缩略图）
    final hasOriginalImage = hasDisplayUrl && displayUrl != widget.photo.thumbnailUrl;

    return InteractiveViewer(
      transformationController: _transformController,
      minScale: 0.5,
      maxScale: 4.0,
      child: Center(
        child: _buildImageContent(displayUrl, hasDisplayUrl, hasThumbnail, hasOriginalImage),
      ),
    );
  }

  Widget _buildImageContent(String displayUrl, bool hasDisplayUrl, bool hasThumbnail, bool hasOriginalImage) {
    if (_hasError && !hasThumbnail && !hasOriginalImage) {
      return _buildErrorWidget(_errorMessage ?? '加载失败');
    }

    // 没有任何可用 URL
    if (!hasDisplayUrl && !hasThumbnail) {
      return _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : _buildErrorWidget('没有可用的图片');
    }

    // 有原图 URL，直接加载原图
    if (hasOriginalImage) {
      return _buildImageFromUrl(
        url: displayUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
          // 加载中显示进度指示器
          final progress = loadingProgress.expectedTotalBytes != null
              ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
              : null;
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  color: Colors.white,
                ),
                if (progress != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          debugPrint('PhotoViewer: Error loading image: $error');
          // 加载原图失败时尝试使用缩略图
          if (hasThumbnail) {
            return _buildImageFromUrl(
              url: widget.photo.thumbnailUrl!,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _buildErrorWidget('图片加载失败'),
            );
          }
          return _buildErrorWidget(error.toString());
        },
      );
    }

    // 没有原图，正在加载中，显示缩略图 + 加载指示器
    if (_isLoading && hasThumbnail) {
      return Stack(
        alignment: Alignment.center,
        children: [
          _buildImageFromUrl(
            url: widget.photo.thumbnailUrl!,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          ),
        ],
      );
    }

    // 只有缩略图
    if (hasThumbnail) {
      return _buildImageFromUrl(
        url: widget.photo.thumbnailUrl!,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        },
        errorBuilder: (_, error, __) => _buildErrorWidget(error.toString()),
      );
    }

    return _buildErrorWidget('没有可用的图片');
  }

  Widget _buildErrorWidget(String errorMessage) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.broken_image_outlined,
          size: 64,
          color: Colors.white.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 16),
        Text(
          '加载失败',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            errorMessage,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: _loadUrl,
          icon: const Icon(Icons.refresh, color: Colors.white70),
          label: const Text('重试', style: TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          width: 50,
          height: 50,
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分享选项瓦片（桌面端分享对话框使用）
class _ShareOptionTile extends StatelessWidget {
  const _ShareOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}
