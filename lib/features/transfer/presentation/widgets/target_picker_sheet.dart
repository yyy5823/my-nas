import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';

/// 上传目标选择结果
class UploadTarget {
  const UploadTarget({
    required this.sourceId,
    required this.sourceName,
    required this.path,
    required this.pathDisplayName,
  });

  /// 目标源 ID
  final String sourceId;

  /// 目标源名称
  final String sourceName;

  /// 目标路径
  final String path;

  /// 路径显示名称
  final String pathDisplayName;
}

/// 上传目标选择器
class TargetPickerSheet extends ConsumerStatefulWidget {
  const TargetPickerSheet({
    super.key,
    required this.mediaType,
    this.title = '选择上传目标',
  });

  /// 媒体类型（用于筛选对应的媒体库）
  final MediaType mediaType;

  /// 标题
  final String title;

  /// 显示选择器
  static Future<UploadTarget?> show(
    BuildContext context, {
    required MediaType mediaType,
    String title = '选择上传目标',
  }) {
    return showModalBottomSheet<UploadTarget>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => TargetPickerSheet(
        mediaType: mediaType,
        title: title,
      ),
    );
  }

  @override
  ConsumerState<TargetPickerSheet> createState() => _TargetPickerSheetState();
}

class _TargetPickerSheetState extends ConsumerState<TargetPickerSheet> {
  String? _selectedSourceId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final connections = ref.watch(activeConnectionsProvider);
    final libraryConfig = ref.watch(mediaLibraryConfigProvider);

    // 获取已连接的存储类源（排除本机源）
    final storageConnections = connections.entries
        .where((e) =>
            e.value.status == SourceStatus.connected &&
            e.value.source.type.category.isStorageCategory &&
            !_isLocalSource(e.value.source.type))
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // 拖动手柄
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 标题
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  widget.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(),

          // 内容
          Expanded(
            child: storageConnections.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: storageConnections.length,
                    itemBuilder: (context, index) {
                      final entry = storageConnections[index];
                      return _buildSourceItem(
                        context,
                        entry.value,
                        libraryConfig.valueOrNull,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  bool _isLocalSource(SourceType type) {
    return type == SourceType.mobileGallery ||
        type == SourceType.mobileMusic ||
        type == SourceType.mobileFiles ||
        type == SourceType.local;
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '没有可用的上传目标',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '请先连接到 NAS 或云存储',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceItem(
    BuildContext context,
    SourceConnection connection,
    MediaLibraryConfig? libraryConfig,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final source = connection.source;
    final isExpanded = _selectedSourceId == source.id;

    // 获取该源下对应媒体类型的媒体库
    final libraries = libraryConfig
            ?.getPathsForType(widget.mediaType)
            .where((MediaLibraryPath lib) => lib.sourceId == source.id)
            .toList() ??
        [];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          // 源标题
          ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                source.type.icon,
                color: colorScheme.primary,
                size: 22,
              ),
            ),
            title: Text(source.name),
            subtitle: Text(
              source.host,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
            ),
            onTap: () {
              setState(() {
                _selectedSourceId = isExpanded ? null : source.id;
              });
            },
          ),

          // 展开的媒体库列表
          if (isExpanded) ...[
            const Divider(height: 1),
            if (libraries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '该源没有配置${_getMediaTypeName(widget.mediaType)}媒体库',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ...libraries.map((MediaLibraryPath lib) => _buildLibraryItem(context, source, lib)),

            // 选择自定义路径选项
            ListTile(
              leading: const SizedBox(width: 24),
              title: const Text('选择其他目录...'),
              trailing: const Icon(Icons.folder_open, size: 20),
              onTap: () => _showDirectoryPicker(context, connection),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLibraryItem(
    BuildContext context,
    SourceEntity source,
    MediaLibraryPath library,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      leading: const SizedBox(width: 24),
      title: Text(library.displayName),
      subtitle: Text(
        library.path,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        final target = UploadTarget(
          sourceId: source.id,
          sourceName: source.name,
          path: library.path,
          pathDisplayName: library.displayName,
        );
        Navigator.pop(context, target);
      },
    );
  }

  Future<void> _showDirectoryPicker(
    BuildContext context,
    SourceConnection connection,
  ) async {
    // TODO: 实现目录选择器
    // 目前先使用简单的文本输入
    final path = await showDialog<String>(
      context: context,
      builder: (context) => _DirectoryInputDialog(
        source: connection.source,
      ),
    );

    if (path != null && path.isNotEmpty && mounted) {
      final target = UploadTarget(
        sourceId: connection.source.id,
        sourceName: connection.source.name,
        path: path,
        pathDisplayName: path,
      );
      Navigator.pop(context, target);
    }
  }

  String _getMediaTypeName(MediaType type) => switch (type) {
        MediaType.photo => '照片',
        MediaType.music => '音乐',
        MediaType.video => '视频',
        MediaType.book => '图书',
        MediaType.comic => '漫画',
        MediaType.note => '笔记',
      };
}

/// 目录输入对话框
class _DirectoryInputDialog extends StatefulWidget {
  const _DirectoryInputDialog({required this.source});

  final SourceEntity source;

  @override
  State<_DirectoryInputDialog> createState() => _DirectoryInputDialogState();
}

class _DirectoryInputDialogState extends State<_DirectoryInputDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('输入目标路径'),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(
          hintText: '例如：/photos/upload',
          helperText: '上传到 ${widget.source.name}',
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
