import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/presentation/providers/video_player_provider.dart';

/// 显示音轨选择器
void showAudioTrackSelector(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => const AudioTrackSelector(),
  );
}

class AudioTrackSelector extends ConsumerWidget {
  const AudioTrackSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final playerNotifier = ref.watch(videoPlayerControllerProvider.notifier);
    final audioTracks = playerNotifier.audioTracks;
    final currentTrack = playerNotifier.currentAudioTrack;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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

          // 标题
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.audiotrack_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '音轨选择',
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // 音轨列表
          if (audioTracks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                children: [
                  Icon(
                    Icons.music_off_rounded,
                    size: 48,
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant
                        : AppColors.lightOnSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '无可用音轨',
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant
                          : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                itemCount: audioTracks.length,
                itemBuilder: (context, index) {
                  final track = audioTracks[index];
                  final isSelected = _isTrackSelected(track, currentTrack);
                  final trackInfo = _getTrackInfo(track);

                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : (isDark
                                ? AppColors.darkSurfaceVariant
                                : AppColors.lightSurfaceVariant),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.audiotrack_rounded,
                        color: isSelected
                            ? AppColors.primary
                            : (isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant),
                        size: 20,
                      ),
                    ),
                    title: Text(
                      trackInfo.title,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected ? AppColors.primary : null,
                      ),
                    ),
                    subtitle: trackInfo.subtitle != null
                        ? Text(
                            trackInfo.subtitle!,
                            style: context.textTheme.bodySmall?.copyWith(
                              color: isDark
                                  ? AppColors.darkOnSurfaceVariant
                                  : AppColors.lightOnSurfaceVariant,
                            ),
                          )
                        : null,
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.primary,
                          )
                        : null,
                    onTap: () {
                      playerNotifier.setAudioTrack(track);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  bool _isTrackSelected(AudioTrack track, AudioTrack? currentTrack) {
    if (currentTrack == null) return false;
    return track.id == currentTrack.id;
  }

  _TrackInfo _getTrackInfo(AudioTrack track) {
    String title = track.title ?? '音轨 ${track.id}';
    String? subtitle;

    // 解析语言
    if (track.language != null && track.language!.isNotEmpty) {
      final langName = _getLanguageName(track.language!);
      subtitle = langName;
    }

    // 添加编解码器信息
    if (track.codec != null && track.codec!.isNotEmpty) {
      final codecInfo = track.codec!.toUpperCase();
      if (subtitle != null) {
        subtitle = '$subtitle · $codecInfo';
      } else {
        subtitle = codecInfo;
      }
    }

    // 添加声道信息
    final channelCount = track.channelscount ?? track.audiochannels;
    if (channelCount != null && channelCount > 0) {
      final channelInfo = _getChannelInfo(channelCount);
      if (subtitle != null) {
        subtitle = '$subtitle · $channelInfo';
      } else {
        subtitle = channelInfo;
      }
    } else if (track.channels != null && track.channels!.isNotEmpty) {
      // 使用 channels 字符串描述（如 "stereo"）
      if (subtitle != null) {
        subtitle = '$subtitle · ${track.channels}';
      } else {
        subtitle = track.channels;
      }
    }

    return _TrackInfo(title: title, subtitle: subtitle);
  }

  String _getLanguageName(String langCode) {
    final code = langCode.toLowerCase();
    const langMap = {
      'chi': '中文',
      'chs': '简体中文',
      'cht': '繁体中文',
      'zho': '中文',
      'zh': '中文',
      'zh-cn': '简体中文',
      'zh-tw': '繁体中文',
      'zh-hk': '粤语',
      'eng': '英语',
      'en': '英语',
      'jpn': '日语',
      'ja': '日语',
      'kor': '韩语',
      'ko': '韩语',
      'fra': '法语',
      'fr': '法语',
      'deu': '德语',
      'de': '德语',
      'spa': '西班牙语',
      'es': '西班牙语',
      'ita': '意大利语',
      'it': '意大利语',
      'rus': '俄语',
      'ru': '俄语',
      'por': '葡萄牙语',
      'pt': '葡萄牙语',
      'ara': '阿拉伯语',
      'ar': '阿拉伯语',
      'hin': '印地语',
      'hi': '印地语',
      'tha': '泰语',
      'th': '泰语',
      'vie': '越南语',
      'vi': '越南语',
      'und': '未知语言',
    };
    return langMap[code] ?? langCode;
  }

  String _getChannelInfo(int channels) => switch (channels) {
        1 => '单声道',
        2 => '立体声',
        6 => '5.1声道',
        8 => '7.1声道',
        _ => '$channels声道',
      };
}

class _TrackInfo {
  const _TrackInfo({required this.title, this.subtitle});
  final String title;
  final String? subtitle;
}
