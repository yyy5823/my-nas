import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/photo/domain/entities/photo_item.dart';

/// 照片 URL 获取回调
typedef PhotoUrlGetter = Future<String?> Function(String path, String sourceId);

/// 获取照片 sourceId 回调
typedef SourceIdGetter = String Function(String photoPath);

/// 照片查看器页面
class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({
    super.key,
    required this.photos,
    required this.initialIndex,
    this.getPhotoUrl,
    this.getSourceId,
  });

  final List<PhotoItem> photos;
  final int initialIndex;
  final PhotoUrlGetter? getPhotoUrl;
  final SourceIdGetter? getSourceId;

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
  }

  @override
  void dispose() {
    _pageController.dispose();
    _overlayController.dispose();
    // 恢复系统 UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleOverlay() {
    setState(() {
      _showOverlay = !_showOverlay;
      if (_showOverlay) {
        _overlayController.forward();
      } else {
        _overlayController.reverse();
      }
    });
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

    // 尝试获取原图 URL
    if (widget.getPhotoUrl != null && widget.getSourceId != null) {
      final sourceId = widget.getSourceId!(photo.path);
      final url = await widget.getPhotoUrl!(photo.path, sourceId);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
              },
              itemBuilder: (context, index) {
                final item = widget.photos[index];
                final cachedUrl = _loadedUrls[item.path];
                return _PhotoPage(
                  photo: item,
                  cachedUrl: cachedUrl,
                  onLoadUrl: () => _loadPhotoUrl(index),
                );
              },
            ),

          // 顶部工具栏
          FadeTransition(
            opacity: _overlayAnimation,
            child: _buildTopBar(context, photo),
          ),

          // 底部信息栏
          FadeTransition(
            opacity: _overlayAnimation,
            child: _buildBottomBar(context, photo, isDark),
          ),

          // 左右导航按钮（桌面端）
          if (MediaQuery.of(context).size.width > 600 && _showOverlay) ...[
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              // 返回按钮
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              // 文件名
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      photo.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${_currentIndex + 1} / ${widget.photos.length}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // 更多操作
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                color: Colors.grey[900],
                onSelected: (value) {
                  switch (value) {
                    case 'info':
                      _showPhotoInfo(context, photo);
                    case 'share':
                      // TODO: 分享
                      break;
                    case 'download':
                      // TODO: 下载
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'info',
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.white, size: 20),
                        SizedBox(width: 12),
                        Text('详细信息', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [
                        Icon(Icons.share_outlined, color: Colors.white, size: 20),
                        SizedBox(width: 12),
                        Text('分享', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'download',
                    child: Row(
                      children: [
                        Icon(Icons.download_outlined, color: Colors.white, size: 20),
                        SizedBox(width: 12),
                        Text('下载', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, PhotoItem photo, bool isDark) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black54,
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 日期
                if (photo.modifiedAt != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_today_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          DateFormat('yyyy-MM-dd HH:mm').format(photo.modifiedAt!),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 12),
                // 文件大小
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    photo.displaySize,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
}

class _PhotoPage extends StatefulWidget {
  const _PhotoPage({
    required this.photo,
    this.cachedUrl,
    this.onLoadUrl,
  });

  final PhotoItem photo;
  final String? cachedUrl;
  final Future<String?> Function()? onLoadUrl;

  @override
  State<_PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<_PhotoPage> {
  final _transformController = TransformationController();
  String? _loadedUrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadedUrl = widget.cachedUrl;
    if (_loadedUrl == null || _loadedUrl!.isEmpty) {
      _loadUrl();
    }
  }

  @override
  void didUpdateWidget(_PhotoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cachedUrl != oldWidget.cachedUrl && widget.cachedUrl != null) {
      setState(() {
        _loadedUrl = widget.cachedUrl;
      });
    }
  }

  Future<void> _loadUrl() async {
    if (_isLoading || widget.onLoadUrl == null) return;
    _isLoading = true;
    final url = await widget.onLoadUrl!();
    if (mounted && url != null && url.isNotEmpty) {
      setState(() {
        _loadedUrl = url;
      });
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
    // 优先使用已加载的 URL，其次使用原有 URL，最后使用缩略图
    final displayUrl = _loadedUrl ?? widget.photo.url;
    final hasThumbnail = widget.photo.thumbnailUrl != null && widget.photo.thumbnailUrl!.isNotEmpty;
    final hasDisplayUrl = displayUrl.isNotEmpty;

    return InteractiveViewer(
      transformationController: _transformController,
      minScale: 0.5,
      maxScale: 4.0,
      onInteractionEnd: (details) {
        // 双击后缩放恢复
        if (_transformController.value.getMaxScaleOnAxis() < 1.1 &&
            _transformController.value.getMaxScaleOnAxis() > 0.9) {
          _transformController.value = Matrix4.identity();
        }
      },
      child: Center(
        child: hasDisplayUrl
            ? CachedNetworkImage(
                imageUrl: displayUrl,
                fit: BoxFit.contain,
                placeholder: (context, url) => hasThumbnail
                    ? CachedNetworkImage(
                        imageUrl: widget.photo.thumbnailUrl!,
                        fit: BoxFit.contain,
                      )
                    : const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                        ),
                      ),
                errorWidget: (context, url, error) => hasThumbnail
                    ? CachedNetworkImage(
                        imageUrl: widget.photo.thumbnailUrl!,
                        fit: BoxFit.contain,
                        errorWidget: (context, url, error) => _buildErrorWidget(),
                      )
                    : _buildErrorWidget(),
              )
            : hasThumbnail
                ? CachedNetworkImage(
                    imageUrl: widget.photo.thumbnailUrl!,
                    fit: BoxFit.contain,
                    errorWidget: (context, url, error) => _buildErrorWidget(),
                  )
                : _buildErrorWidget(),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.broken_image_outlined,
          size: 64,
          color: Colors.white.withOpacity(0.5),
        ),
        const SizedBox(height: 16),
        Text(
          '加载失败',
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
          ),
        ),
      ],
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
                color: Colors.white.withOpacity(0.6),
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
