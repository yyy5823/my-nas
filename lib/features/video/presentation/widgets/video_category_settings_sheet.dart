import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/domain/entities/video_category_config.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/providers/video_category_settings_provider.dart';

/// 视频分类设置弹窗
///
/// 允许用户调整分类显示顺序、切换可见性、添加/移除动态分类
class VideoCategorySettingsSheet extends ConsumerStatefulWidget {
  const VideoCategorySettingsSheet({super.key});

  /// 显示设置弹窗
  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => const VideoCategorySettingsSheet(),
      );

  @override
  ConsumerState<VideoCategorySettingsSheet> createState() =>
      _VideoCategorySettingsSheetState();
}

class _VideoCategorySettingsSheetState
    extends ConsumerState<VideoCategorySettingsSheet> {
  /// 当前选择的动态分类类型（用于显示选择器）
  VideoHomeCategory? _selectedDynamicCategory;

  /// 可用的筛选项
  List<String>? _availableFilters;
  bool _loadingFilters = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(videoCategorySettingsProvider);
    final sortedSections = settings.sortedSections;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, scrollController) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // 拖动指示器
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[700] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题栏
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '分类显示设置',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref
                        .read(videoCategorySettingsProvider.notifier)
                        .resetToDefaults(),
                    child: const Text('重置'),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 分类列表
            Expanded(
              child: ReorderableListView.builder(
                scrollController: scrollController,
                buildDefaultDragHandles: false, // 禁用默认的右侧拖动手柄
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: sortedSections.length,
                onReorder: (oldIndex, newIndex) {
                  ref
                      .read(videoCategorySettingsProvider.notifier)
                      .reorder(oldIndex, newIndex);
                },
                itemBuilder: (context, index) {
                  final section = sortedSections[index];
                  return _CategoryTile(
                    key: ValueKey(section.uniqueKey),
                    section: section,
                    isDark: isDark,
                    onToggle: () => ref
                        .read(videoCategorySettingsProvider.notifier)
                        .toggleVisibility(section.uniqueKey),
                    onRemove: section.category.isDynamic
                        ? () => ref
                            .read(videoCategorySettingsProvider.notifier)
                            .removeDynamicCategory(
                              section.category,
                              section.filter!,
                            )
                        : null,
                  );
                },
              ),
            ),
            // 添加动态分类按钮
            const Divider(height: 1),
            _buildAddDynamicCategorySection(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildAddDynamicCategorySection(bool isDark) {
    if (_selectedDynamicCategory != null) {
      return _buildFilterPicker(isDark);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '添加动态分类',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
        // 单项分类（需要选择具体项目）
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildCategoryTypeChip(
                isDark,
                VideoHomeCategory.byMovieGenre,
                Icons.movie_rounded,
                Colors.blue,
              ),
              _buildCategoryTypeChip(
                isDark,
                VideoHomeCategory.byMovieRegion,
                Icons.public_rounded,
                Colors.green,
              ),
              _buildCategoryTypeChip(
                isDark,
                VideoHomeCategory.byTvGenre,
                Icons.live_tv_rounded,
                Colors.orange,
              ),
              _buildCategoryTypeChip(
                isDark,
                VideoHomeCategory.byTvRegion,
                Icons.language_rounded,
                Colors.purple,
              ),
            ],
          ),
        ),
        // 浏览分类（卡片式入口）
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              Text(
                '分类入口',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Divider(
                  color: isDark ? Colors.grey[800] : Colors.grey[300],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildBrowseCategoryChip(
                isDark,
                VideoHomeCategory.browseMovieGenres,
                Icons.category_rounded,
                Colors.blue,
              ),
              _buildBrowseCategoryChip(
                isDark,
                VideoHomeCategory.browseMovieRegions,
                Icons.public_rounded,
                Colors.green,
              ),
              _buildBrowseCategoryChip(
                isDark,
                VideoHomeCategory.browseTvGenres,
                Icons.category_rounded,
                Colors.orange,
              ),
              _buildBrowseCategoryChip(
                isDark,
                VideoHomeCategory.browseTvRegions,
                Icons.language_rounded,
                Colors.purple,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBrowseCategoryChip(
    bool isDark,
    VideoHomeCategory category,
    IconData icon,
    Color color,
  ) {
    final settings = ref.watch(videoCategorySettingsProvider);
    final isAdded = settings.sections.any((s) => s.category == category);

    return FilterChip(
      avatar: Icon(icon, size: 18, color: isAdded ? Colors.white : color),
      label: Text(category.displayName),
      labelStyle: TextStyle(
        color: isAdded ? Colors.white : (isDark ? Colors.white : Colors.black87),
        fontSize: 13,
      ),
      selected: isAdded,
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      checkmarkColor: Colors.white,
      onSelected: (selected) {
        if (selected) {
          ref
              .read(videoCategorySettingsProvider.notifier)
              .addDynamicCategory(category, '');
        } else {
          ref
              .read(videoCategorySettingsProvider.notifier)
              .removeDynamicCategory(category, '');
        }
      },
    );
  }

  Widget _buildCategoryTypeChip(
    bool isDark,
    VideoHomeCategory category,
    IconData icon,
    Color color,
  ) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(category.displayName),
      labelStyle: TextStyle(
        color: isDark ? Colors.white : Colors.black87,
        fontSize: 13,
      ),
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      onPressed: () => _loadFiltersAndShowPicker(category),
    );
  }

  Widget _buildFilterPicker(bool isDark) {
    if (_loadingFilters) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final filters = _availableFilters ?? [];
    final settings = ref.watch(videoCategorySettingsProvider);
    final addedFilters =
        settings.getFiltersForCategory(_selectedDynamicCategory!);

    if (filters.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _selectedDynamicCategory!.isRegionCategory
                  ? Icons.public_outlined
                  : Icons.category_outlined,
              size: 48,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              _selectedDynamicCategory!.isRegionCategory
                  ? '暂无可用地区'
                  : '暂无可用类型',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() {
                _selectedDynamicCategory = null;
                _availableFilters = null;
              }),
              child: const Text('返回'),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() {
                  _selectedDynamicCategory = null;
                  _availableFilters = null;
                }),
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '选择${_selectedDynamicCategory!.displayName}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: filters.map((filter) {
                final isAdded = addedFilters.contains(filter);
                return FilterChip(
                  label: Text(filter),
                  selected: isAdded,
                  onSelected: (selected) {
                    if (selected) {
                      ref
                          .read(videoCategorySettingsProvider.notifier)
                          .addDynamicCategory(
                            _selectedDynamicCategory!,
                            filter,
                          );
                    } else {
                      ref
                          .read(videoCategorySettingsProvider.notifier)
                          .removeDynamicCategory(
                            _selectedDynamicCategory!,
                            filter,
                          );
                    }
                  },
                  selectedColor: AppColors.primary.withValues(alpha: 0.2),
                  checkmarkColor: AppColors.primary,
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _loadFiltersAndShowPicker(VideoHomeCategory category) async {
    setState(() {
      _selectedDynamicCategory = category;
      _loadingFilters = true;
      _availableFilters = null;
    });

    try {
      final db = VideoDatabaseService();
      await db.init();

      List<String> filters;

      switch (category) {
        case VideoHomeCategory.byMovieGenre:
          filters = await db.getAvailableGenres(category: MediaCategory.movie);
        case VideoHomeCategory.byMovieRegion:
          filters = await db.getAvailableCountries(category: MediaCategory.movie);
        case VideoHomeCategory.byTvGenre:
          filters = await db.getAvailableGenres(category: MediaCategory.tvShow);
        case VideoHomeCategory.byTvRegion:
          filters = await db.getAvailableCountries(category: MediaCategory.tvShow);
        default:
          filters = [];
      }

      if (mounted) {
        setState(() {
          _availableFilters = filters;
          _loadingFilters = false;
        });
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _availableFilters = [];
          _loadingFilters = false;
        });
      }
    }
  }
}

/// 分类项 Tile
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required super.key,
    required this.section,
    required this.isDark,
    required this.onToggle,
    this.onRemove,
  });

  final VideoCategorySectionConfig section;
  final bool isDark;
  final VoidCallback onToggle;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final isDynamic = section.category.isDynamic;

    return ColoredBox(
      color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖动手柄
            ReorderableDragStartListener(
              index: section.order,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.drag_handle,
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                ),
              ),
            ),
            // 分类图标
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _getCategoryColor(section.category).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getCategoryIcon(section.category),
                color: _getCategoryColor(section.category),
                size: 20,
              ),
            ),
          ],
        ),
        title: Text(
          section.displayName,
          style: TextStyle(
            color: section.visible
                ? (isDark ? Colors.white : Colors.black87)
                : (isDark ? Colors.grey[600] : Colors.grey[400]),
          ),
        ),
        subtitle: isDynamic && section.subtitle.isNotEmpty
            ? Text(
                section.subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[600] : Colors.grey[500],
                ),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isDynamic && onRemove != null)
              IconButton(
                onPressed: onRemove,
                icon: Icon(
                  Icons.remove_circle_outline,
                  color: Colors.red[400],
                  size: 20,
                ),
                tooltip: '移除',
              ),
            Switch.adaptive(
              value: section.visible,
              onChanged: (_) => onToggle(),
              thumbColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected) ? AppColors.primary : null),
              trackColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? AppColors.primary.withValues(alpha: 0.5)
                      : null),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getCategoryIcon(VideoHomeCategory category) {
    switch (category) {
      case VideoHomeCategory.heroBanner:
        return Icons.featured_play_list_rounded;
      case VideoHomeCategory.continueWatching:
        return Icons.play_circle_rounded;
      case VideoHomeCategory.recentlyAdded:
        return Icons.schedule_rounded;
      case VideoHomeCategory.movies:
        return Icons.movie_rounded;
      case VideoHomeCategory.tvShows:
        return Icons.live_tv_rounded;
      case VideoHomeCategory.movieCollections:
        return Icons.collections_bookmark_rounded;
      case VideoHomeCategory.topRated:
        return Icons.star_rounded;
      case VideoHomeCategory.unwatched:
        return Icons.visibility_off_rounded;
      case VideoHomeCategory.others:
        return Icons.video_file_rounded;
      case VideoHomeCategory.byMovieGenre:
      case VideoHomeCategory.browseMovieGenres:
        return Icons.category_rounded;
      case VideoHomeCategory.byMovieRegion:
      case VideoHomeCategory.browseMovieRegions:
        return Icons.public_rounded;
      case VideoHomeCategory.byTvGenre:
      case VideoHomeCategory.browseTvGenres:
        return Icons.category_rounded;
      case VideoHomeCategory.byTvRegion:
      case VideoHomeCategory.browseTvRegions:
        return Icons.language_rounded;
    }
  }

  Color _getCategoryColor(VideoHomeCategory category) {
    switch (category) {
      case VideoHomeCategory.heroBanner:
        return Colors.purple;
      case VideoHomeCategory.continueWatching:
        return Colors.orange;
      case VideoHomeCategory.recentlyAdded:
        return Colors.blue;
      case VideoHomeCategory.movies:
        return AppColors.primary;
      case VideoHomeCategory.tvShows:
        return AppColors.accent;
      case VideoHomeCategory.movieCollections:
        return Colors.purple;
      case VideoHomeCategory.topRated:
        return Colors.amber;
      case VideoHomeCategory.unwatched:
        return Colors.teal;
      case VideoHomeCategory.others:
        return Colors.grey;
      case VideoHomeCategory.byMovieGenre:
      case VideoHomeCategory.browseMovieGenres:
        return Colors.blue;
      case VideoHomeCategory.byMovieRegion:
      case VideoHomeCategory.browseMovieRegions:
        return Colors.green;
      case VideoHomeCategory.byTvGenre:
      case VideoHomeCategory.browseTvGenres:
        return Colors.orange;
      case VideoHomeCategory.byTvRegion:
      case VideoHomeCategory.browseTvRegions:
        return Colors.purple;
    }
  }
}
