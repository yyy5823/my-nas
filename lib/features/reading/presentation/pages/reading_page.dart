import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/book/presentation/pages/book_list_page.dart';
import 'package:my_nas/features/comic/presentation/pages/comic_list_page.dart';
import 'package:my_nas/features/note/presentation/pages/note_list_page.dart';
import 'package:my_nas/features/note/presentation/widgets/note_tree_widget.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_glass_app_bar.dart';

/// 当前选中的阅读 Tab
final readingTabProvider = StateProvider<int>((ref) => 0);

/// 阅读内容类型
enum ReadingContentType {
  book(Icons.menu_book_rounded, '图书'),
  comic(Icons.collections_bookmark_rounded, '漫画'),
  note(Icons.note_alt_rounded, '笔记');

  const ReadingContentType(this.icon, this.label);
  final IconData icon;
  final String label;
}

class ReadingPage extends ConsumerStatefulWidget {
  const ReadingPage({super.key});

  @override
  ConsumerState<ReadingPage> createState() => _ReadingPageState();
}

class _ReadingPageState extends ConsumerState<ReadingPage> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: ref.read(readingTabProvider),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabChanged(int index) {
    ref.read(readingTabProvider.notifier).state = index;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentTab = ref.watch(readingTabProvider);
    final uiStyle = ref.watch(uiStyleProvider);
    final safeTop = MediaQuery.of(context).padding.top;

    // iOS 26 玻璃模式：悬浮布局
    if (uiStyle.isGlass) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
        body: Stack(
          children: [
            // 主内容区域
            _buildReadingContentWithLargeTitle(context, isDark, currentTab, safeTop),
            // 悬浮按钮组（右上角）
            Positioned(
              top: safeTop + 8,
              right: 16,
              child: _buildFloatingButtons(context, isDark, currentTab),
            ),
          ],
        ),
      );
    }

    // 经典模式：传统布局
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: Column(
        children: [
          // 统一的顶栏
          _buildAppBar(context, isDark, currentTab),
          // 内容区域
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(), // 禁用手势滑动
              onPageChanged: (index) {
                ref.read(readingTabProvider.notifier).state = index;
              },
              children: const [
                // 图书页面内容
                BookListContent(),
                // 漫画页面内容
                ComicListContent(),
                // 笔记页面内容
                NoteListContent(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// iOS 26 悬浮按钮组
  Widget _buildFloatingButtons(BuildContext context, bool isDark, int currentTab) =>
    GlassButtonGroup(
      children: [
        GlassGroupPopupMenuButton<int>(
          icon: ReadingContentType.values[currentTab].icon,
          tooltip: '切换内容类型',
          itemBuilder: (context) => ReadingContentType.values.asMap().entries.map((entry) {
            final index = entry.key;
            final type = entry.value;
            final isSelected = index == currentTab;

            return PopupMenuItem<int>(
              value: index,
              child: Row(
                children: [
                  Icon(
                    type.icon,
                    size: 20,
                    color: isSelected
                        ? AppColors.primary
                        : (isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[600]),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    type.label,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : (isDark ? AppColors.darkOnSurface : Colors.black87),
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  if (isSelected) ...[
                    const Spacer(),
                    Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
          onSelected: _onTabChanged,
        ),
      ],
    );

  /// iOS 26 带大标题的阅读内容
  Widget _buildReadingContentWithLargeTitle(
    BuildContext context,
    bool isDark,
    int currentTab,
    double safeTop,
  ) => PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      onPageChanged: (index) {
        ref.read(readingTabProvider.notifier).state = index;
      },
      children: [
        // 图书页面 - 带大标题的滚动布局
        _buildScrollableContent(
          context, isDark, currentTab, safeTop,
          child: const BookListContent(),
        ),
        // 漫画页面
        _buildScrollableContent(
          context, isDark, currentTab, safeTop,
          child: const ComicListContent(),
        ),
        // 笔记页面
        _buildScrollableContent(
          context, isDark, currentTab, safeTop,
          child: const NoteListContent(),
        ),
      ],
    );

  /// 构建带大标题的可滚动内容
  Widget _buildScrollableContent(
    BuildContext context,
    bool isDark,
    int currentTab,
    double safeTop, {
    required Widget child,
  }) {
    return Column(
      children: [
        // 顶部安全区留白 + 大标题
        Padding(
          padding: EdgeInsets.only(top: safeTop + 8),
          child: _buildLargeTitle(context, isDark, currentTab, hasFloatingButtons: true),
        ),
        // 内容 - 使用 Expanded 填充剩余空间
        Expanded(child: child),
      ],
    );
  }

  /// iOS 26 大标题区域（非 Sliver 版本）
  Widget _buildLargeTitle(
    BuildContext context,
    bool isDark,
    int currentTab, {
    bool hasFloatingButtons = false,
  }) {
    // 获取各类数据统计
    final bookState = ref.watch(bookListProvider);
    final comicState = ref.watch(comicListProvider);
    final noteState = ref.watch(notePageProvider);

    final bookCount = bookState is BookListLoaded ? bookState.totalCount : 0;
    final comicCount = comicState is ComicListLoaded ? comicState.comics.length : 0;
    final noteCount = noteState is NotePageLoaded ? _countNotes(noteState.treeNodes) : 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 大标题 - 需要避开浮动按钮
          Padding(
            padding: EdgeInsets.only(right: hasFloatingButtons ? 150 : 0),
            child: Text(
              _getGreeting(),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 统计信息 - 横向排列
          Row(
            children: [
              _buildStatChip(
                icon: Icons.menu_book_rounded,
                label: '$bookCount 本',
                color: Colors.amber[700]!,
                isDark: isDark,
                isActive: currentTab == 0,
              ),
              const SizedBox(width: 12),
              _buildStatChip(
                icon: Icons.collections_bookmark_rounded,
                label: '$comicCount 部',
                color: Colors.orange[600]!,
                isDark: isDark,
                isActive: currentTab == 1,
              ),
              const SizedBox(width: 12),
              _buildStatChip(
                icon: Icons.note_alt_rounded,
                label: '$noteCount 篇',
                color: Colors.green[600]!,
                isDark: isDark,
                isActive: currentTab == 2,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 统计信息小标签
  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    bool isActive = false,
  }) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: isActive ? color : (isDark ? Colors.grey[500] : Colors.grey[400])),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive
                ? (isDark ? Colors.white : Colors.black87)
                : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
          ),
        ),
      ],
    );

  /// 计算笔记数量（只计算文件，不计算文件夹）
  int _countNotes(List<NoteTreeNode> nodes) {
    var count = 0;
    for (final node in nodes) {
      if (node.type == NoteTreeNodeType.file) {
        count++;
      }
      if (node.children.isNotEmpty) {
        count += _countNotes(node.children);
      }
    }
    return count;
  }

  Widget _buildAppBar(BuildContext context, bool isDark, int currentTab) {
    final uiStyle = ref.watch(uiStyleProvider);

    // 玻璃模式下的染色
    final tintColor = uiStyle.isGlass
        ? (isDark
            ? Colors.amber.withValues(alpha: 0.15)
            : Colors.amber.withValues(alpha: 0.08))
        : null;

    return AdaptiveGlassHeader(
      height: 72,
      backgroundColor: uiStyle.isGlass
          ? tintColor
          : (isDark
              ? const Color(0xFF2E2A1A) // 深琥珀棕色调
              : Colors.amber.withValues(alpha: 0.08)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 16, 16),
        child: Row(
          children: [
            // 问候语和当前类型标题
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getGreeting(),
                    style: context.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        ReadingContentType.values[currentTab].icon,
                        size: 14,
                        color: Colors.amber[700],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        ReadingContentType.values[currentTab].label,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppColors.darkOnSurfaceVariant
                              : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 类型切换按钮
            _buildTypeSwitcher(context, isDark, currentTab),
          ],
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了';
    if (hour < 9) return '早上好';
    if (hour < 12) return '上午好';
    if (hour < 14) return '中午好';
    if (hour < 18) return '下午好';
    if (hour < 22) return '晚上好';
    return '夜深了';
  }

  Widget _buildTypeSwitcher(BuildContext context, bool isDark, int currentTab) {
    final uiStyle = ref.watch(uiStyleProvider);

    final popupButton = PopupMenuButton<int>(
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: EdgeInsets.zero,
      itemBuilder: (context) => ReadingContentType.values.asMap().entries.map((entry) {
        final index = entry.key;
        final type = entry.value;
        final isSelected = index == currentTab;

        return PopupMenuItem<int>(
          value: index,
          child: Row(
            children: [
              Icon(
                type.icon,
                size: 20,
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[600]),
              ),
              const SizedBox(width: 12),
              Text(
                type.label,
                style: TextStyle(
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? AppColors.darkOnSurface : Colors.black87),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (isSelected) ...[
                const Spacer(),
                Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
              ],
            ],
          ),
        );
      }).toList(),
      onSelected: _onTabChanged,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ReadingContentType.values[currentTab].icon,
            size: 22,
            color: isDark ? Colors.white : Colors.black87,
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.arrow_drop_down_rounded,
            size: 20,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ],
      ),
    );

    // 玻璃模式下使用浮动玻璃按钮样式
    if (uiStyle.isGlass) {
      final glassStyle = GlassTheme.getStyle(uiStyle, isDark: isDark);
      final bgColor = isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.06);
      final borderColor = isDark
          ? Colors.white.withValues(alpha: glassStyle.borderOpacity * 0.8)
          : Colors.black.withValues(alpha: glassStyle.borderOpacity * 0.4);

      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor, width: 0.5),
            ),
            child: popupButton,
          ),
        ),
      );
    }

    // 经典模式
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
          ),
          child: popupButton,
        ),
      ),
    );
  }
}
