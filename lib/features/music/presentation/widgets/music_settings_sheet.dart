import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_settings_provider.dart';

/// 显示音乐设置
void showMusicSettingsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const MusicSettingsSheet(),
  );
}

class MusicSettingsSheet extends ConsumerWidget {
  const MusicSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(musicSettingsProvider);
    final notifier = ref.read(musicSettingsProvider.notifier);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // 拖拽指示器
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkOutline.withValues(alpha: 0.3)
                    : AppColors.lightOutline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // 标题栏
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.fileAudio.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.settings_rounded,
                      color: AppColors.fileAudio,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '播放设置',
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: notifier.reset,
                    child: const Text('重置'),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // 设置列表
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                children: [
                  // 播放模式
                  _buildSection(
                    context,
                    title: '默认播放模式',
                    child: SegmentedButton<PlayMode>(
                      segments: const [
                        ButtonSegment(
                          value: PlayMode.loop,
                          label: Text('列表循环'),
                          icon: Icon(Icons.repeat_rounded),
                        ),
                        ButtonSegment(
                          value: PlayMode.repeatOne,
                          label: Text('单曲循环'),
                          icon: Icon(Icons.repeat_one_rounded),
                        ),
                        ButtonSegment(
                          value: PlayMode.shuffle,
                          label: Text('随机播放'),
                          icon: Icon(Icons.shuffle_rounded),
                        ),
                      ],
                      selected: {settings.playMode},
                      onSelectionChanged: (selected) {
                        notifier.setPlayMode(selected.first);
                      },
                    ),
                  ),

                  const Divider(),

                  // 默认音量
                  _buildSection(
                    context,
                    title: '默认音量',
                    child: Row(
                      children: [
                        Icon(
                          settings.volume == 0
                              ? Icons.volume_off_rounded
                              : settings.volume < 0.5
                                  ? Icons.volume_down_rounded
                                  : Icons.volume_up_rounded,
                          color: isDark
                              ? AppColors.darkOnSurfaceVariant
                              : AppColors.lightOnSurfaceVariant,
                        ),
                        Expanded(
                          child: Slider(
                            value: settings.volume,
                            onChanged: notifier.setVolume,
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          child: Text(
                            '${(settings.volume * 100).round()}%',
                            textAlign: TextAlign.center,
                            style: context.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Divider(),

                  // 淡入淡出
                  _buildSection(
                    context,
                    title: '歌曲切换淡入淡出',
                    subtitle: '歌曲切换时平滑过渡',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableCrossfadeDurations.map((duration) {
                        final isSelected = duration == settings.crossfadeDuration;
                        return ChoiceChip(
                          label: Text(duration == 0 ? '关闭' : '${duration}秒'),
                          selected: isSelected,
                          onSelected: (_) => notifier.setCrossfadeDuration(duration),
                        );
                      }).toList(),
                    ),
                  ),

                  const Divider(),

                  // 无缝播放
                  SwitchListTile(
                    title: const Text('无缝播放'),
                    subtitle: const Text('播放列表歌曲之间无间隙'),
                    value: settings.gaplessPlayback,
                    onChanged: notifier.setGaplessPlayback,
                    contentPadding: EdgeInsets.zero,
                  ),

                  const Divider(),

                  // 显示歌词
                  SwitchListTile(
                    title: const Text('显示歌词'),
                    subtitle: const Text('在播放页面显示歌词（如果可用）'),
                    value: settings.showLyrics,
                    onChanged: notifier.setShowLyrics,
                    contentPadding: EdgeInsets.zero,
                  ),

                  const Divider(),

                  // 连接后自动播放
                  SwitchListTile(
                    title: const Text('连接后自动播放'),
                    subtitle: const Text('连接到 NAS 后自动继续上次播放'),
                    value: settings.autoPlayOnConnect,
                    onChanged: notifier.setAutoPlayOnConnect,
                    contentPadding: EdgeInsets.zero,
                  ),

                  SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    String? subtitle,
    required Widget child,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: context.textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.darkOnSurfaceVariant
                      : AppColors.lightOnSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
}
