import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/features/nastool/presentation/providers/nastool_provider.dart';
import 'package:my_nas/features/nastool/presentation/widgets/common/nt_common_widgets.dart';
import 'package:my_nas/service_adapters/nastool/models/models.dart';

class NtRssPage extends ConsumerStatefulWidget {
  const NtRssPage({super.key, required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  ConsumerState<NtRssPage> createState() => _NtRssPageState();
}

class _NtRssPageState extends ConsumerState<NtRssPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
      children: [
        ColoredBox(
          color: NtColors.surface(widget.isDark),
          child: TabBar(
            controller: _tabController,
            labelColor: NtColors.primary,
            unselectedLabelColor: NtColors.onSurfaceVariant(widget.isDark),
            indicatorColor: NtColors.primary,
            tabs: const [
              Tab(text: 'RSS 任务', icon: Icon(Icons.rss_feed_rounded, size: 20)),
              Tab(text: '自定义解析', icon: Icon(Icons.code_rounded, size: 20)),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _RssTasksTab(sourceId: widget.sourceId, isDark: widget.isDark),
              _RssParsersTab(sourceId: widget.sourceId, isDark: widget.isDark),
            ],
          ),
        ),
      ],
    );
}

class _RssTasksTab extends ConsumerWidget {
  const _RssTasksTab({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(nastoolRssTasksProvider(sourceId));

    return tasksAsync.when(
      loading: () => const NtLoading(),
      error: (e, _) => NtError(
        message: '加载失败: $e',
        isDark: isDark,
        onRetry: () => ref.invalidate(nastoolRssTasksProvider(sourceId)),
      ),
      data: (tasks) {
        if (tasks.isEmpty) {
          return NtEmptyState(
            icon: Icons.rss_feed_rounded,
            message: '暂无 RSS 订阅任务\n在 NASTool 后台添加 RSS 订阅',
            isDark: isDark,
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(nastoolRssTasksProvider(sourceId)),
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: tasks.length,
            itemBuilder: (context, index) => _RssTaskCard(
              task: tasks[index],
              isDark: isDark,
              onPreview: () => _showPreview(context, tasks[index], ref),
            ),
          ),
        );
      },
    );
  }

  void _showPreview(BuildContext context, NtRssTask task, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, scrollController) => DecoratedBox(
          decoration: BoxDecoration(
            color: NtColors.surface(isDark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Text(
                      '${task.name} - 文章预览',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: NtColors.onSurface(isDark),
                          ),
                    ),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<NtRssArticle>>(
                  future: ref.read(nastoolActionsProvider(sourceId)).previewRssTask(task.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const NtLoading();
                    }
                    if (snapshot.hasError) {
                      return NtError(message: '加载失败: ${snapshot.error}', isDark: isDark);
                    }
                    final articles = snapshot.data ?? [];
                    if (articles.isEmpty) {
                      return NtEmptyState(icon: Icons.article_rounded, message: '暂无文章', isDark: isDark);
                    }
                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      itemCount: articles.length,
                      itemBuilder: (context, index) => _RssArticleTile(article: articles[index], isDark: isDark),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RssParsersTab extends ConsumerWidget {
  const _RssParsersTab({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parsersAsync = ref.watch(nastoolRssParsersProvider(sourceId));

    return parsersAsync.when(
      loading: () => const NtLoading(),
      error: (e, _) => NtError(
        message: '加载失败: $e',
        isDark: isDark,
        onRetry: () => ref.invalidate(nastoolRssParsersProvider(sourceId)),
      ),
      data: (parsers) {
        if (parsers.isEmpty) {
          return NtEmptyState(icon: Icons.code_rounded, message: '暂无自定义解析器', isDark: isDark);
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(nastoolRssParsersProvider(sourceId)),
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: parsers.length,
            itemBuilder: (context, index) => _RssParserCard(parser: parsers[index], isDark: isDark),
          ),
        );
      },
    );
  }
}

class _RssTaskCard extends StatelessWidget {
  const _RssTaskCard({required this.task, required this.isDark, this.onPreview});
  final NtRssTask task;
  final bool isDark;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) => NtCard(
        isDark: isDark,
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: NtColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.rss_feed_rounded, color: NtColors.warning),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: NtColors.onSurface(isDark),
                            ),
                      ),
                      if (task.address != null)
                        Text(
                          task.address!,
                          style: TextStyle(color: NtColors.onSurfaceVariant(isDark), fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                NtChip(
                  label: task.state == 'Y' ? '启用' : '禁用',
                  color: task.state == 'Y' ? NtColors.success : NtColors.onSurfaceVariant(isDark),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                if (task.include != null && task.include!.isNotEmpty)
                  NtChip(label: '包含: ${task.include}', color: NtColors.success),
                if (task.exclude != null && task.exclude!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  NtChip(label: '排除: ${task.exclude}', color: NtColors.error),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                NtButton(label: '预览', icon: Icons.preview_rounded, isOutlined: true, onPressed: onPreview),
              ],
            ),
          ],
        ),
      );
}

class _RssParserCard extends StatelessWidget {
  const _RssParserCard({required this.parser, required this.isDark});
  final NtRssParser parser;
  final bool isDark;

  @override
  Widget build(BuildContext context) => NtCard(
        isDark: isDark,
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: NtColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.code_rounded, color: NtColors.info),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    parser.name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: NtColors.onSurface(isDark),
                        ),
                  ),
                  if (parser.type != null)
                    Text(
                      '类型: ${parser.type}',
                      style: TextStyle(color: NtColors.onSurfaceVariant(isDark), fontSize: 12),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _RssArticleTile extends StatelessWidget {
  const _RssArticleTile({required this.article, required this.isDark});
  final NtRssArticle article;
  final bool isDark;

  @override
  Widget build(BuildContext context) => NtCard(
        isDark: isDark,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              article.title ?? '',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: NtColors.onSurface(isDark),
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (article.description != null) ...[
              const SizedBox(height: 4),
              Text(
                article.description!,
                style: TextStyle(color: NtColors.onSurfaceVariant(isDark), fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (article.size != null) NtChip(label: NtFormatter.bytes(article.size)),
                const Spacer(),
                Text(
                  article.pubDate ?? '',
                  style: TextStyle(color: NtColors.onSurfaceVariant(isDark), fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      );
}
