import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract final class AppSpacing {
  // Base unit: 4px
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double xxxxl = 48;

  // App bar content padding (inside SafeArea)
  // iOS: Minimal vertical padding since iOS navigation bars are compact
  // Android: Slightly more padding for Material feel
  // Desktop: Most padding for mouse interaction areas
  static EdgeInsets get appBarContentPadding {
    if (kIsWeb) {
      return const EdgeInsets.symmetric(horizontal: 16, vertical: 8);
    }
    if (Platform.isIOS) {
      // iOS: 更紧凑的顶部间距，符合 iOS HIG
      return const EdgeInsets.symmetric(horizontal: 16, vertical: 4);
    }
    if (Platform.isAndroid) {
      // Android: Material Design 适中间距
      return const EdgeInsets.symmetric(horizontal: 12, vertical: 6);
    }
    // Desktop: 更多呼吸空间
    return const EdgeInsets.symmetric(horizontal: 16, vertical: 8);
  }

  // App bar vertical padding only (for simpler cases)
  static double get appBarVerticalPadding {
    if (kIsWeb) return sm;
    if (Platform.isIOS) return xs;
    if (Platform.isAndroid) return 6;
    return sm;
  }

  // App bar horizontal padding
  static double get appBarHorizontalPadding {
    if (kIsWeb) return lg;
    if (Platform.isIOS) return lg;
    if (Platform.isAndroid) return md;
    return lg;
  }

  // Common paddings
  static const EdgeInsets paddingXs = EdgeInsets.all(xs);
  static const EdgeInsets paddingSm = EdgeInsets.all(sm);
  static const EdgeInsets paddingMd = EdgeInsets.all(md);
  static const EdgeInsets paddingLg = EdgeInsets.all(lg);
  static const EdgeInsets paddingXl = EdgeInsets.all(xl);
  static const EdgeInsets paddingXxl = EdgeInsets.all(xxl);

  // Horizontal paddings
  static const EdgeInsets paddingHorizontalSm =
      EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets paddingHorizontalMd =
      EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets paddingHorizontalLg =
      EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets paddingHorizontalXl =
      EdgeInsets.symmetric(horizontal: xl);

  // Vertical paddings
  static const EdgeInsets paddingVerticalSm =
      EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets paddingVerticalMd =
      EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets paddingVerticalLg =
      EdgeInsets.symmetric(vertical: lg);
  static const EdgeInsets paddingVerticalXl =
      EdgeInsets.symmetric(vertical: xl);

  // Screen padding
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: md,
  );
}

abstract final class AppRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double full = 999;

  static const BorderRadius borderRadiusXs =
      BorderRadius.all(Radius.circular(xs));
  static const BorderRadius borderRadiusSm =
      BorderRadius.all(Radius.circular(sm));
  static const BorderRadius borderRadiusMd =
      BorderRadius.all(Radius.circular(md));
  static const BorderRadius borderRadiusLg =
      BorderRadius.all(Radius.circular(lg));
  static const BorderRadius borderRadiusXl =
      BorderRadius.all(Radius.circular(xl));
  static const BorderRadius borderRadiusXxl =
      BorderRadius.all(Radius.circular(xxl));
  static const BorderRadius borderRadiusFull =
      BorderRadius.all(Radius.circular(full));
}
