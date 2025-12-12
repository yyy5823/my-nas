import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/pt_sites/data/services/pt_site_api.dart';
import 'package:my_nas/features/pt_sites/domain/entities/pt_torrent.dart';
import 'package:my_nas/features/pt_sites/presentation/providers/pt_site_provider.dart';
import 'package:my_nas/features/pt_sites/presentation/widgets/pt_torrent_card.dart';
import 'package:my_nas/features/pt_sites/presentation/widgets/send_to_downloader_sheet.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';

/// PT 站点详情页
class PTSiteDetailPage extends ConsumerStatefulWidget {
  const PTSiteDetailPage({
    required this.source,
    super.key,
  });

  final SourceEntity source;

  @override
  ConsumerState<PTSiteDetailPage> createState() => _PTSiteDetailPageState();
}

class _PTSiteDetailPageState extends ConsumerState<PTSiteDetailPage> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  bool _isSearching = false;
  bool _hasConnected = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connect();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(ptTorrentListProvider(widget.source.id).notifier).loadMore();
    }
  }

  Future<void> _connect() async {
    if (_hasConnected) return;
    _hasConnected = true;

    await ref
        .read(ptSiteConnectionProvider(widget.source.id).notifier)
        .connect(widget.source);

    final connection = ref.read(ptSiteConnectionProvider(widget.source.id));
    if (connection.status == PTSiteConnectionStatus.connected) {
      await ref
          .read(ptTorrentListProvider(widget.source.id).notifier)
          .loadTorrents();
    }
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(ptSiteConnectionProvider(widget.source.id));
    final torrentListState = ref.watch(ptTorrentListProvider(widget.source.id));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '搜索种子...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant
                        : AppColors.lightOnSurfaceVariant,
                  ),
                ),
                style: TextStyle(
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                ),
                onSubmitted: (value) {
                  ref
                      .read(ptTorrentListProvider(widget.source.id).notifier)
                      .setKeyword(value.isEmpty ? null : value);
                  ref
                      .read(ptTorrentListProvider(widget.source.id).notifier)
                      .loadTorrents(refresh: true);
                },
              )
            : Text(widget.source.name.isEmpty
                ? widget.source.type.displayName
                : widget.source.name),
        actions: [
          // 搜索按钮
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  ref
                      .read(ptTorrentListProvider(widget.source.id).notifier)
                      .setKeyword(null);
                  ref
                      .read(ptTorrentListProvider(widget.source.id).notifier)
                      .loadTorrents(refresh: true);
                }
              });
            },
          ),
          // 筛选按钮
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterSheet(context),
          ),
          // 排序按钮
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () => _showSortSheet(context),
          ),
          // 更多菜单
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'refresh':
                  ref
                      .read(ptTorrentListProvider(widget.source.id).notifier)
                      .loadTorrents(refresh: true);
                case 'user_info':
                  _showUserInfoSheet(context, connection.userInfo);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh),
                    SizedBox(width: 12),
                    Text('刷新'),
                  ],
                ),
              ),
              if (connection.userInfo != null)
                const PopupMenuItem(
                  value: 'user_info',
                  child: Row(
                    children: [
                      Icon(Icons.person),
                      SizedBox(width: 12),
                      Text('个人信息'),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: _buildBody(connection, torrentListState, isDark),
    );
  }

  Widget _buildBody(
    PTSiteConnection connection,
    PTTorrentListState torrentListState,
    bool isDark,
  ) {
    // 连接中
    if (connection.status == PTSiteConnectionStatus.connecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在连接...'),
          ],
        ),
      );
    }

    // 连接错误
    if (connection.status == PTSiteConnectionStatus.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: isDark ? AppColors.errorLight : AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              '连接失败',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                connection.errorMessage ?? '未知错误',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark
                      ? AppColors.darkOnSurfaceVariant
                      : AppColors.lightOnSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                _hasConnected = false;
                _connect();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    // 加载中
    if (torrentListState.isLoading && torrentListState.torrents.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // 加载错误
    if (torrentListState.error != null && torrentListState.torrents.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(torrentListState.error!),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref
                  .read(ptTorrentListProvider(widget.source.id).notifier)
                  .loadTorrents(refresh: true),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    // 空列表
    if (torrentListState.torrents.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: isDark
                  ? AppColors.darkOnSurfaceVariant
                  : AppColors.lightOnSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              torrentListState.keyword != null ? '没有找到相关种子' : '暂无种子',
              style: TextStyle(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // 种子列表
    return RefreshIndicator(
      onRefresh: () => ref
          .read(ptTorrentListProvider(widget.source.id).notifier)
          .loadTorrents(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: torrentListState.torrents.length +
            (torrentListState.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == torrentListState.torrents.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final torrent = torrentListState.torrents[index];
          return PTTorrentCard(
            torrent: torrent,
            onTap: () => _showTorrentDetail(context, torrent),
            onDownload: () => _showDownloadOptions(context, torrent),
          );
        },
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    final categories = ref.read(ptCategoriesProvider(widget.source.id));

    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '筛选分类',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.all_inclusive),
              title: const Text('全部'),
              onTap: () {
                ref
                    .read(ptTorrentListProvider(widget.source.id).notifier)
                    .setCategory(null);
                ref
                    .read(ptTorrentListProvider(widget.source.id).notifier)
                    .loadTorrents(refresh: true);
                Navigator.pop(context);
              },
            ),
            categories.when(
              data: (cats) => Column(
                children: cats
                    .map((cat) => ListTile(
                          leading: const Icon(Icons.folder),
                          title: Text(cat.name),
                          onTap: () {
                            ref
                                .read(ptTorrentListProvider(widget.source.id)
                                    .notifier)
                                .setCategory(cat.id);
                            ref
                                .read(ptTorrentListProvider(widget.source.id)
                                    .notifier)
                                .loadTorrents(refresh: true);
                            Navigator.pop(context);
                          },
                        ))
                    .toList(),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showSortSheet(BuildContext context) {
    final currentState = ref.read(ptTorrentListProvider(widget.source.id));

    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '排序方式',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ...[
              (PTTorrentSortBy.uploadTime, '上传时间', Icons.access_time),
              (PTTorrentSortBy.size, '大小', Icons.storage),
              (PTTorrentSortBy.seeders, '做种人数', Icons.upload),
              (PTTorrentSortBy.leechers, '下载人数', Icons.download),
              (PTTorrentSortBy.snatched, '完成次数', Icons.check_circle),
            ].map((item) => ListTile(
                  leading: Icon(item.$3),
                  title: Text(item.$2),
                  trailing: currentState.sortBy == item.$1
                      ? Icon(
                          currentState.descending
                              ? Icons.arrow_downward
                              : Icons.arrow_upward,
                          size: 20,
                        )
                      : null,
                  selected: currentState.sortBy == item.$1,
                  onTap: () {
                    if (currentState.sortBy == item.$1) {
                      ref
                          .read(
                              ptTorrentListProvider(widget.source.id).notifier)
                          .toggleSortDirection();
                    } else {
                      ref
                          .read(
                              ptTorrentListProvider(widget.source.id).notifier)
                          .setSortBy(item.$1);
                    }
                    ref
                        .read(ptTorrentListProvider(widget.source.id).notifier)
                        .loadTorrents(refresh: true);
                    Navigator.pop(context);
                  },
                )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showUserInfoSheet(BuildContext context, PTUserInfo? userInfo) {
    if (userInfo == null) return;

    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    child: Text(
                      userInfo.username.isNotEmpty
                          ? userInfo.username[0].toUpperCase()
                          : '?',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userInfo.username,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (userInfo.userClass != null)
                          Text(
                            userInfo.userClass!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildInfoRow('上传量', userInfo.formattedUploaded),
              _buildInfoRow('下载量', userInfo.formattedDownloaded),
              _buildInfoRow('分享率', userInfo.formattedRatio),
              _buildInfoRow('魔力值', userInfo.bonus.toStringAsFixed(0)),
              _buildInfoRow('做种数', userInfo.seedingCount.toString()),
              _buildInfoRow('下载数', userInfo.leechingCount.toString()),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );

  void _showTorrentDetail(BuildContext context, PTTorrent torrent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SafeArea(
          child: Column(
            children: [
              // 拖动指示器
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkOnSurfaceVariant
                      : AppColors.lightOnSurfaceVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 内容
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 种子名称
                      Text(
                        torrent.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 促销标签
                      if (torrent.status.hasPromotion) ...[
                        Wrap(
                          spacing: 8,
                          children: [
                            _buildPromotionChip(torrent.status),
                            if (torrent.status.formattedRemainingTime != null)
                              Chip(
                                label: Text(
                                  '剩余 ${torrent.status.formattedRemainingTime}',
                                ),
                                backgroundColor: Colors.orange.withValues(alpha: 0.2),
                                labelStyle: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 基本信息
                      _buildDetailRow(Icons.storage, '大小', torrent.formattedSize),
                      _buildDetailRow(Icons.upload, '做种', '${torrent.seeders}'),
                      _buildDetailRow(Icons.download, '下载', '${torrent.leechers}'),
                      _buildDetailRow(
                          Icons.check_circle, '完成', '${torrent.snatched}'),
                      _buildDetailRow(
                        Icons.access_time,
                        '上传时间',
                        _formatDateTime(torrent.uploadTime),
                      ),

                      if (torrent.category != null)
                        _buildDetailRow(Icons.folder, '分类', torrent.category!),

                      if (torrent.smallDescr != null &&
                          torrent.smallDescr!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          '简介',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? AppColors.darkOnSurface
                                : AppColors.lightOnSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          torrent.smallDescr!,
                          style: TextStyle(
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                      ],

                      // 标签
                      if (torrent.labels.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: torrent.labels
                              .map((label) => Chip(
                                    label: Text(
                                      label,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                  ))
                              .toList(),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // 操作按钮
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _copyDownloadUrl(torrent),
                              icon: const Icon(Icons.copy),
                              label: const Text('复制链接'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _showDownloadOptions(context, torrent);
                              },
                              icon: const Icon(Icons.download),
                              label: const Text('下载'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPromotionChip(PTTorrentStatus status) {
    final label = status.promotionLabel;
    if (label == null) return const SizedBox.shrink();

    final color = status.isFree || status.isDoubleFree
        ? Colors.green
        : status.isDoubleUp
            ? Colors.blue
            : Colors.orange;

    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: color,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} 分钟前';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} 小时前';
    } else if (diff.inDays < 30) {
      return '${diff.inDays} 天前';
    } else {
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _copyDownloadUrl(PTTorrent torrent) async {
    try {
      final api = ref.read(ptSiteConnectionProvider(widget.source.id)).api;
      if (api == null) return;

      final url = await api.getDownloadUrl(torrent.id);
      await Clipboard.setData(ClipboardData(text: url));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('下载链接已复制到剪贴板'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('获取下载链接失败: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showDownloadOptions(BuildContext context, PTTorrent torrent) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SendToDownloaderSheet(
        torrent: torrent,
        sourceId: widget.source.id,
      ),
    );
  }
}
