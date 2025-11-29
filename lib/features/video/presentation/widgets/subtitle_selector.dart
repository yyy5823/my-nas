import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' show SubtitleTrack;
import 'package:my_nas/features/video/data/services/subtitle_service.dart';
import 'package:my_nas/features/video/presentation/providers/video_player_provider.dart';

/// 字幕选择器弹窗
class SubtitleSelectorSheet extends ConsumerWidget {
  const SubtitleSelectorSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final externalSubtitles = ref.watch(availableSubtitlesProvider);
    final currentSubtitle = ref.watch(currentSubtitleProvider);
    final playerNotifier = ref.read(videoPlayerControllerProvider.notifier);
    final embeddedSubtitles = playerNotifier.embeddedSubtitles;

    // 过滤出有效的内嵌字幕（排除 no 和 auto）
    final validEmbedded = embeddedSubtitles.where((s) => s.id != 'no' && s.id != 'auto').toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动条
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 标题
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.subtitles),
                const SizedBox(width: 12),
                Text(
                  '字幕选择',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // 字幕列表
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                // 关闭字幕选项
                _SubtitleTile(
                  title: '关闭字幕',
                  subtitle: '不显示任何字幕',
                  isSelected: currentSubtitle == null,
                  icon: Icons.subtitles_off,
                  onTap: () {
                    playerNotifier.setSubtitle(null);
                    Navigator.pop(context);
                  },
                ),

                // 外部字幕
                if (externalSubtitles.isNotEmpty) ...[
                  _SectionHeader(
                    title: '外部字幕',
                    count: externalSubtitles.length,
                  ),
                  ...externalSubtitles.map(
                    (sub) => _SubtitleTile(
                      title: sub.language ?? sub.name,
                      subtitle: sub.name,
                      isSelected: currentSubtitle?.path == sub.path,
                      icon: Icons.closed_caption,
                      onTap: () {
                        playerNotifier.setSubtitle(sub);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],

                // 内嵌字幕
                if (validEmbedded.isNotEmpty) ...[
                  _SectionHeader(
                    title: '内嵌字幕',
                    count: validEmbedded.length,
                  ),
                  ...validEmbedded.map(
                    (track) => _EmbeddedSubtitleTile(
                      track: track,
                      onTap: () {
                        playerNotifier.setEmbeddedSubtitleTrack(track);
                        ref.read(currentSubtitleProvider.notifier).state = null;
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],

                // 无字幕提示
                if (externalSubtitles.isEmpty && validEmbedded.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(
                          Icons.subtitles_off_outlined,
                          size: 48,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          '未找到字幕文件',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '请将 .srt, .ass, .vtt 字幕文件\n放在视频同目录下',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 分组标题
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
  });

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            Text(
              title,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      );
}

/// 字幕选项
class _SubtitleTile extends StatelessWidget {
  const _SubtitleTile({
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool isSelected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(
          icon,
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isSelected
            ? Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
              )
            : null,
        onTap: onTap,
      );
}

/// 内嵌字幕选项
class _EmbeddedSubtitleTile extends StatelessWidget {
  const _EmbeddedSubtitleTile({
    required this.track,
    required this.onTap,
  });

  final SubtitleTrack track;
  final VoidCallback onTap;

  String get _title {
    if (track.title != null && track.title!.isNotEmpty) {
      return track.title!;
    }
    if (track.language != null && track.language!.isNotEmpty) {
      return _languageToName(track.language!);
    }
    return '轨道 ${track.id}';
  }

  String _languageToName(String code) {
    const map = {
      'chi': '中文',
      'chs': '简体中文',
      'cht': '繁体中文',
      'zho': '中文',
      'eng': 'English',
      'jpn': '日本語',
      'kor': '한국어',
    };
    return map[code.toLowerCase()] ?? code;
  }

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(Icons.closed_caption_outlined),
        title: Text(_title),
        subtitle: Text(
          track.language ?? 'ID: ${track.id}',
          style: const TextStyle(fontSize: 12),
        ),
        onTap: onTap,
      );
}

/// 显示字幕选择器
void showSubtitleSelector(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const SubtitleSelectorSheet(),
  );
}
