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

  Widget _buildAppBar(BuildContext context, bool isDark, int currentTab) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : context.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : context.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SizedBox(
            height: 40, // 确保和其他导航页面的顶栏高度一致
            child: Row(
              children: [
                // 当前类型标题
                Text(
                  ReadingContentType.values[currentTab].label,
                  style: context.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkOnSurface : null,
                  ),
                ),
                const Spacer(),
                // 类型切换按钮
                _buildTypeSwitcher(context, isDark, currentTab),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSwitcher(BuildContext context, bool isDark, int currentTab) {
    return PopupMenuButton<int>(
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
}
