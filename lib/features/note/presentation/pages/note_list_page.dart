import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/note/data/services/markdown_parser.dart';
import 'package:my_nas/features/note/domain/entities/note_item.dart';
import 'package:my_nas/features/note/presentation/pages/note_editor_page.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/empty_widget.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';
import 'package:my_nas/shared/widgets/loading_widget.dart';
import 'package:my_nas/shared/widgets/media_setup_widget.dart';

/// 笔记列表状态
final noteListProvider =
    StateNotifierProvider<NoteListNotifier, NoteListState>(
        (ref) => NoteListNotifier(ref));

sealed class NoteListState {}

class NoteListLoading extends NoteListState {
  NoteListLoading({this.progress = 0, this.currentFolder});
  final double progress;
  final String? currentFolder;
}

class NoteListNotConnected extends NoteListState {}

class NoteListLoaded extends NoteListState {
  NoteListLoaded(this.notes);
  final List<NoteItem> notes;
}

class NoteListError extends NoteListState {
  NoteListError(this.message);
  final String message;
}

class NoteListNotifier extends StateNotifier<NoteListState> {
  NoteListNotifier(this._ref) : super(NoteListLoading()) {
    loadNotes();
  }

  final Ref _ref;

  Future<void> loadNotes({int maxDepth = 3}) async {
    state = NoteListLoading();

    final connections = _ref.read(activeConnectionsProvider);
    final configAsync = _ref.read(mediaLibraryConfigProvider);

    // 等待配置加载完成
    MediaLibraryConfig? config = configAsync.valueOrNull;
    if (config == null) {
      state = NoteListLoading(progress: 0, currentFolder: '正在加载配置...');

      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final updated = _ref.read(mediaLibraryConfigProvider);
        config = updated.valueOrNull;
        if (config != null) break;

        if (updated.hasError) {
          state = NoteListError('加载媒体库配置失败');
          return;
        }
      }

      if (config == null) {
        state = NoteListLoaded([]);
        return;
      }
    }

    // 获取已启用的笔记路径
    final notePaths = config.getEnabledPathsForType(MediaType.note);

    if (notePaths.isEmpty) {
      state = NoteListLoaded([]);
      return;
    }

    // 过滤出已连接的路径
    final connectedPaths = notePaths.where((path) {
      final conn = connections[path.sourceId];
      return conn?.status == SourceStatus.connected;
    }).toList();

    if (connectedPaths.isEmpty) {
      state = NoteListNotConnected();
      return;
    }

    try {
      final noteFiles = <FileItem>[];
      final sourceIds = <String, String>{};  // 文件路径 -> sourceId 映射

      for (var i = 0; i < connectedPaths.length; i++) {
        final mediaPath = connectedPaths[i];
        final connection = connections[mediaPath.sourceId];
        if (connection == null) continue;

        state = NoteListLoading(
          progress: i / connectedPaths.length,
          currentFolder: mediaPath.displayName,
        );

        try {
          await _scanForNotes(
            connection.adapter.fileSystem,
            mediaPath.path,
            noteFiles,
            sourceIds,
            sourceId: mediaPath.sourceId,
            depth: 0,
            maxDepth: maxDepth,
          );
        } on Exception catch (e) {
          logger.w('扫描笔记文件夹失败: ${mediaPath.path} - $e');
        }
      }

      // 获取笔记详情（包括内容预览和任务解析）
      final notes = <NoteItem>[];
      for (final file in noteFiles) {
        try {
          final sourceId = sourceIds[file.path];
          final connection = sourceId != null ? connections[sourceId] : null;
          if (connection == null) continue;

          final url = await connection.adapter.fileSystem.getFileUrl(file.path);
          var note = NoteItem.fromFileItem(file, url);

          // 尝试获取内容预览
          final preview = await _fetchNotePreview(url);
          if (preview != null) {
            final tasks = MarkdownParser.parseTasks(preview);
            final type = MarkdownParser.detectNoteType(preview);
            final tags = MarkdownParser.extractTags(preview);
            note = note.copyWith(
              content: preview,
              tasks: tasks,
              type: type,
              tags: tags,
            );
          }
          notes.add(note);
        } on Exception {
          // 忽略无法加载的笔记
        }
      }

      // 按修改时间排序
      notes.sort((a, b) {
        final aTime = a.modifiedAt ?? DateTime(1970);
        final bTime = b.modifiedAt ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });

      logger.i('笔记扫描完成，共找到 ${notes.length} 个笔记');
      state = NoteListLoaded(notes);
    } on Exception catch (e) {
      state = NoteListError(e.toString());
    }
  }

  Future<void> _scanForNotes(
    NasFileSystem fs,
    String path,
    List<FileItem> notes,
    Map<String, String> sourceIds, {
    required String sourceId,
    required int depth,
    int maxDepth = 3,
  }) async {
    if (depth > maxDepth) return;

    try {
      final items = await fs.listDirectory(path);
      for (final item in items) {
        // 跳过隐藏文件夹和系统文件夹
        if (item.name.startsWith('.') ||
            item.name.startsWith('@') ||
            item.name == '#recycle') {
          continue;
        }

        if (item.isDirectory) {
          await _scanForNotes(
            fs,
            item.path,
            notes,
            sourceIds,
            sourceId: sourceId,
            depth: depth + 1,
            maxDepth: maxDepth,
          );
        } else if (_isNoteFile(item.name)) {
          notes.add(item);
          sourceIds[item.path] = sourceId;
        }
      }
    } on Exception catch (e) {
      logger.w('扫描子文件夹失败: $path - $e');
    }
  }

  bool _isNoteFile(String filename) {
    final lower = filename.toLowerCase();
    return lower.endsWith('.md') || lower.endsWith('.markdown') || lower.endsWith('.txt');
  }

  Future<String?> _fetchNotePreview(String url, {int maxBytes = 2000}) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'Range': 'bytes=0-$maxBytes'},
      );
      if (response.statusCode == 200 || response.statusCode == 206) {
        try {
          return utf8.decode(response.bodyBytes);
        } on FormatException {
          return String.fromCharCodes(response.bodyBytes);
        }
      }
    } on Exception {
      // 忽略预览加载失败
    }
    return null;
  }
}

class NoteListPage extends ConsumerWidget {
  const NoteListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(noteListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: Column(
        children: [
          _buildAppBar(context, ref, isDark),
          Expanded(
            child: switch (state) {
              NoteListLoading(:final progress, :final currentFolder) =>
                _buildLoadingState(progress, currentFolder),
              NoteListNotConnected() => const MediaSetupWidget(
                  mediaType: MediaType.note,
                  icon: Icons.note_outlined,
                ),
              NoteListError(:final message) => AppErrorWidget(
                  message: message,
                  onRetry: () => ref.read(noteListProvider.notifier).loadNotes(),
                ),
              NoteListLoaded(:final notes) when notes.isEmpty => const EmptyWidget(
                  icon: Icons.note_outlined,
                  title: '暂无笔记',
                  message: '在配置的目录中添加 Markdown 文件后将显示在这里',
                ),
              NoteListLoaded(:final notes) => _buildNoteList(context, ref, notes, isDark),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, WidgetRef ref, bool isDark) {
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Text(
                '笔记',
                style: context.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkOnSurface : null,
                ),
              ),
              const Spacer(),
              _buildIconButton(
                icon: Icons.refresh_rounded,
                onTap: () => ref.read(noteListProvider.notifier).loadNotes(),
                isDark: isDark,
                tooltip: '刷新',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isDark ? AppColors.darkOnSurfaceVariant : null,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState(double progress, String? currentFolder) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              value: progress > 0 ? progress : null,
              strokeWidth: 4,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '扫描笔记中...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (currentFolder != null) ...[
            const SizedBox(height: 8),
            Text(
              currentFolder,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
          if (progress > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${(progress * 100).toInt()}%',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoteList(
    BuildContext context,
    WidgetRef ref,
    List<NoteItem> notes,
    bool isDark,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: notes.length,
      itemBuilder: (context, index) => _NoteListTile(
        note: notes[index],
        isDark: isDark,
      ),
    );
  }
}

class _NoteListTile extends StatelessWidget {
  const _NoteListTile({
    required this.note,
    required this.isDark,
  });

  final NoteItem note;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
            : context.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppColors.darkOutline.withValues(alpha: 0.2)
              : context.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openNote(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 图标
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _getNoteTypeColor(note.type).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getNoteTypeIcon(note.type),
                    color: _getNoteTypeColor(note.type),
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // 内容
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题行
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              note.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppColors.darkOnSurface : null,
                              ),
                            ),
                          ),
                          if (note.hasTasks) ...[
                            const SizedBox(width: 8),
                            _buildTaskBadge(context),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      // 摘要
                      if (note.content != null)
                        Text(
                          MarkdownParser.extractSummary(note.content!),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: 8),
                      // 底部信息
                      Row(
                        children: [
                          // 标签
                          if (note.tags.isNotEmpty) ...[
                            ...note.tags.take(3).map((tag) => Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '#$tag',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                )),
                          ],
                          const Spacer(),
                          // 修改时间
                          if (note.modifiedAt != null)
                            Text(
                              _formatDate(note.modifiedAt!),
                              style: context.textTheme.labelSmall?.copyWith(
                                color: isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : context.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTaskBadge(BuildContext context) {
    final completed = note.completedTasks;
    final total = note.totalTasks;
    final hasOverdue = note.overdueTasks > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: hasOverdue
            ? Colors.red.withValues(alpha: 0.1)
            : (completed == total
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.orange.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasOverdue
                ? Icons.warning_rounded
                : (completed == total
                    ? Icons.check_circle_rounded
                    : Icons.pending_rounded),
            size: 14,
            color: hasOverdue
                ? Colors.red
                : (completed == total ? Colors.green : Colors.orange),
          ),
          const SizedBox(width: 4),
          Text(
            '$completed/$total',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: hasOverdue
                  ? Colors.red
                  : (completed == total ? Colors.green : Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getNoteTypeIcon(NoteType type) {
    return switch (type) {
      NoteType.normal => Icons.article_outlined,
      NoteType.todo => Icons.checklist_rounded,
      NoteType.diary => Icons.book_outlined,
      NoteType.meeting => Icons.groups_outlined,
    };
  }

  Color _getNoteTypeColor(NoteType type) {
    return switch (type) {
      NoteType.normal => AppColors.primary,
      NoteType.todo => Colors.orange,
      NoteType.diary => Colors.purple,
      NoteType.meeting => Colors.teal,
    };
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return '今天 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return '昨天';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} 天前';
    } else {
      return '${date.month}/${date.day}';
    }
  }

  void _openNote(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => NoteEditorPage(note: note),
      ),
    );
  }
}
