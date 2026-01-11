import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/book/data/services/online_book_shelf_service.dart';
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
  bool _isInShelf = false;

  @override
  void initState() {
    super.initState();
    hideTabBar();
    _loadChapters();
    _checkShelfStatus();
  }

  Future<void> _checkShelfStatus() async {
    final inShelf = await OnlineBookShelfService.instance.isInShelf(
      widget.book.bookUrl,
      widget.book.source.id,
    );
    if (mounted) {
      setState(() => _isInShelf = inShelf);
    }
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

  /// 获取可显示的书名
  String get _displayName {
    final name = widget.book.name;
    // 如果是URL，尝试提取书名
    if (name.startsWith('http://') || name.startsWith('https://')) {
      return _extractNameFromUrl(name);
    }
    // URL解码
    return _urlDecode(name);
  }

  /// 获取可显示的作者
  String get _displayAuthor {
    final author = widget.book.author;
    if (!_isValidText(author)) return '';
    return _urlDecode(author);
  }

  /// 获取可显示的简介
  String? get _displayIntro {
    final intro = widget.book.intro;
    if (intro == null || intro.isEmpty) return null;
    if (!_isValidText(intro)) return null;
    return _urlDecode(intro);
  }

  /// 获取可显示的分类
  String? get _displayKind {
    final kind = widget.book.kind;
    if (kind == null || kind.isEmpty) return null;
    if (!_isValidText(kind)) return null;
    return _urlDecode(kind);
  }

  /// 获取可显示的字数
  String? get _displayWordCount {
    final wc = widget.book.wordCount;
    if (wc == null || wc.isEmpty) return null;
    if (!_isValidText(wc)) return null;
    return _urlDecode(wc);
  }

  /// 检查文本是否有效（非URL、非JSON）
  bool _isValidText(String text) {
    if (text.isEmpty) return false;
    // 检查是否是URL
    if (text.startsWith('http://') || text.startsWith('https://')) return false;
    // 检查是否是JSON对象
    if (text.startsWith('{') && text.endsWith('}')) return false;
    if (text.startsWith('[') && text.endsWith(']')) return false;
    // 检查是否包含大量URL编码
    if (RegExp(r'%[0-9A-Fa-f]{2}').allMatches(text).length > text.length / 10) {
      return true; // 有编码但尝试解码
    }
    return true;
  }

  /// URL解码
  String _urlDecode(String text) {
    try {
      final decoded = Uri.decodeComponent(text);
      if (decoded != text) return decoded;
    } catch (_) {}
    return text;
  }

  /// 从URL提取书名
  String _extractNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      var path = uri.path
          .replaceAll(RegExp(r'^/+'), '')
          .replaceAll(RegExp(r'\.(html?|php|aspx?)$', caseSensitive: false), '')
          .replaceAll(RegExp(r'/+$'), '');
      
      path = Uri.decodeComponent(path);
      
      if (path.isEmpty || RegExp(r'^\d+$').hasMatch(path)) {
        return widget.book.name; // 无法提取，返回原值
      }
      
      final parts = path.split('/');
      return parts.last;
    } catch (_) {
      return widget.book.name;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uiStyle = ref.watch(uiStyleProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      floatingActionButton: _buildFloatingButtons(isDark),
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
                      _displayName,
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _displayAuthor,
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

  /// 构建浮动操作按钮
  Widget _buildFloatingButtons(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 加入书架按钮
        GestureDetector(
          onLongPress: _isInShelf ? _removeFromShelf : null,
          child: FloatingActionButton.small(
            heroTag: 'addToShelf',
            onPressed: _addToShelf,
            backgroundColor: _isInShelf 
                ? AppColors.primary 
                : (isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant),
            foregroundColor: _isInShelf 
                ? Colors.white 
                : AppColors.primary,
            child: Icon(_isInShelf ? Icons.bookmark_rounded : Icons.bookmark_add_outlined),
          ),
        ),
        const SizedBox(height: 12),
        // 开始阅读按钮
        FloatingActionButton.extended(
          heroTag: 'startReading',
          onPressed: _startReading,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('开始阅读'),
        ),
      ],
    );
  }

  Future<void> _addToShelf() async {
    if (_isInShelf) {
      context.showToast('已在书架中');
      return;
    }
    
    try {
      await OnlineBookShelfService.instance.addBook(widget.book);
      if (mounted) {
        setState(() => _isInShelf = true);
        context.showToast('已加入书架: $_displayName');
      }
    } catch (e) {
      if (mounted) {
        context.showToast('加入书架失败');
      }
    }
  }

  Future<void> _removeFromShelf() async {
    final shelfItem = await OnlineBookShelfService.instance.getByBookUrl(
      widget.book.bookUrl,
      widget.book.source.id,
    );
    if (shelfItem == null) return;
    
    await OnlineBookShelfService.instance.removeBook(shelfItem.id);
    if (mounted) {
      setState(() => _isInShelf = false);
      context.showToast('已从书架移除');
    }
  }

  void _startReading() {
    if (_chapters != null && _chapters!.isNotEmpty) {
      _openReader(_chapters!.first);
    } else {
      context.showToast('暂无章节可阅读');
    }
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
                  if (_displayKind != null && _displayKind!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _displayKind!,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  if (_displayWordCount != null && _displayWordCount!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      _displayWordCount!,
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
              if (_displayIntro != null && _displayIntro!.isNotEmpty) ...[
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
                  _displayIntro!,
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
