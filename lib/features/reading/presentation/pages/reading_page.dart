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
    final selectedIndex = ref.watch(readingTabProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: Column(
        children: [
          // 顶部区域：标题
          _buildHeader(context, isDark, selectedIndex),
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

  Widget _buildHeader(BuildContext context, bool isDark, int selectedIndex) {
    final currentType = ReadingContentType.values[selectedIndex];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : context.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.darkOutline.withOpacity(0.2)
                : context.colorScheme.outlineVariant.withOpacity(0.5),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: InkWell(
            onTap: () => _showTypeMenu(context, isDark, selectedIndex),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 图标
                  Icon(
                    currentType.icon,
                    size: 28,
                    color: isDark ? AppColors.darkOnSurface : context.colorScheme.onSurface,
                  ),
                  const SizedBox(width: 12),
                  // 标题
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '阅读',
                        style: context.textTheme.titleSmall?.copyWith(
                          color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        currentType.label,
                        style: context.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkOnSurface : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  // 下拉图标
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 24,
                    color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showTypeMenu(BuildContext context, bool isDark, int currentIndex) {
    showMenu<int>(
      context: context,
      position: const RelativeRect.fromLTRB(16, 80, 0, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? AppColors.darkSurface : Colors.white,
      items: ReadingContentType.values.asMap().entries.map((entry) {
        final index = entry.key;
        final type = entry.value;
        final isSelected = index == currentIndex;

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
                  size: 20,
                  color: AppColors.primary,
                ),
              ],
            ],
          ),
        );
      }).toList(),
    ).then((selectedIndex) {
      if (selectedIndex != null && selectedIndex != currentIndex) {
        _onTabChanged(selectedIndex);
      }
    });
  }
}
