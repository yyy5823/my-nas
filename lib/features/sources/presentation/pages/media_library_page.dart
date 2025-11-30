import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/sources/presentation/widgets/folder_picker_sheet.dart';

class MediaLibraryPage extends ConsumerWidget {
  const MediaLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: MediaType.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('媒体库'),
          bottom: TabBar(
            isScrollable: true,
            tabs: MediaType.values.map((type) {
              return Tab(
                icon: Icon(_getMediaTypeIcon(type)),
                text: type.displayName,
              );
            }).toList(),
          ),
        ),
        body: TabBarView(
          children: MediaType.values.map((type) {
            return _MediaTypeTab(mediaType: type);
          }).toList(),
        ),
      ),
    );
  }

  IconData _getMediaTypeIcon(MediaType type) {
    return switch (type) {
      MediaType.video => Icons.movie_outlined,
      MediaType.music => Icons.music_note_outlined,
      MediaType.photo => Icons.photo_library_outlined,
      MediaType.comic => Icons.collections_outlined,
      MediaType.book => Icons.book_outlined,
      MediaType.note => Icons.note_outlined,
    };
  }
}

class _MediaTypeTab extends ConsumerWidget {
  const _MediaTypeTab({required this.mediaType});

  final MediaType mediaType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(mediaLibraryConfigProvider);
    final sourcesAsync = ref.watch(sourcesProvider);
    final connections = ref.watch(activeConnectionsProvider);

    return configAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('加载失败: $e')),
      data: (config) {
        final paths = config.getPathsForType(mediaType);

        return sourcesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('加载失败: $e')),
          data: (sources) {
            if (sources.isEmpty) {
              return _buildNoSourcesState(context);
            }

            return Column(
              children: [
                // 添加按钮
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _addPath(context, ref, sources, connections),
                      icon: const Icon(Icons.add),
                      label: Text('添加${mediaType.displayName}目录'),
                    ),
                  ),
                ),

                // 目录列表
                if (paths.isEmpty)
                  Expanded(child: _buildEmptyState(context))
                else
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: paths.length,
                      itemBuilder: (context, index) {
                        final path = paths[index];
                        final source = sources.firstWhere(
                          (s) => s.id == path.sourceId,
                          orElse: () => SourceEntity(
                            name: '未知源',
                            type: SourceType.synology,
                            host: '',
                            username: '',
                          ),
                        );
                        final connection = connections[path.sourceId];

                        return _PathCard(
                          path: path,
                          source: source,
                          connection: connection,
                          mediaType: mediaType,
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildNoSourcesState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '尚未添加任何源',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '请先在设置中添加 NAS 或其他源',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getEmptyIcon(),
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '未配置${mediaType.displayName}目录',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '点击上方按钮添加目录',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getEmptyIcon() {
    return switch (mediaType) {
      MediaType.video => Icons.video_library_outlined,
      MediaType.music => Icons.library_music_outlined,
      MediaType.photo => Icons.photo_library_outlined,
      MediaType.comic => Icons.collections_bookmark_outlined,
      MediaType.book => Icons.library_books_outlined,
      MediaType.note => Icons.sticky_note_2_outlined,
    };
  }

  void _addPath(
    BuildContext context,
    WidgetRef ref,
    List<SourceEntity> sources,
    Map<String, SourceConnection> connections,
  ) {
    // 过滤出已连接的源
    final connectedSources = sources.where((s) {
      final conn = connections[s.id];
      return conn?.status == SourceStatus.connected;
    }).toList();

    if (connectedSources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('没有已连接的源，请先连接一个源'),
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FolderPickerSheet(
        sources: connectedSources,
        connections: connections,
        onSelect: (sourceId, path, name) async {
          final newPath = MediaLibraryPath(
            sourceId: sourceId,
            path: path,
            name: name,
          );
          await ref
              .read(mediaLibraryConfigProvider.notifier)
              .addPath(mediaType, newPath);
          if (context.mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已添加目录: $path')),
            );
          }
        },
      ),
    );
  }
}

class _PathCard extends ConsumerWidget {
  const _PathCard({
    required this.path,
    required this.source,
    required this.connection,
    required this.mediaType,
  });

  final MediaLibraryPath path;
  final SourceEntity source;
  final SourceConnection? connection;
  final MediaType mediaType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = connection?.status == SourceStatus.connected;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (path.isEnabled ? AppColors.primary : Colors.grey)
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.folder,
            color: path.isEnabled ? AppColors.primary : Colors.grey,
          ),
        ),
        title: Text(
          path.displayName,
          style: TextStyle(
            color: path.isEnabled ? null : Colors.grey,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              path.path,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                Icon(
                  isConnected ? Icons.cloud_done : Icons.cloud_off,
                  size: 12,
                  color: isConnected ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 4),
                Text(
                  source.displayName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isConnected ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            switch (value) {
              case 'toggle':
                await ref
                    .read(mediaLibraryConfigProvider.notifier)
                    .togglePath(mediaType, path.id, !path.isEnabled);
                break;
              case 'delete':
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('删除目录'),
                    content: Text('确定要从媒体库中移除 "${path.displayName}" 吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await ref
                      .read(mediaLibraryConfigProvider.notifier)
                      .removePath(mediaType, path.id);
                }
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'toggle',
              child: Row(
                children: [
                  Icon(path.isEnabled ? Icons.visibility_off : Icons.visibility),
                  const SizedBox(width: 12),
                  Text(path.isEnabled ? '停用' : '启用'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 12),
                  Text('删除', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
