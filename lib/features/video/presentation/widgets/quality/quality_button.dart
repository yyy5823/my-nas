import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/presentation/providers/quality_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/quality/quality_selector_sheet.dart';

/// 清晰度快捷按钮（显示在视频控制栏）
class QualityButton extends ConsumerWidget {
  const QualityButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qualityState = ref.watch(qualityStateProvider);

    return GestureDetector(
      onTap: () => showQualitySelectorSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 清晰度标签
            Text(
              qualityState.currentQuality.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            // 加载指示器或转码标识
            if (qualityState.isLoading) ...[
              const SizedBox(width: 6),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                ),
              ),
            ] else if (qualityState.canSwitchQuality) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_drop_down,
                color: Colors.white70,
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 清晰度按钮（带边框样式，用于顶部栏）
class QualityButtonOutlined extends ConsumerWidget {
  const QualityButtonOutlined({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qualityState = ref.watch(qualityStateProvider);

    return GestureDetector(
      onTap: () => showQualitySelectorSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white54),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              qualityState.currentQuality.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
            if (qualityState.isLoading) ...[
              const SizedBox(width: 6),
              const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 清晰度图标按钮（仅图标）
class QualityIconButton extends ConsumerWidget {
  const QualityIconButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qualityState = ref.watch(qualityStateProvider);

    return IconButton(
      onPressed: () => showQualitySelectorSheet(context),
      icon: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(
            Icons.high_quality_rounded,
            color: Colors.white,
          ),
          if (qualityState.isLoading)
            const Positioned(
              right: -2,
              bottom: -2,
              child: SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                ),
              ),
            ),
        ],
      ),
      tooltip: '画质: ${qualityState.currentQuality.label}',
    );
  }
}
