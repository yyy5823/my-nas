import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/book/presentation/pages/book_list_page.dart';
import 'package:my_nas/features/comic/presentation/pages/comic_list_page.dart';
import 'package:my_nas/features/note/presentation/pages/note_list_page.dart';
import 'package:my_nas/shared/widgets/elegant_segment_control.dart';

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
          // 顶部区域：标题 + 分段控制器
          _buildHeader(context, isDark, selectedIndex),
          // 内容区域
          Expanded(
            child: PageView(
              controller: _pageController,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Text(
                '阅读',
                style: context.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkOnSurface : null,
                ),
              ),
              const SizedBox(height: 16),
              // 分段控制器
              ElegantSegmentControl(
                items: ReadingContentType.values
                    .map((type) => SegmentItem(icon: type.icon, label: type.label))
                    .toList(),
                selectedIndex: selectedIndex,
                onChanged: _onTabChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
