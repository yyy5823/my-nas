import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';

extension BuildContextExtensions on BuildContext {
  // Theme
  ThemeData get theme => Theme.of(this);
  ColorScheme get colorScheme => theme.colorScheme;
  TextTheme get textTheme => theme.textTheme;
  bool get isDarkMode => theme.brightness == Brightness.dark;

  // ============ 语义化颜色（根据亮暗模式自动调整）============

  /// 成功颜色
  Color get successColor => AppColors.success;

  /// 警告颜色
  Color get warningColor => AppColors.warning;

  /// 信息颜色（使用主题色）
  Color get infoColor => colorScheme.primary;

  /// 危险/删除颜色
  Color get dangerColor => AppColors.error;

  /// 评分星星颜色
  Color get starColor => AppColors.warning;

  /// 占位符/骨架屏背景色（亮暗模式自适应）
  Color get placeholderColor =>
      isDarkMode ? colorScheme.surfaceContainerHighest : const Color(0xFFE0E0E0);

  /// 占位符/骨架屏高亮色（亮暗模式自适应）
  Color get placeholderHighlightColor =>
      isDarkMode ? colorScheme.surface : const Color(0xFFF5F5F5);

  // MediaQuery
  MediaQueryData get mediaQuery => MediaQuery.of(this);
  Size get screenSize => mediaQuery.size;
  double get screenWidth => screenSize.width;
  double get screenHeight => screenSize.height;
  EdgeInsets get padding => mediaQuery.padding;
  EdgeInsets get viewInsets => mediaQuery.viewInsets;
  EdgeInsets get viewPadding => mediaQuery.viewPadding;

  // Responsive
  bool get isCompact => screenWidth < 600;
  bool get isMedium => screenWidth >= 600 && screenWidth < 840;
  bool get isExpanded => screenWidth >= 840 && screenWidth < 1200;
  bool get isLarge => screenWidth >= 1200 && screenWidth < 1600;
  bool get isExtraLarge => screenWidth >= 1600;

  bool get isMobile => isCompact;
  bool get isTablet => isMedium || isExpanded;
  bool get isDesktop => isLarge || isExtraLarge;

  // Navigation
  NavigatorState get navigator => Navigator.of(this);
  void pop<T>([T? result]) => navigator.pop(result);
  Future<T?> push<T>(Route<T> route) => navigator.push(route);

  // Snackbar
  ScaffoldMessengerState get scaffoldMessenger => ScaffoldMessenger.of(this);

  void showSnackBar(
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        action: action,
      ),
    );
  }

  void showErrorSnackBar(String message) {
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: colorScheme.error,
      ),
    );
  }

  void showSuccessSnackBar(String message) {
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: successColor,
      ),
    );
  }

  void showWarningSnackBar(String message) {
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: warningColor,
      ),
    );
  }
}
