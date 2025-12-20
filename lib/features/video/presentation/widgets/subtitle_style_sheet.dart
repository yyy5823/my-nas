import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/presentation/providers/subtitle_style_provider.dart';

/// 显示字幕样式设置
void showSubtitleStyleSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const SubtitleStyleSheet(),
  );
}

class SubtitleStyleSheet extends ConsumerWidget {
  const SubtitleStyleSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = ref.watch(subtitleStyleProvider);
    final notifier = ref.read(subtitleStyleProvider.notifier);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) => DecoratedBox(
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
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.text_fields_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '字幕样式',
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

            // 预览区域
            Container(
              margin: const EdgeInsets.all(AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  // 视频占位
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.grey[800]!, Colors.grey[900]!],
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.movie_rounded,
                        size: 48,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                  // 字幕预览
                  Positioned(
                    left: 0,
                    right: 0,
                    top: style.position == SubtitlePosition.top ? 8 : null,
                    bottom: style.position == SubtitlePosition.bottom
                        ? 8
                        : null,
                    child: style.position == SubtitlePosition.center
                        ? Positioned.fill(
                            child: Center(child: _buildSubtitlePreview(style)),
                          )
                        : _buildSubtitlePreview(style),
                  ),
                ],
              ),
            ),

            // 设置选项
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                children: [
                  // 字体大小
                  _buildSection(
                    context,
                    title: '字体大小',
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () =>
                              notifier.setFontSize(style.fontSize - 2),
                          icon: const Icon(Icons.remove_rounded),
                        ),
                        Expanded(
                          child: Slider(
                            value: style.fontSize,
                            min: 12,
                            max: 48,
                            divisions: 18,
                            label: '${style.fontSize.round()}',
                            onChanged: notifier.setFontSize,
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              notifier.setFontSize(style.fontSize + 2),
                          icon: const Icon(Icons.add_rounded),
                        ),
                        SizedBox(
                          width: 48,
                          child: Text(
                            '${style.fontSize.round()}',
                            textAlign: TextAlign.center,
                            style: context.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 字体颜色
                  _buildSection(
                    context,
                    title: '字体颜色',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: subtitleColors.map((color) {
                        final isSelected =
                            color.toARGB32() == style.fontColor.toARGB32();
                        return _ColorButton(
                          color: color,
                          isSelected: isSelected,
                          onTap: () => notifier.setFontColor(color),
                        );
                      }).toList(),
                    ),
                  ),

                  // 背景颜色
                  _buildSection(
                    context,
                    title: '背景颜色',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: subtitleBackgrounds.map((color) {
                        final isSelected =
                            color.toARGB32() ==
                            style.backgroundColor.toARGB32();
                        return _ColorButton(
                          color: color,
                          isSelected: isSelected,
                          onTap: () => notifier.setBackgroundColor(color),
                          showTransparent: color == Colors.transparent,
                        );
                      }).toList(),
                    ),
                  ),

                  // 位置
                  _buildSection(
                    context,
                    title: '字幕位置',
                    child: SegmentedButton<SubtitlePosition>(
                      segments: const [
                        ButtonSegment(
                          value: SubtitlePosition.top,
                          label: Text('顶部'),
                          icon: Icon(Icons.vertical_align_top_rounded),
                        ),
                        ButtonSegment(
                          value: SubtitlePosition.center,
                          label: Text('居中'),
                          icon: Icon(Icons.vertical_align_center_rounded),
                        ),
                        ButtonSegment(
                          value: SubtitlePosition.bottom,
                          label: Text('底部'),
                          icon: Icon(Icons.vertical_align_bottom_rounded),
                        ),
                      ],
                      selected: {style.position},
                      onSelectionChanged: (selected) {
                        notifier.setPosition(selected.first);
                      },
                    ),
                  ),

                  // 字体粗细
                  _buildSection(
                    context,
                    title: '字体粗细',
                    child: SegmentedButton<FontWeight>(
                      segments: const [
                        ButtonSegment(
                          value: FontWeight.normal,
                          label: Text('正常'),
                        ),
                        ButtonSegment(
                          value: FontWeight.w500,
                          label: Text('中等'),
                        ),
                        ButtonSegment(
                          value: FontWeight.bold,
                          label: Text('粗体'),
                        ),
                      ],
                      selected: {style.fontWeight},
                      onSelectionChanged: (selected) {
                        notifier.setFontWeight(selected.first);
                      },
                    ),
                  ),

                  // 描边设置
                  _buildSection(
                    context,
                    title: '描边效果',
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('启用描边'),
                          value: style.hasOutline,
                          onChanged: (value) {
                            notifier.setHasOutline(hasOutline: value);
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (style.hasOutline) ...[
                          Row(
                            children: [
                              Text('描边宽度', style: context.textTheme.bodyMedium),
                              Expanded(
                                child: Slider(
                                  value: style.outlineWidth,
                                  min: 0.5,
                                  max: 5,
                                  divisions: 9,
                                  label: style.outlineWidth.toStringAsFixed(1),
                                  onChanged: notifier.setOutlineWidth,
                                ),
                              ),
                              SizedBox(
                                width: 40,
                                child: Text(
                                  style.outlineWidth.toStringAsFixed(1),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // 字幕延时
                  _buildSection(
                    context,
                    title: '字幕延时',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '调整字幕与画面的同步，正值延后字幕，负值提前字幕',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () =>
                                  notifier.setDelay(style.delay - 0.5),
                              icon: const Icon(Icons.remove_rounded),
                            ),
                            Expanded(
                              child: Slider(
                                value: style.delay,
                                min: -10,
                                max: 10,
                                divisions: 40,
                                label: style.delayText,
                                onChanged: notifier.setDelay,
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  notifier.setDelay(style.delay + 0.5),
                              icon: const Icon(Icons.add_rounded),
                            ),
                            SizedBox(
                              width: 56,
                              child: Text(
                                style.delayText,
                                textAlign: TextAlign.center,
                                style: context.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: style.delay != 0
                                      ? AppColors.primary
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        // 快捷按钮
                        Wrap(
                          spacing: 8,
                          children: [
                            ActionChip(
                              label: const Text('-1s'),
                              onPressed: () => notifier.setDelay(style.delay - 1),
                            ),
                            ActionChip(
                              label: const Text('-0.5s'),
                              onPressed: () => notifier.setDelay(style.delay - 0.5),
                            ),
                            ActionChip(
                              label: const Text('重置'),
                              onPressed: () => notifier.setDelay(0),
                            ),
                            ActionChip(
                              label: const Text('+0.5s'),
                              onPressed: () => notifier.setDelay(style.delay + 0.5),
                            ),
                            ActionChip(
                              label: const Text('+1s'),
                              onPressed: () => notifier.setDelay(style.delay + 1),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 字幕底部距离
                  _buildSection(
                    context,
                    title: '字幕底部距离',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '调整字幕距离视频底部的距离',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () =>
                                  notifier.setBottomPadding(style.bottomPadding - 8),
                              icon: const Icon(Icons.remove_rounded),
                            ),
                            Expanded(
                              child: Slider(
                                value: style.bottomPadding,
                                min: 0,
                                max: 200,
                                divisions: 25,
                                label: '${style.bottomPadding.round()}px',
                                onChanged: notifier.setBottomPadding,
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  notifier.setBottomPadding(style.bottomPadding + 8),
                              icon: const Icon(Icons.add_rounded),
                            ),
                            SizedBox(
                              width: 56,
                              child: Text(
                                '${style.bottomPadding.round()}px',
                                textAlign: TextAlign.center,
                                style: context.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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

  Widget _buildSubtitlePreview(SubtitleStyle style) => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '这是字幕预览效果',
        style: TextStyle(
          fontSize: style.fontSize * 0.6, // 预览区域缩小显示
          color: style.fontColor,
          fontWeight: style.fontWeight,
          shadows: style.hasOutline
              ? [
                  Shadow(
                    color: style.outlineColor,
                    blurRadius: style.outlineWidth,
                    offset: const Offset(1, 1),
                  ),
                  Shadow(
                    color: style.outlineColor,
                    blurRadius: style.outlineWidth,
                    offset: const Offset(-1, -1),
                  ),
                ]
              : null,
        ),
      ),
    ),
  );

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required Widget child,
  }) => Padding(
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
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.showTransparent = false,
  });

  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  final bool showTransparent;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected
              ? AppColors.primary
              : Colors.grey.withValues(alpha: 0.3),
          width: isSelected ? 3 : 1,
        ),
      ),
      child: showTransparent
          ? CustomPaint(painter: _TransparentPainter())
          : isSelected
          ? Icon(
              Icons.check_rounded,
              color: color.computeLuminance() > 0.5
                  ? Colors.black
                  : Colors.white,
              size: 20,
            )
          : null,
    ),
  );
}

class _TransparentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    paint.color = Colors.grey[300]!;
    canvas.drawArc(rect, 0, 3.14159, true, paint);

    paint.color = Colors.grey[600]!;
    canvas.drawArc(rect, 3.14159, 3.14159, true, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
