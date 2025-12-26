import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/features/nastool/presentation/providers/nastool_provider.dart';
import 'package:my_nas/features/nastool/presentation/widgets/common/nt_common_widgets.dart';
import 'package:my_nas/service_adapters/nastool/models/models.dart';

class NtMediaPage extends ConsumerStatefulWidget {
  const NtMediaPage({super.key, required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  ConsumerState<NtMediaPage> createState() => _NtMediaPageState();
}

class _NtMediaPageState extends ConsumerState<NtMediaPage> {
  final _searchController = TextEditingController();
  List<NtSearchResult>? _searchResults;
  bool _isSearching = false;
  String? _searchError;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _doSearch(String keyword) async {
    if (keyword.trim().isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final results = await ref.read(nastoolActionsProvider(widget.sourceId)).searchResources(keyword);
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _searchError = e.toString();
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: NtSearchBar(
            controller: _searchController,
            isDark: widget.isDark,
            hintText: '搜索影视资源...',
            onSubmitted: _doSearch,
          ),
        ),
        Expanded(
          child: _buildContent(),
        ),
      ],
    );

  Widget _buildContent() {
    if (_isSearching) {
      return const NtLoading(message: '搜索中...');
    }

    if (_searchError != null) {
      return NtError(
        message: '搜索失败: $_searchError',
        isDark: widget.isDark,
        onRetry: () => _doSearch(_searchController.text),
      );
    }

    if (_searchResults == null) {
      return NtEmptyState(
        icon: Icons.search_rounded,
        message: '输入关键词搜索影视资源',
        isDark: widget.isDark,
      );
    }

    if (_searchResults!.isEmpty) {
      return NtEmptyState(
        icon: Icons.search_off_rounded,
        message: '未找到相关资源',
        isDark: widget.isDark,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      itemCount: _searchResults!.length,
      itemBuilder: (context, index) => _SearchResultCard(
        result: _searchResults![index],
        isDark: widget.isDark,
        onDownload: () => _downloadResource(_searchResults![index]),
        onSubscribe: () => _subscribeResource(_searchResults![index]),
      ),
    );
  }

  void _downloadResource(NtSearchResult result) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('下载资源'),
        content: Text('确定要下载「${result.title}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(nastoolActionsProvider(widget.sourceId)).downloadResource(
                    enclosure: result.enclosure ?? '',
                    title: result.title,
                  );
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已添加到下载队列')));
            },
            child: const Text('下载'),
          ),
        ],
      ),
    );
  }

  void _subscribeResource(NtSearchResult result) {
    ref.read(nastoolActionsProvider(widget.sourceId)).addSubscribe(
          name: result.title,
          type: 'MOV',
        );
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已添加订阅')));
  }
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.result,
    required this.isDark,
    this.onDownload,
    this.onSubscribe,
  });

  final NtSearchResult result;
  final bool isDark;
  final VoidCallback? onDownload;
  final VoidCallback? onSubscribe;

  @override
  Widget build(BuildContext context) => NtCard(
        isDark: isDark,
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: NtColors.surfaceVariant(isDark),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.movie, size: 28, color: NtColors.onSurfaceVariant(isDark)),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: NtColors.onSurface(isDark),
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (result.site != null) NtChip(label: result.site!, color: NtColors.info),
                          NtChip(label: NtFormatter.bytes(result.size)),
                          if (result.resolution != null) NtChip(label: result.resolution!, color: NtColors.success),
                          if (result.seeders != null)
                            NtChip(label: '${result.seeders}↑', color: NtColors.success, icon: Icons.arrow_upward),
                        ],
                      ),
                      if (result.description != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          result.description!,
                          style: TextStyle(color: NtColors.onSurfaceVariant(isDark), fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                NtButton(
                  label: '订阅',
                  icon: Icons.bookmark_add_rounded,
                  isOutlined: true,
                  onPressed: onSubscribe,
                ),
                const SizedBox(width: AppSpacing.sm),
                NtButton(
                  label: '下载',
                  icon: Icons.download_rounded,
                  onPressed: onDownload,
                ),
              ],
            ),
          ],
        ),
      );
}
