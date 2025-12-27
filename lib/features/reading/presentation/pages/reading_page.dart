import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/book/presentation/pages/book_list_page.dart';
import 'package:my_nas/features/comic/presentation/pages/comic_list_page.dart';
import 'package:my_nas/features/note/presentation/pages/note_list_page.dart';

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

  Widget _buildAppBar(BuildContext context, bool isDark, int currentTab) =>
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF2E2A1A), AppColors.darkBackground] // 深琥珀棕色调
                : [Colors.amber.withValues(alpha: 0.08), Colors.grey[50]!],
          ),
        ),
        child: SafeArea(
          bottom: false,
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
                              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
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
        ),
      );

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

  Widget _buildTypeSwitcher(BuildContext context, bool isDark, int currentTab) => PopupMenuButton<int>(
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  ReadingContentType.values[currentTab].icon,
                  size: 22,
                  color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[700],
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 20,
                  color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[600],
                ),
              ],
            ),
          ),
        ),
      ),
    );
}
