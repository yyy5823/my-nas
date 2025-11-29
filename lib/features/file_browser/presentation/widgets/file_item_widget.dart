import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

class FileItemWidget extends StatelessWidget {
  const FileItemWidget({
    required this.file,
    required this.onTap,
    super.key,
    this.onLongPress,
    this.isGridView = false,
  });

  final FileItem file;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isGridView;

  @override
  Widget build(BuildContext context) =>
      isGridView ? _buildGridItem(context) : _buildListItem(context);

  Widget _buildListItem(BuildContext context) => ListTile(
        leading: _buildIcon(context, size: 40),
        title: Text(
          file.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _getSubtitle(),
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: file.isDirectory
            ? const Icon(Icons.chevron_right)
            : Text(
                file.displaySize,
                style: context.textTheme.bodySmall,
              ),
        onTap: onTap,
        onLongPress: onLongPress,
      );

  Widget _buildGridItem(BuildContext context) => InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: AppRadius.borderRadiusMd,
        child: Container(
          padding: AppSpacing.paddingSm,
          decoration: BoxDecoration(
            borderRadius: AppRadius.borderRadiusMd,
            border: Border.all(
              color: context.colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: _buildIcon(context, size: 48),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: context.textTheme.bodySmall,
              ),
              if (!file.isDirectory) ...[
                const SizedBox(height: 2),
                Text(
                  file.displaySize,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _buildIcon(BuildContext context, {required double size}) {
    final iconData = _getIconData();
    final color = _getIconColor(context);

    return Icon(iconData, size: size, color: color);
  }

  IconData _getIconData() => switch (file.type) {
        FileType.folder => Icons.folder,
        FileType.image => Icons.image_outlined,
        FileType.video => Icons.video_file_outlined,
        FileType.audio => Icons.audio_file_outlined,
        FileType.document => Icons.description_outlined,
        FileType.archive => Icons.folder_zip_outlined,
        FileType.code => Icons.code,
        FileType.text => Icons.article_outlined,
        FileType.pdf => Icons.picture_as_pdf_outlined,
        FileType.epub || FileType.comic => Icons.menu_book_outlined,
        FileType.other => Icons.insert_drive_file_outlined,
      };

  Color _getIconColor(BuildContext context) => switch (file.type) {
        FileType.folder => context.colorScheme.primary,
        FileType.image => Colors.pink,
        FileType.video => Colors.red,
        FileType.audio => Colors.purple,
        FileType.document => Colors.blue,
        FileType.archive => Colors.amber,
        FileType.code => Colors.green,
        FileType.pdf => Colors.red.shade700,
        FileType.epub || FileType.comic => Colors.teal,
        _ => context.colorScheme.onSurfaceVariant,
      };

  String _getSubtitle() {
    if (file.isDirectory) return '文件夹';

    final parts = <String>[];
    if (file.modifiedTime != null) {
      parts.add(_formatDate(file.modifiedTime!));
    }
    return parts.join(' · ');
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
}
