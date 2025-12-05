import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';

abstract final class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: _lightColorScheme,
        scaffoldBackgroundColor: AppColors.lightBackground,
        appBarTheme: _lightAppBarTheme,
        cardTheme: _lightCardTheme,
        elevatedButtonTheme: _elevatedButtonTheme,
        outlinedButtonTheme: _outlinedButtonTheme,
        textButtonTheme: _textButtonTheme,
        inputDecorationTheme: _lightInputDecorationTheme,
        dividerTheme: _lightDividerTheme,
        navigationBarTheme: _lightNavigationBarTheme,
        navigationRailTheme: _lightNavigationRailTheme,
        bottomSheetTheme: _lightBottomSheetTheme,
        dialogTheme: _lightDialogTheme,
        snackBarTheme: _snackBarTheme,
        listTileTheme: _lightListTileTheme,
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: _darkColorScheme,
        scaffoldBackgroundColor: AppColors.darkBackground,
        appBarTheme: _darkAppBarTheme,
        cardTheme: _darkCardTheme,
        elevatedButtonTheme: _elevatedButtonTheme,
        outlinedButtonTheme: _outlinedButtonTheme,
        textButtonTheme: _textButtonTheme,
        inputDecorationTheme: _darkInputDecorationTheme,
        dividerTheme: _darkDividerTheme,
        navigationBarTheme: _darkNavigationBarTheme,
        navigationRailTheme: _darkNavigationRailTheme,
        bottomSheetTheme: _darkBottomSheetTheme,
        dialogTheme: _darkDialogTheme,
        snackBarTheme: _snackBarTheme,
        listTileTheme: _darkListTileTheme,
      );

  // Color Schemes
  static const ColorScheme _lightColorScheme = ColorScheme.light(
    primary: AppColors.primary,
    primaryContainer: AppColors.primaryLight,
    onPrimaryContainer: AppColors.primaryDark,
    secondary: AppColors.secondary,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.secondaryLight,
    onSecondaryContainer: AppColors.secondaryDark,
    tertiary: AppColors.tertiary,
    onTertiary: Colors.white,
    tertiaryContainer: AppColors.tertiaryLight,
    onTertiaryContainer: AppColors.tertiaryDark,
    error: AppColors.error,
    onSurface: AppColors.lightOnSurface,
    surfaceContainerHighest: AppColors.lightSurfaceVariant,
    onSurfaceVariant: AppColors.lightOnSurfaceVariant,
    outline: AppColors.lightOutline,
    outlineVariant: AppColors.lightOutlineVariant,
  );

  static const ColorScheme _darkColorScheme = ColorScheme.dark(
    primary: AppColors.primaryLight,
    onPrimary: AppColors.darkBackground,
    primaryContainer: AppColors.primary,
    onPrimaryContainer: Colors.white,
    secondary: AppColors.secondaryLight,
    onSecondary: AppColors.darkBackground,
    secondaryContainer: AppColors.secondary,
    onSecondaryContainer: Colors.white,
    tertiary: AppColors.tertiaryLight,
    onTertiary: AppColors.darkBackground,
    tertiaryContainer: AppColors.tertiary,
    onTertiaryContainer: Colors.white,
    error: AppColors.errorLight,
    onError: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    onSurface: AppColors.darkOnSurface,
    surfaceContainerHighest: AppColors.darkSurfaceVariant,
    onSurfaceVariant: AppColors.darkOnSurfaceVariant,
    outline: AppColors.darkOutline,
    outlineVariant: AppColors.darkOutlineVariant,
  );

  // AppBar
  static const AppBarTheme _lightAppBarTheme = AppBarTheme(
    elevation: 0,
    scrolledUnderElevation: 1,
    backgroundColor: AppColors.lightSurface,
    foregroundColor: AppColors.lightOnSurface,
    surfaceTintColor: Colors.transparent,
  );

  static const AppBarTheme _darkAppBarTheme = AppBarTheme(
    elevation: 0,
    scrolledUnderElevation: 1,
    backgroundColor: AppColors.darkSurface,
    foregroundColor: AppColors.darkOnSurface,
    surfaceTintColor: Colors.transparent,
  );

  // Card
  static final CardThemeData _lightCardTheme = CardThemeData(
    elevation: 0,
    color: AppColors.lightSurface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.borderRadiusMd,
      side: const BorderSide(color: AppColors.lightOutlineVariant),
    ),
  );

  static final CardThemeData _darkCardTheme = CardThemeData(
    elevation: 0,
    color: AppColors.darkSurface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.borderRadiusMd,
      side: const BorderSide(color: AppColors.darkOutlineVariant),
    ),
  );

  // Buttons
  static final ElevatedButtonThemeData _elevatedButtonTheme =
      ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      elevation: 0,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadiusSm,
      ),
    ),
  );

  static final OutlinedButtonThemeData _outlinedButtonTheme =
      OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadiusSm,
      ),
    ),
  );

  static final TextButtonThemeData _textButtonTheme = TextButtonThemeData(
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadiusSm,
      ),
    ),
  );

  // Input
  static final InputDecorationTheme _lightInputDecorationTheme =
      InputDecorationTheme(
    filled: true,
    fillColor: AppColors.lightSurfaceVariant,
    border: OutlineInputBorder(
      borderRadius: AppRadius.borderRadiusSm,
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: AppRadius.borderRadiusSm,
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: AppRadius.borderRadiusSm,
      borderSide: const BorderSide(color: AppColors.primary, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: AppRadius.borderRadiusSm,
      borderSide: const BorderSide(color: AppColors.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: AppRadius.borderRadiusSm,
      borderSide: const BorderSide(color: AppColors.error, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
  );

  static final InputDecorationTheme _darkInputDecorationTheme =
      InputDecorationTheme(
    filled: true,
    fillColor: AppColors.darkSurfaceVariant,
    border: OutlineInputBorder(
      borderRadius: AppRadius.borderRadiusSm,
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: AppRadius.borderRadiusSm,
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: AppRadius.borderRadiusSm,
      borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: AppRadius.borderRadiusSm,
      borderSide: const BorderSide(color: AppColors.errorLight),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: AppRadius.borderRadiusSm,
      borderSide: const BorderSide(color: AppColors.errorLight, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
  );

  // Divider
  static const DividerThemeData _lightDividerTheme = DividerThemeData(
    color: AppColors.lightOutlineVariant,
    thickness: 1,
    space: 1,
  );

  static const DividerThemeData _darkDividerTheme = DividerThemeData(
    color: AppColors.darkOutlineVariant,
    thickness: 1,
    space: 1,
  );

  // Navigation Bar (Bottom)
  static const NavigationBarThemeData _lightNavigationBarTheme =
      NavigationBarThemeData(
    elevation: 0,
    backgroundColor: AppColors.lightSurface,
    surfaceTintColor: Colors.transparent,
    indicatorColor: AppColors.primaryLight,
  );

  static const NavigationBarThemeData _darkNavigationBarTheme =
      NavigationBarThemeData(
    elevation: 0,
    backgroundColor: AppColors.darkSurface,
    surfaceTintColor: Colors.transparent,
    indicatorColor: AppColors.primary,
  );

  // Navigation Rail (Desktop)
  static const NavigationRailThemeData _lightNavigationRailTheme =
      NavigationRailThemeData(
    elevation: 0,
    backgroundColor: AppColors.lightSurface,
    indicatorColor: AppColors.primaryLight,
  );

  static const NavigationRailThemeData _darkNavigationRailTheme =
      NavigationRailThemeData(
    elevation: 0,
    backgroundColor: AppColors.darkSurface,
    indicatorColor: AppColors.primary,
  );

  // Bottom Sheet
  static final BottomSheetThemeData _lightBottomSheetTheme =
      BottomSheetThemeData(
    backgroundColor: AppColors.lightSurface,
    surfaceTintColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
  );

  static final BottomSheetThemeData _darkBottomSheetTheme =
      BottomSheetThemeData(
    backgroundColor: AppColors.darkSurface,
    surfaceTintColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
  );

  // Dialog
  static final DialogThemeData _lightDialogTheme = DialogThemeData(
    backgroundColor: AppColors.lightSurface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.borderRadiusLg,
    ),
  );

  static final DialogThemeData _darkDialogTheme = DialogThemeData(
    backgroundColor: AppColors.darkSurface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.borderRadiusLg,
    ),
  );

  // SnackBar
  static final SnackBarThemeData _snackBarTheme = SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.borderRadiusSm,
    ),
  );

  // ListTile
  static final ListTileThemeData _lightListTileTheme = ListTileThemeData(
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.borderRadiusSm,
    ),
  );

  static final ListTileThemeData _darkListTileTheme = ListTileThemeData(
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.borderRadiusSm,
    ),
  );
}
