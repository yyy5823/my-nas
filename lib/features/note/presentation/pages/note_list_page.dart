import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/connection/presentation/providers/connection_provider.dart';
import 'package:my_nas/features/note/data/services/markdown_parser.dart';
import 'package:my_nas/features/note/domain/entities/note_item.dart';
import 'package:my_nas/features/note/presentation/pages/note_editor_page.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/empty_widget.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';
import 'package:my_nas/shared/widgets/loading_widget.dart';
import 'package:my_nas/shared/widgets/not_connected_widget.dart';

/// 笔记列表状态
final noteListProvider =
    StateNotifierProvider<NoteListNotifier, NoteListState>(
        (ref) => NoteListNotifier(ref));

sealed class NoteListState {}

class NoteListLoading extends NoteListState {}

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

  Future<void> loadNotes() async {
    state = NoteListLoading();

    final adapter = _ref.read(activeAdapterProvider);
    if (adapter == null) {
      state = NoteListNotConnected();
      return;
    }

    try {
      final shares = await adapter.fileSystem.listDirectory('/');
      final noteFiles = <FileItem>[];

      for (final share in shares) {
        if (share.isDirectory) {
          try {
            await _scanForNotes(adapter.fileSystem, share.path, noteFiles, depth: 0);
          } on Exception {
            // 忽略无法访问的目录
          }
        }
      }

      // 获取笔记详情（包括内容预览和任务解析）
      final notes = <NoteItem>[];
      for (final file in noteFiles) {
        try {
          final url = await adapter.fileSystem.getFileUrl(file.path);
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

      state = NoteListLoaded(notes);
    } on Exception catch (e) {
      state = NoteListError(e.toString());
    }
  }

  Future<void> _scanForNotes(
    NasFileSystem fs,
    String path,
    List<FileItem> notes, {
    required int depth,
    int maxDepth = 3,
  }) async {
    if (depth > maxDepth) return;

    final items = await fs.listDirectory(path);
    for (final item in items) {
      if (item.isDirectory) {
        await _scanForNotes(fs, item.path, notes, depth: depth + 1);
      } else if (_isNoteFile(item.name)) {
        notes.add(item);
      }
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
              NoteListLoading() => const LoadingWidget(message: '扫描笔记中...'),
              NoteListNotConnected() => const NotConnectedWidget(
                  icon: Icons.note_outlined,
                  message: '连接到 NAS 后即可浏览和编辑笔记',
                ),
              NoteListError(:final message) => AppErrorWidget(
                  message: message,
                  onRetry: () => ref.read(noteListProvider.notifier).loadNotes(),
                ),
              NoteListLoaded(:final notes) when notes.isEmpty => const EmptyWidget(
                  icon: Icons.note_outlined,
                  title: '暂无笔记',
                  message: '在 NAS 中添加 Markdown 文件后将显示在这里',
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
