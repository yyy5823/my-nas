import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/book/domain/entities/book_source.dart';
import 'package:my_nas/features/book/presentation/pages/online_book_reader_page.dart';
import 'package:my_nas/features/book/presentation/providers/book_search_provider.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_glass_container.dart';
import 'package:my_nas/app/theme/ui_style.dart';

/// 在线书籍详情页面
class OnlineBookDetailPage extends ConsumerStatefulWidget {
  const OnlineBookDetailPage({super.key, required this.book});

  final OnlineBook book;

  @override
  ConsumerState<OnlineBookDetailPage> createState() => _OnlineBookDetailPageState();
}

class _OnlineBookDetailPageState extends ConsumerState<OnlineBookDetailPage>
    with TabBarVisibilityMixin {
  List<OnlineChapter>? _chapters;
  bool _isLoadingChapters = false;
  String? _error;
  bool _isReversed = false;

  @override
  void initState() {
    super.initState();
    hideTabBar();
    _loadChapters();
  }

  Future<void> _loadChapters() async {
    setState(() {
      _isLoadingChapters = true;
      _error = null;
    });

    try {
      final contentService = ref.read(bookContentServiceProvider);
      final chapters = await contentService.getChapterList(
        widget.book.source,
        widget.book.bookUrl,
      );
      if (mounted) {
        setState(() {
          _chapters = chapters;
          _isLoadingChapters = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoadingChapters = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uiStyle = ref.watch(uiStyleProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: CustomScrollView(
        slivers: [
          // AppBar
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeader(isDark),
            ),
            backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          ),
          // 书籍信息
          SliverToBoxAdapter(
            child: _buildBookInfo(isDark, uiStyle),
          ),
          // 目录标题
          SliverToBoxAdapter(
            child: _buildChapterHeader(isDark),
          ),
          // 目录列表
          _buildChapterList(isDark, uiStyle),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 背景
        if (widget.book.coverUrl != null && widget.book.coverUrl!.isNotEmpty)
          CachedNetworkImage(
            imageUrl: widget.book.coverUrl!,
            fit: BoxFit.cover,
            color: Colors.black54,
            colorBlendMode: BlendMode.darken,
          )
        else
          Container(
            color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
          ),
        // 毛玻璃效果
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                (isDark ? AppColors.darkBackground : Colors.white).withValues(alpha: 0.8),
              ],
            ),
          ),
        ),
        // 内容
        Positioned(
          left: 16,
          bottom: 16,
          right: 16,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 封面
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 80,
                  height: 110,
                  child: widget.book.coverUrl != null && widget.book.coverUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: widget.book.coverUrl!,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                          child: const Icon(Icons.auto_stories_rounded, size: 32),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              // 标题信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.book.name,
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.book.author,
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBookInfo(bool isDark, UIStyle uiStyle) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: AdaptiveGlassContainer(
        uiStyle: uiStyle,
        isDark: isDark,
        cornerRadius: 12,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 分类和字数
              Row(
                children: [
                  if (widget.book.kind != null && widget.book.kind!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.book.kind!,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  if (widget.book.wordCount != null && widget.book.wordCount!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      widget.book.wordCount!,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    '来源: ${widget.book.source.displayName}',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                ],
              ),
              // 简介
              if (widget.book.intro != null && widget.book.intro!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '简介',
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.book.intro!,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                    height: 1.5,
                  ),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChapterHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          Text(
            '目录',
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
            ),
          ),
          if (_chapters != null) ...[
            const SizedBox(width: 8),
            Text(
              '(${_chapters!.length}章)',
              style: context.textTheme.bodySmall?.copyWith(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ],
          const Spacer(),
          // 排序切换
          TextButton.icon(
            onPressed: () => setState(() => _isReversed = !_isReversed),
            icon: Icon(
              _isReversed ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 16,
            ),
            label: Text(_isReversed ? '倒序' : '正序'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChapterList(bool isDark, UIStyle uiStyle) {
    if (_isLoadingChapters) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text('加载目录失败'),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _loadChapters,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_chapters == null || _chapters!.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Text(
            '暂无章节',
            style: context.textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final chapters = _isReversed ? _chapters!.reversed.toList() : _chapters!;

    return SliverPadding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final chapter = chapters[index];
            return _ChapterTile(
              chapter: chapter,
              isDark: isDark,
              uiStyle: uiStyle,
              onTap: () => _openReader(chapter),
            );
          },
          childCount: chapters.length,
        ),
      ),
    );
  }

  void _openReader(OnlineChapter chapter) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => OnlineBookReaderPage(
          book: widget.book,
          chapters: _chapters ?? [],
          initialChapter: chapter,
        ),
      ),
    );
  }
}

/// 章节列表项
class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    required this.chapter,
    required this.isDark,
    required this.uiStyle,
    required this.onTap,
  });

  final OnlineChapter chapter;
  final bool isDark;
  final UIStyle uiStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 卷名样式不同
    if (chapter.isVolume) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          chapter.name,
          style: context.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  chapter.name,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (chapter.updateTime != null && chapter.updateTime!.isNotEmpty)
                Text(
                  chapter.updateTime!,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
