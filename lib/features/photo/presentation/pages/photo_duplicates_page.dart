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
  bool _isFindingSimilar = false;
  String? _errorMessage;

  // 重复照片数据 - 基于文件名+大小的快速检测
  Map<String, List<PhotoEntity>> _nameSizeDuplicates = {};
  ({int duplicateGroups, int totalDuplicatePhotos})? _nameSizeStats;

  // 重复照片数据 - 基于哈希的深度检测
  Map<String, List<PhotoEntity>> _hashDuplicates = {};
  ({int fileHashDuplicates, int perceptualHashDuplicates, int totalDuplicatePhotos})? _hashStats;

  // 相似照片数据 - 基于 pHash 汉明距离
  List<List<PhotoEntity>> _similarGroups = [];

  // 哈希计算状态
  ({int total, int hashed, int pending, int failed})? _hashCalcStats;

  // 相似照片查找进度
  ({int processed, int total})? _similarProgress;

  // 选中的照片（用于删除）
  final Set<String> _selectedPhotos = {}; // 存储 uniqueKey

  // 扫描进度
  HashProgress? _scanProgress;
  StreamSubscription<HashProgress>? _progressSubscription;

  // 当前显示模式: 0=快速检测, 1=完全相同, 2=视觉相似
  int _currentMode = 0;

  // 相似度阈值（汉明距离）
  int _similarityThreshold = 8;

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

      // 优先加载快速检测结果（基于文件名+大小）
      final nameSizeStats = await _db.getNameSizeDuplicateStats();
      final nameSizeDups = await _db.getPotentialDuplicatesByNameAndSize();

      // 同时加载哈希检测结果（跨数据源）
      final hashStats = await _db.getDuplicateStats();
      final hashDups = await _db.getDuplicatesByFileHash(crossSource: true);

      // 加载哈希计算状态
      final hashCalcStats = await _db.getHashStats();

      setState(() {
        _nameSizeStats = nameSizeStats;
        _nameSizeDuplicates = nameSizeDups;
        _hashStats = hashStats;
        _hashDuplicates = hashDups;
        _hashCalcStats = hashCalcStats;
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

  Future<void> _findSimilarPhotos() async {
    setState(() {
      _isFindingSimilar = true;
      _similarProgress = null;
    });

    try {
      final groups = await _hashService.findSimilarPhotos(
        threshold: _similarityThreshold,
        onProgress: (processed, total) {
          setState(() {
            _similarProgress = (processed: processed, total: total);
          });
        },
      );

      setState(() {
        _similarGroups = groups;
        _isFindingSimilar = false;
        _similarProgress = null;
      });
    } on Exception catch (e) {
      setState(() {
        _errorMessage = '查找相似照片失败: $e';
        _isFindingSimilar = false;
        _similarProgress = null;
      });
    }
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

        // 模式切换选项卡
        SliverToBoxAdapter(child: _buildModeTabBar(isDark)),

        // 统计信息卡片
        SliverToBoxAdapter(child: _buildStatsCard(isDark)),

        // 相似照片查找进度
        if (_currentMode == 2 && _isFindingSimilar)
          SliverToBoxAdapter(child: _buildFindingSimilarCard(isDark)),

        // 根据模式显示不同内容
        ..._buildContentByMode(isDark),
      ],
    );
  }

  List<Widget> _buildContentByMode(bool isDark) {
    switch (_currentMode) {
      case 0: // 快速检测
        if (_nameSizeDuplicates.isEmpty) {
          return [SliverFillRemaining(child: _buildEmptyState(isDark))];
        }
        return [
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final entry = _nameSizeDuplicates.entries.elementAt(index);
                return _buildDuplicateGroup(entry.key, entry.value, isDark);
              },
              childCount: _nameSizeDuplicates.length,
            ),
          ),
        ];

      case 1: // 精确匹配（MD5）
        if (_hashDuplicates.isEmpty) {
          return [SliverFillRemaining(child: _buildEmptyState(isDark))];
        }
        return [
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final entry = _hashDuplicates.entries.elementAt(index);
                return _buildDuplicateGroup(entry.key, entry.value, isDark);
              },
              childCount: _hashDuplicates.length,
            ),
          ),
        ];

      case 2: // 视觉相似
        if (_isFindingSimilar) {
          return [const SliverToBoxAdapter(child: SizedBox.shrink())];
        }
        if (_similarGroups.isEmpty) {
          return [SliverFillRemaining(child: _buildEmptyState(isDark))];
        }
        return [
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final group = _similarGroups[index];
                return _buildSimilarGroup(index, group, isDark);
              },
              childCount: _similarGroups.length,
            ),
          ),
        ];

      default:
        return [SliverFillRemaining(child: _buildEmptyState(isDark))];
    }
  }

  Widget _buildFindingSimilarCard(bool isDark) {
    final progress = _similarProgress;
    final hasProgress = progress != null && progress.total > 0;

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
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '正在分析照片相似度...',
                    style: context.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (hasProgress) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress.processed / progress.total,
              ),
              const SizedBox(height: 8),
              Text(
                '已分析 ${progress.processed} / ${progress.total} 个分组',
                style: context.textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSimilarGroup(int index, List<PhotoEntity> photos, bool isDark) {
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
                    color: Colors.purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${photos.length} 张相似',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
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
                final photoIndex = entry.key;
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
                      // 第一张标记
                      if (photoIndex == 0)
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
                      // 文件大小
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
          // 文件路径
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

  /// 模式切换选项卡
  Widget _buildModeTabBar(bool isDark) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceElevated : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildModeTab(
              title: '快速',
              subtitle: '名称+大小',
              isSelected: _currentMode == 0,
              count: _nameSizeStats?.duplicateGroups ?? 0,
              isDark: isDark,
              onTap: () => setState(() => _currentMode = 0),
            ),
          ),
          Expanded(
            child: _buildModeTab(
              title: '精确',
              subtitle: 'MD5哈希',
              isSelected: _currentMode == 1,
              count: _hashStats?.fileHashDuplicates ?? 0,
              isDark: isDark,
              onTap: () => setState(() => _currentMode = 1),
            ),
          ),
          Expanded(
            child: _buildModeTab(
              title: '相似',
              subtitle: '视觉匹配',
              isSelected: _currentMode == 2,
              count: _similarGroups.length,
              isDark: isDark,
              onTap: () {
                setState(() => _currentMode = 2);
                // 如果还没有查找过相似照片，自动开始查找
                if (_similarGroups.isEmpty && !_isFindingSimilar) {
                  _findSimilarPhotos();
                }
              },
            ),
          ),
        ],
      ),
    );

  Widget _buildModeTab({
    required String title,
    required String subtitle,
    required bool isSelected,
    required int count,
    required bool isDark,
    required VoidCallback onTap,
  }) => GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppColors.darkSurface : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? AppColors.primary
                        : (isDark ? Colors.grey[400] : Colors.grey[600]),
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : (isDark ? Colors.grey[700] : Colors.grey[300]),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? AppColors.primary
                            : (isDark ? Colors.grey[400] : Colors.grey[600]),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey[500] : Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );

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
    final calcStats = _hashCalcStats;
    final needsScan = (calcStats?.pending ?? 0) > 0 || (calcStats?.failed ?? 0) > 0;

    // 根据当前模式显示对应的统计
    if (_currentMode == 1) {
      // 精确匹配模式
      final stats = _hashStats;
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: isDark ? AppColors.darkSurfaceElevated : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                ],
              ),
              // 哈希计算状态
              if (calcStats != null) ...[
                const SizedBox(height: 12),
                _buildHashStatusHint(calcStats, needsScan, isDark),
              ],
            ],
          ),
        ),
      );
    } else if (_currentMode == 2) {
      // 视觉相似模式
      final totalSimilarPhotos = _similarGroups.fold(0, (sum, g) => sum + g.length);
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: isDark ? AppColors.darkSurfaceElevated : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildStatItem(
                    '相似组',
                    '${_similarGroups.length}',
                    Icons.compare_rounded,
                    isDark,
                  ),
                  const SizedBox(width: 24),
                  _buildStatItem(
                    '涉及照片',
                    '$totalSimilarPhotos',
                    Icons.photo_library_rounded,
                    isDark,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 相似度阈值设置
              Row(
                children: [
                  Text(
                    '相似度阈值: ',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      ),
                      child: Slider(
                        value: _similarityThreshold.toDouble(),
                        min: 1,
                        max: 15,
                        divisions: 14,
                        label: _getThresholdLabel(_similarityThreshold),
                        onChanged: (value) {
                          setState(() => _similarityThreshold = value.round());
                        },
                        onChangeEnd: (value) {
                          // 阈值变化后重新查找
                          _findSimilarPhotos();
                        },
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getThresholdColor(_similarityThreshold).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _getThresholdLabel(_similarityThreshold),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _getThresholdColor(_similarityThreshold),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Colors.purple),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '视觉相似检测可找出经过压缩、裁剪、调色后的相同照片。'
                        '阈值越低越严格，越高则匹配更宽松。',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 哈希计算状态
              if (calcStats != null && needsScan) ...[
                const SizedBox(height: 8),
                _buildHashStatusHint(calcStats, needsScan, isDark),
              ],
            ],
          ),
        ),
      );
    } else {
      final stats = _nameSizeStats;
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: isDark ? AppColors.darkSurfaceElevated : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildStatItem(
                    '重复组',
                    '${stats?.duplicateGroups ?? 0}',
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
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '快速检测基于相同的文件名和大小，可能存在误判。建议使用深度检测确认。',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
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

  Widget _buildHashStatusHint(
    ({int total, int hashed, int pending, int failed}) calcStats,
    bool needsScan,
    bool isDark,
  ) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: needsScan
            ? Colors.orange.withValues(alpha: 0.1)
            : Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            needsScan ? Icons.info_outline : Icons.check_circle_outline,
            size: 16,
            color: needsScan ? Colors.orange : Colors.green,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              needsScan
                  ? '已扫描 ${calcStats.hashed}/${calcStats.total} 张'
                      '${calcStats.pending > 0 ? '，待扫描 ${calcStats.pending}' : ''}'
                      '${calcStats.failed > 0 ? '，失败 ${calcStats.failed}' : ''}'
                      '\n点击右上角刷新按钮继续扫描'
                  : '全部 ${calcStats.total} 张照片已完成扫描',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );

  String _getThresholdLabel(int threshold) {
    if (threshold <= 3) return '严格';
    if (threshold <= 6) return '较严格';
    if (threshold <= 10) return '适中';
    return '宽松';
  }

  Color _getThresholdColor(int threshold) {
    if (threshold <= 3) return Colors.green;
    if (threshold <= 6) return Colors.blue;
    if (threshold <= 10) return Colors.orange;
    return Colors.red;
  }

  Widget _buildEmptyState(bool isDark) {
    final (title, subtitle) = switch (_currentMode) {
      0 => ('没有发现疑似重复', '快速检测未发现相同文件名和大小的照片'),
      1 => ('没有发现重复照片', '点击右上角刷新按钮扫描照片哈希值'),
      2 => ('没有发现相似照片', '尝试调高相似度阈值，或点击刷新按钮重新分析'),
      _ => ('没有数据', ''),
    };

    return Center(
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
            title,
            style: context.textTheme.titleMedium?.copyWith(
              color: isDark ? Colors.white : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: context.textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          if (_currentMode == 2) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _findSimilarPhotos,
              icon: const Icon(Icons.refresh),
              label: const Text('重新分析'),
            ),
          ],
        ],
      ),
    );
  }

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
                      // 数据源标识（跨数据源时显示）
                      if (_currentMode == 1 && photos.map((p) => p.sourceId).toSet().length > 1)
                        Positioned(
                          top: index == 0 ? 24 : 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              photo.sourceId.length > 8
                                  ? '${photo.sourceId.substring(0, 8)}...'
                                  : photo.sourceId,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
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
