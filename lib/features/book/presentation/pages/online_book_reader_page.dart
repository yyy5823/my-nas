import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/book/domain/entities/book_source.dart';
import 'package:my_nas/features/book/presentation/providers/book_search_provider.dart';
import 'package:my_nas/features/book/presentation/providers/tts_provider.dart';
import 'package:my_nas/features/book/presentation/widgets/tts_control_bar.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';

/// 在线书籍阅读页面
class OnlineBookReaderPage extends ConsumerStatefulWidget {
  const OnlineBookReaderPage({
    super.key,
    required this.book,
    required this.chapters,
    required this.initialChapter,
  });

  final OnlineBook book;
  final List<OnlineChapter> chapters;
  final OnlineChapter initialChapter;

  @override
  ConsumerState<OnlineBookReaderPage> createState() => _OnlineBookReaderPageState();
}

class _OnlineBookReaderPageState extends ConsumerState<OnlineBookReaderPage>
    with TabBarVisibilityMixin {
  late int _currentIndex;
  String? _content;
  bool _isLoading = false;
  String? _error;
  bool _showControls = false;
  bool _showTTS = false;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    hideTabBar();
    _currentIndex = widget.chapters.indexOf(widget.initialChapter);
    if (_currentIndex == -1) _currentIndex = 0;
    _loadContent();
    // 隐藏状态栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    // 恢复状态栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadContent() async {
    if (_currentIndex < 0 || _currentIndex >= widget.chapters.length) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final contentService = ref.read(bookContentServiceProvider);
      final content = await contentService.getChapterContent(
        widget.book.source,
        widget.chapters[_currentIndex],
      );
      if (mounted) {
        setState(() {
          _content = content;
          _isLoading = false;
        });
        // 滚动到顶部
        _scrollController.jumpTo(0);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentChapter = widget.chapters[_currentIndex];

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5DC),
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // 内容区域
            _buildContent(isDark),
            // 控制栏
            if (_showControls) ...[
              // 顶部栏
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopBar(isDark, currentChapter),
              ),
              // 底部栏
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomBar(isDark),
              ),
            ],
            // TTS 控制栏
            if (_showTTS)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: TTSControlBar(
                  onClose: () => setState(() => _showTTS = false),
                  backgroundColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5DC),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text('加载失败', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadContent,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_content == null || _content!.isEmpty) {
      return Center(
        child: Text(
          '暂无内容',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
        ),
      );
    }

    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).padding.bottom + 60,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 章节标题
          Text(
            widget.chapters[_currentIndex].name,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 24),
          // 正文
          Text(
            _content!,
            style: TextStyle(
              fontSize: 18,
              height: 1.8,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 40),
          // 翻页按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (_currentIndex > 0)
                OutlinedButton.icon(
                  onPressed: _previousChapter,
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const Text('上一章'),
                )
              else
                const SizedBox(width: 120),
              if (_currentIndex < widget.chapters.length - 1)
                OutlinedButton.icon(
                  onPressed: _nextChapter,
                  icon: const Icon(Icons.chevron_right_rounded),
                  label: const Text('下一章'),
                )
              else
                const SizedBox(width: 120),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(bool isDark, OnlineChapter chapter) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          chapter.name,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_rounded, color: Colors.white),
            onPressed: _showChapterList,
            tooltip: '目录',
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(bool isDark) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + AppSpacing.sm,
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildBarButton(
            icon: Icons.skip_previous_rounded,
            label: '上一章',
            onTap: _currentIndex > 0 ? _previousChapter : null,
          ),
          _buildBarButton(
            icon: Icons.headphones_rounded,
            label: '朗读',
            onTap: _startTTS,
          ),
          _buildBarButton(
            icon: Icons.format_list_bulleted_rounded,
            label: '目录',
            onTap: _showChapterList,
          ),
          _buildBarButton(
            icon: Icons.skip_next_rounded,
            label: '下一章',
            onTap: _currentIndex < widget.chapters.length - 1 ? _nextChapter : null,
          ),
        ],
      ),
    );
  }

  Widget _buildBarButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  void _previousChapter() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _loadContent();
    }
  }

  void _nextChapter() {
    if (_currentIndex < widget.chapters.length - 1) {
      setState(() => _currentIndex++);
      _loadContent();
    }
  }

  /// 开始朗读当前章节
  Future<void> _startTTS() async {
    if (_content == null || _content!.isEmpty) return;

    final ttsNotifier = ref.read(ttsProvider.notifier);
    await ttsNotifier.init();

    // 按段落分割
    final paragraphs = _content!
        .split(RegExp(r'\n\n+'))
        .where((p) => p.trim().isNotEmpty)
        .toList();

    setState(() => _showTTS = true);

    await ttsNotifier.speakParagraphs(
      paragraphs,
      onAllComplete: () {
        // 朗读完成，检查是否自动播放下一章
        final settings = ref.read(ttsProvider).settings;
        if (settings.autoPlayNextChapter && _currentIndex < widget.chapters.length - 1) {
          _nextChapter();
          Future.delayed(const Duration(milliseconds: 500), _startTTS);
        }
      },
    );
  }

  void _showChapterList() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => _ChapterListSheet(
          chapters: widget.chapters,
          currentIndex: _currentIndex,
          scrollController: scrollController,
          onSelect: (index) {
            Navigator.pop(context);
            setState(() => _currentIndex = index);
            _loadContent();
          },
        ),
      ),
    );
  }
}

/// 章节列表弹框
class _ChapterListSheet extends StatelessWidget {
  const _ChapterListSheet({
    required this.chapters,
    required this.currentIndex,
    required this.scrollController,
    required this.onSelect,
  });

  final List<OnlineChapter> chapters;
  final int currentIndex;
  final ScrollController scrollController;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // 拖拽指示器
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.3)
                  : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              '目录',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),
          ),
          // 章节列表
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              itemCount: chapters.length,
              itemBuilder: (context, index) {
                final chapter = chapters[index];
                final isSelected = index == currentIndex;
                return ListTile(
                  title: Text(
                    chapter.name,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_rounded, color: AppColors.primary)
                      : null,
                  onTap: () => onSelect(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
