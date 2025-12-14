import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/domain/entities/video_category_config.dart';
import 'package:my_nas/features/video/presentation/providers/video_category_settings_provider.dart';

/// 视频分类设置弹窗
///
/// 允许用户调整分类显示顺序、切换可见性、添加/移除类型分类
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
  bool _showGenrePicker = false;
  List<String>? _availableGenres;
  bool _loadingGenres = false;

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
                    onRemoveGenre: section.category == VideoHomeCategory.byGenre
                        ? () => ref
                            .read(videoCategorySettingsProvider.notifier)
                            .removeGenre(section.genreFilter!)
                        : null,
                  );
                },
              ),
            ),
            // 添加类型分类按钮
            const Divider(height: 1),
            _buildAddGenreSection(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildAddGenreSection(bool isDark) {
    if (_showGenrePicker) {
      return _buildGenrePicker(isDark);
    }

    return ListTile(
      leading: Container(
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
      title: const Text('添加类型分类'),
      subtitle: const Text('按电影/剧集类型添加分类'),
      trailing: const Icon(Icons.chevron_right),
      onTap: _loadGenresAndShowPicker,
    );
  }

  Widget _buildGenrePicker(bool isDark) {
    if (_loadingGenres) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final genres = _availableGenres ?? [];
    final settings = ref.watch(videoCategorySettingsProvider);
    final addedGenres =
        settings.genreSections.map((s) => s.genreFilter).toSet();

    if (genres.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.category_outlined,
              size: 48,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              '暂无可用类型',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _showGenrePicker = false),
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
                onPressed: () => setState(() => _showGenrePicker = false),
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 8),
              Text(
                '选择类型',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
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
              children: genres.map((genre) {
                final isAdded = addedGenres.contains(genre);
                return FilterChip(
                  label: Text(genre),
                  selected: isAdded,
                  onSelected: (selected) {
                    if (selected) {
                      ref
                          .read(videoCategorySettingsProvider.notifier)
                          .addGenre(genre);
                    } else {
                      ref
                          .read(videoCategorySettingsProvider.notifier)
                          .removeGenre(genre);
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

  Future<void> _loadGenresAndShowPicker() async {
    setState(() {
      _showGenrePicker = true;
      _loadingGenres = true;
    });

    try {
      final db = VideoDatabaseService();
      await db.init();
      final genres = await db.getAllGenres();
      if (mounted) {
        setState(() {
          _availableGenres = genres;
          _loadingGenres = false;
        });
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _availableGenres = [];
          _loadingGenres = false;
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
    this.onRemoveGenre,
  });

  final VideoCategorySectionConfig section;
  final bool isDark;
  final VoidCallback onToggle;
  final VoidCallback? onRemoveGenre;

  @override
  Widget build(BuildContext context) {
    final isGenre = section.category == VideoHomeCategory.byGenre;

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
        subtitle: isGenre
            ? Text(
                '类型分类',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[600] : Colors.grey[500],
                ),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isGenre && onRemoveGenre != null)
              IconButton(
                onPressed: onRemoveGenre,
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
      case VideoHomeCategory.byGenre:
        return Icons.category_rounded;
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
      case VideoHomeCategory.byGenre:
        return Colors.indigo;
    }
  }
}
