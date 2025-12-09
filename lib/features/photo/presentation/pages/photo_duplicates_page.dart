import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/features/photo/data/services/photo_hash_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';

/// 重复照片管理页面
class PhotoDuplicatesPage extends ConsumerStatefulWidget {
  const PhotoDuplicatesPage({super.key});

  @override
  ConsumerState<PhotoDuplicatesPage> createState() => _PhotoDuplicatesPageState();
}

class _PhotoDuplicatesPageState extends ConsumerState<PhotoDuplicatesPage> {
  final PhotoDatabaseService _db = PhotoDatabaseService();
  final PhotoHashService _hashService = PhotoHashService();

  // 状态
  bool _isLoading = true;
  bool _isScanning = false;
  String? _errorMessage;

  // 重复照片数据
  Map<String, List<PhotoEntity>> _duplicateGroups = {};
  ({int fileHashDuplicates, int perceptualHashDuplicates, int totalDuplicatePhotos})? _stats;

  // 选中的照片（用于删除）
  final Set<String> _selectedPhotos = {}; // 存储 uniqueKey

  // 扫描进度
  HashProgress? _scanProgress;
  StreamSubscription<HashProgress>? _progressSubscription;

  @override
  void initState() {
    super.initState();
    _loadDuplicates();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadDuplicates() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _db.init();
      final stats = await _db.getDuplicateStats();
      final duplicates = await _db.getDuplicatesByFileHash();

      setState(() {
        _stats = stats;
        _duplicateGroups = duplicates;
        _isLoading = false;
      });
    } on Exception catch (e) {
      setState(() {
        _errorMessage = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _startScan() async {
    // 获取第一个可用的文件系统
    final connections = ref.read(activeConnectionsProvider);
    final connectedSources = connections.values
        .where((c) => c.status == SourceStatus.connected)
        .toList();

    if (connectedSources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先连接到 NAS')),
      );
      return;
    }

    setState(() {
      _isScanning = true;
      _scanProgress = null;
    });

    _progressSubscription = _hashService.progressStream.listen((progress) {
      setState(() => _scanProgress = progress);

      if (progress.status == HashStatus.completed ||
          progress.status == HashStatus.cancelled ||
          progress.status == HashStatus.error) {
        _loadDuplicates();
        setState(() => _isScanning = false);
      }
    });

    // 使用第一个连接的文件系统
    final fileSystem = connectedSources.first.adapter.fileSystem;
    await _hashService.processAllPhotos(fileSystem);
  }

  void _cancelScan() {
    _hashService.cancel();
  }

  void _togglePhotoSelection(PhotoEntity photo) {
    setState(() {
      if (_selectedPhotos.contains(photo.uniqueKey)) {
        _selectedPhotos.remove(photo.uniqueKey);
      } else {
        _selectedPhotos.add(photo.uniqueKey);
      }
    });
  }

  void _selectAllExceptFirst(List<PhotoEntity> photos) {
    setState(() {
      // 保留第一张（最新的），选中其他所有
      for (var i = 1; i < photos.length; i++) {
        _selectedPhotos.add(photos[i].uniqueKey);
      }
    });
  }

  void _clearSelection() {
    setState(_selectedPhotos.clear);
  }

  Future<void> _deleteSelected() async {
    if (_selectedPhotos.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${_selectedPhotos.length} 张照片吗？\n\n'
            '注意：此操作会从 NAS 中永久删除文件，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final connections = ref.read(activeConnectionsProvider);
      var deleted = 0;
      var failed = 0;

      for (final uniqueKey in _selectedPhotos.toList()) {
        // 解析 uniqueKey (sourceId_filePath)
        final parts = uniqueKey.split('_');
        if (parts.length < 2) continue;

        final sourceId = parts.first;
        final filePath = parts.sublist(1).join('_');

        final connection = connections[sourceId];
        if (connection == null) {
          failed++;
          continue;
        }

        try {
          // 从 NAS 删除文件
          await connection.adapter.fileSystem.delete(filePath);
          // 从数据库删除记录
          await _db.delete(sourceId, filePath);
          deleted++;
        } on Exception catch (e) {
          logger.w('删除失败: $filePath - $e');
          failed++;
        }
      }

      _selectedPhotos.clear();
      await _loadDuplicates();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已删除 $deleted 张照片${failed > 0 ? '，$failed 张失败' : ''}'),
          ),
        );
      }
    } on Exception catch (e) {
      setState(() {
        _errorMessage = '删除失败: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      appBar: AppBar(
        title: const Text('重复照片'),
        backgroundColor: isDark ? AppColors.darkSurface : null,
        actions: [
          if (_selectedPhotos.isNotEmpty) ...[
            TextButton(
              onPressed: _clearSelection,
              child: Text('取消选择 (${_selectedPhotos.length})'),
            ),
            IconButton(
              onPressed: _deleteSelected,
              icon: const Icon(Icons.delete_rounded, color: Colors.red),
              tooltip: '删除选中',
            ),
          ],
          if (!_isScanning)
            IconButton(
              onPressed: _startScan,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '扫描哈希',
            ),
        ],
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: TextStyle(color: Colors.red[300])),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDuplicates,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        // 扫描进度卡片
        if (_isScanning || _scanProgress != null)
          SliverToBoxAdapter(child: _buildScanProgressCard(isDark)),

        // 统计信息卡片
        SliverToBoxAdapter(child: _buildStatsCard(isDark)),

        // 重复照片组列表
        if (_duplicateGroups.isEmpty)
          SliverFillRemaining(child: _buildEmptyState(isDark))
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final entry = _duplicateGroups.entries.elementAt(index);
                return _buildDuplicateGroup(entry.key, entry.value, isDark);
              },
              childCount: _duplicateGroups.length,
            ),
          ),
      ],
    );
  }

  Widget _buildScanProgressCard(bool isDark) {
    final progress = _scanProgress;

    return Card(
      margin: const EdgeInsets.all(16),
      color: isDark ? AppColors.darkSurfaceElevated : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_isScanning)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    progress?.status == HashStatus.completed
                        ? Icons.check_circle
                        : progress?.status == HashStatus.error
                            ? Icons.error
                            : Icons.cancel,
                    color: progress?.status == HashStatus.completed
                        ? Colors.green
                        : progress?.status == HashStatus.error
                            ? Colors.red
                            : Colors.orange,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isScanning
                        ? '正在扫描...'
                        : progress?.status == HashStatus.completed
                            ? '扫描完成'
                            : progress?.status == HashStatus.cancelled
                                ? '已取消'
                                : '扫描出错',
                    style: context.textTheme.titleMedium,
                  ),
                ),
                if (_isScanning)
                  TextButton(
                    onPressed: _cancelScan,
                    child: const Text('取消'),
                  ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress.progress),
              const SizedBox(height: 8),
              Text(
                '已处理 ${progress.processed} / ${progress.total} 张'
                '${progress.failed > 0 ? '，失败 ${progress.failed}' : ''}',
                style: context.textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              if (progress.currentFile.isNotEmpty)
                Text(
                  progress.currentFile,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.grey[500] : Colors.grey[500],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(bool isDark) {
    final stats = _stats;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDark ? AppColors.darkSurfaceElevated : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _buildStatItem(
              '重复组',
              '${stats?.fileHashDuplicates ?? 0}',
              Icons.collections_rounded,
              isDark,
            ),
            const SizedBox(width: 24),
            _buildStatItem(
              '涉及照片',
              '${stats?.totalDuplicatePhotos ?? 0}',
              Icons.photo_library_rounded,
              isDark,
            ),
            const SizedBox(width: 24),
            _buildStatItem(
              '相似组',
              '${stats?.perceptualHashDuplicates ?? 0}',
              Icons.compare_rounded,
              isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, bool isDark) =>
      Expanded(
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : null,
              ),
            ),
            Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      );

  Widget _buildEmptyState(bool isDark) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 64,
              color: Colors.green[300],
            ),
            const SizedBox(height: 16),
            Text(
              '没有发现重复照片',
              style: context.textTheme.titleMedium?.copyWith(
                color: isDark ? Colors.white : null,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右上角刷新按钮扫描照片哈希值',
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      );

  Widget _buildDuplicateGroup(
    String hash,
    List<PhotoEntity> photos,
    bool isDark,
  ) {
    final connections = ref.watch(activeConnectionsProvider);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDark ? AppColors.darkSurfaceElevated : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 组头部
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${photos.length} 张相同',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _selectAllExceptFirst(photos),
                  icon: const Icon(Icons.select_all, size: 18),
                  label: const Text('选择其他'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
          ),
          // 照片网格
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: photos.asMap().entries.map((entry) {
                final index = entry.key;
                final photo = entry.value;
                final isSelected = _selectedPhotos.contains(photo.uniqueKey);
                final connection = connections[photo.sourceId];
                final fileSystem = connection?.adapter.fileSystem;

                return GestureDetector(
                  onTap: () => _togglePhotoSelection(photo),
                  child: Stack(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected
                              ? Border.all(color: Colors.red, width: 3)
                              : null,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: StreamImage(
                            url: photo.thumbnailUrl,
                            path: photo.filePath,
                            fileSystem: fileSystem,
                            placeholder: Container(
                              color: isDark ? Colors.grey[800] : Colors.grey[200],
                              child: const Icon(Icons.photo),
                            ),
                            errorWidget: Container(
                              color: isDark ? Colors.grey[800] : Colors.grey[200],
                              child: const Icon(Icons.broken_image),
                            ),
                            cacheKey: photo.filePath,
                          ),
                        ),
                      ),
                      // 第一张标记为"保留"
                      if (index == 0)
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '推荐保留',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      // 选中标记
                      if (isSelected)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      // 文件信息
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.7),
                                Colors.transparent,
                              ],
                            ),
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(8),
                            ),
                          ),
                          child: Text(
                            photo.displaySize,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          // 文件路径信息
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: photos.map((photo) {
                final isSelected = _selectedPhotos.contains(photo.uniqueKey);
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                        size: 16,
                        color: isSelected ? Colors.red : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          photo.filePath,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                            decoration: isSelected ? TextDecoration.lineThrough : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
