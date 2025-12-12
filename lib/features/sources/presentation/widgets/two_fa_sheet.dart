import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';

/// 二次验证弹框结果
class TwoFAResult {
  const TwoFAResult({
    required this.otpCode,
    required this.rememberDevice,
  });

  final String otpCode;
  final bool rememberDevice;
}

/// 显示二次验证底部弹框
///
/// 返回 [TwoFAResult]，如果用户取消则返回 null
Future<TwoFAResult?> showTwoFASheet(
  BuildContext context, {
  bool initialRememberDevice = false,
  String? sourceName,
}) async => showModalBottomSheet<TwoFAResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: false,
    enableDrag: true,
    builder: (context) => _TwoFASheet(
      initialRememberDevice: initialRememberDevice,
      sourceName: sourceName,
    ),
  );

class _TwoFASheet extends StatefulWidget {
  const _TwoFASheet({
    this.initialRememberDevice = false,
    this.sourceName,
  });

  final bool initialRememberDevice;
  final String? sourceName;

  @override
  State<_TwoFASheet> createState() => _TwoFASheetState();
}

class _TwoFASheetState extends State<_TwoFASheet> with SingleTickerProviderStateMixin {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  late bool _rememberDevice;
  bool _hasError = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _rememberDevice = widget.initialRememberDevice;
    _controllers = List.generate(6, (_) => TextEditingController());
    _focusNodes = List.generate(6, (_) => FocusNode());

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    );
    _animationController.forward();

    // 自动聚焦第一个输入框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    _animationController.dispose();
    super.dispose();
  }

  String get _otpCode => _controllers.map((c) => c.text).join();

  void _onCodeChanged(int index, String value) {
    if (_hasError) {
      setState(() => _hasError = false);
    }

    if (value.length == 1 && index < 5) {
      // 移动到下一个输入框
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      // 删除时移动到上一个输入框
      _focusNodes[index - 1].requestFocus();
    }

    // 检查是否完成
    if (_otpCode.length == 6) {
      _submit();
    }
  }

  void _onKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_controllers[index].text.isEmpty && index > 0) {
        _focusNodes[index - 1].requestFocus();
        _controllers[index - 1].clear();
      }
    }
  }

  void _submit() {
    final code = _otpCode;
    if (code.length != 6) {
      setState(() => _hasError = true);
      HapticFeedback.heavyImpact();
      return;
    }
    Navigator.pop(
      context,
      TwoFAResult(
        otpCode: code,
        rememberDevice: _rememberDevice,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: DraggableScrollableSheet(
        initialChildSize: 0.58,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        builder: (context, scrollController) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurface.withValues(alpha: 0.95)
                    : Colors.white.withValues(alpha: 0.95),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(
                  color: isDark
                      ? AppColors.darkOutline.withValues(alpha: 0.2)
                      : AppColors.lightOutline.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  // 拖动指示器
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[600] : Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // 内容
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      children: [
                        // 安全图标
                        Center(
                          child: ScaleTransition(
                            scale: _scaleAnimation,
                            child: Container(
                              width: 80,
                              height: 80,
                              margin: const EdgeInsets.only(bottom: 20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppColors.accent,
                                    AppColors.accent.withValues(alpha: 0.7),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.accent.withValues(alpha: 0.3),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.shield_rounded,
                                size: 40,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        // 标题
                        Text(
                          '二次验证',
                          style: context.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        // 副标题
                        Text(
                          widget.sourceName != null
                              ? '正在连接「${widget.sourceName}」\n请输入验证器应用中的验证码'
                              : '请输入验证器应用中的验证码',
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        // PIN 码输入框
                        _buildPinCodeFields(isDark),
                        if (_hasError) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, color: AppColors.error, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '请输入完整的 6 位验证码',
                                style: context.textTheme.bodySmall?.copyWith(color: AppColors.error),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 28),
                        // 记住设备选项
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                                : AppColors.lightSurfaceVariant.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _rememberDevice
                                      ? AppColors.accent.withValues(alpha: 0.15)
                                      : (isDark
                                          ? AppColors.darkSurfaceVariant
                                          : AppColors.lightSurfaceVariant),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.devices_rounded,
                                  color: _rememberDevice
                                      ? AppColors.accent
                                      : (isDark
                                          ? AppColors.darkOnSurfaceVariant
                                          : AppColors.lightOnSurfaceVariant),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '记住此设备',
                                      style: context.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                                      ),
                                    ),
                                    Text(
                                      '下次登录时跳过二次验证',
                                      style: context.textTheme.bodySmall?.copyWith(
                                        color: isDark
                                            ? AppColors.darkOnSurfaceVariant
                                            : AppColors.lightOnSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch.adaptive(
                                value: _rememberDevice,
                                onChanged: (value) => setState(() => _rememberDevice = value),
                                activeTrackColor: AppColors.accent.withValues(alpha: 0.5),
                                thumbColor: WidgetStateProperty.resolveWith((states) {
                                  if (states.contains(WidgetState.selected)) {
                                    return AppColors.accent;
                                  }
                                  return null;
                                }),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        // 验证按钮
                        FilledButton(
                          onPressed: _submit,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            backgroundColor: AppColors.accent,
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.verified_user_rounded, size: 20),
                              SizedBox(width: 8),
                              Text(
                                '验证',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 取消按钮
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          child: Text(
                            '取消',
                            style: TextStyle(
                              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                            ),
                          ),
                        ),
                        // 底部安全区域
                        SizedBox(height: MediaQuery.of(context).padding.bottom),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPinCodeFields(bool isDark) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) => Container(
          width: 48,
          height: 56,
          margin: EdgeInsets.only(
            left: index == 0 ? 0 : 8,
            right: index == 2 ? 8 : 0, // 在第3位后加点间距
          ),
          child: KeyboardListener(
            focusNode: FocusNode(),
            onKeyEvent: (event) => _onKeyEvent(index, event),
            child: TextField(
              controller: _controllers[index],
              focusNode: _focusNodes[index],
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 1,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: _focusNodes[index].hasFocus
                    ? (isDark
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.primary.withValues(alpha: 0.08))
                    : (isDark
                        ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                        : AppColors.lightSurfaceVariant.withValues(alpha: 0.5)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: _hasError
                        ? AppColors.error
                        : (isDark
                            ? AppColors.darkOutline.withValues(alpha: 0.3)
                            : AppColors.lightOutline.withValues(alpha: 0.3)),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: _hasError ? AppColors.error : AppColors.primary,
                    width: 2,
                  ),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(1),
              ],
              onChanged: (value) => _onCodeChanged(index, value),
            ),
          ),
        )),
    );
}
