import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/book/presentation/pages/book_list_page.dart';
import 'package:my_nas/features/note/presentation/pages/note_list_page.dart';

/// 当前选中的阅读 Tab
final readingTabProvider = StateProvider<int>((ref) => 0);

class ReadingPage extends ConsumerStatefulWidget {
  const ReadingPage({super.key});

  @override
  ConsumerState<ReadingPage> createState() => _ReadingPageState();
}

class _ReadingPageState extends ConsumerState<ReadingPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        ref.read(readingTabProvider.notifier).state = _tabController.index;
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: Column(
        children: [
          // 顶部区域：标题 + Tab
          _buildHeader(context, isDark),
          // 内容区域
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                // 图书页面内容
                _BookContent(),
                // 笔记页面内容
                _NoteContent(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
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
        child: Column(
          children: [
            // 标题行
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Text(
                    '阅读',
                    style: context.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkOnSurface : null,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            // Tab 栏
            TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: isDark
                  ? AppColors.darkOnSurfaceVariant
                  : context.colorScheme.onSurfaceVariant,
              indicatorColor: AppColors.primary,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.normal,
                fontSize: 15,
              ),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.menu_book_rounded, size: 18),
                      SizedBox(width: 6),
                      Text('图书'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.note_rounded, size: 18),
                      SizedBox(width: 6),
                      Text('笔记'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 图书内容（复用 BookListPage 的核心内容）
class _BookContent extends ConsumerWidget {
  const _BookContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 直接使用 BookListPage 的内容部分
    return const BookListContent();
  }
}

/// 笔记内容（复用 NoteListPage 的核心内容）
class _NoteContent extends ConsumerWidget {
  const _NoteContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 直接使用 NoteListPage 的内容部分
    return const NoteListContent();
  }
}
