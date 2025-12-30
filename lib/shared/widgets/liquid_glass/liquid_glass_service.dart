import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Liquid Glass 服务
///
/// 提供与原生 iOS 26 Liquid Glass 功能的通信
/// 包括：
/// - 检查 Liquid Glass 可用性
/// - 获取系统配置
/// - 触觉反馈
class LiquidGlassService {
  LiquidGlassService._();

  static final LiquidGlassService _instance = LiquidGlassService._();
  static LiquidGlassService get instance => _instance;

  static const _channel = MethodChannel('com.kkape.mynas/liquid_glass');

  bool? _isSupported;
  Map<String, dynamic>? _systemInfo;
  Map<String, dynamic>? _glassConfig;

  /// 是否支持 Liquid Glass (iOS 26+)
  Future<bool> get isSupported async {
    if (_isSupported != null) return _isSupported!;

    // 只在 iOS 上检查
    if (kIsWeb || !Platform.isIOS) {
      _isSupported = false;
      return false;
    }

    try {
      _isSupported = await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      _isSupported = false;
    }

    return _isSupported!;
  }

  /// 同步检查是否支持（需要先调用 init）
  bool get isSupportedSync => _isSupported ?? false;

  /// 获取系统信息
  Future<Map<String, dynamic>> getSystemInfo() async {
    if (_systemInfo != null) return _systemInfo!;

    if (kIsWeb || !Platform.isIOS) {
      return _getDefaultSystemInfo();
    }

    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>('getSystemInfo');
      _systemInfo = result?.cast<String, dynamic>() ?? _getDefaultSystemInfo();
    } on PlatformException {
      _systemInfo = _getDefaultSystemInfo();
    }

    return _systemInfo!;
  }

  /// 获取玻璃效果配置
  Future<LiquidGlassConfig> getGlassConfig() async {
    if (_glassConfig != null) {
      return LiquidGlassConfig.fromMap(_glassConfig!);
    }

    if (kIsWeb || !Platform.isIOS) {
      return LiquidGlassConfig.fallback();
    }

    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>('getGlassConfig');
      _glassConfig = result?.cast<String, dynamic>() ?? {};
      return LiquidGlassConfig.fromMap(_glassConfig!);
    } on PlatformException {
      return LiquidGlassConfig.fallback();
    }
  }

  /// 触觉反馈
  Future<void> hapticFeedback(HapticType type) async {
    if (kIsWeb || !Platform.isIOS) return;

    try {
      await _channel.invokeMethod('hapticFeedback', type.name);
    } on PlatformException {
      // 忽略错误
    }
  }

  /// 初始化服务（预加载配置）
  Future<void> init() async {
    await isSupported;
    await getSystemInfo();
    await getGlassConfig();
  }

  Map<String, dynamic> _getDefaultSystemInfo() => {
        'isLiquidGlassSupported': false,
        'iosVersion': '0.0',
        'deviceModel': 'Unknown',
        'iosMajorVersion': 0,
        'iosMinorVersion': 0,
        'reduceTransparency': false,
        'reduceMotion': false,
      };
}

/// 触觉反馈类型
enum HapticType {
  light,
  medium,
  heavy,
  selection,
  success,
  warning,
  error,
}

/// Liquid Glass 配置
class LiquidGlassConfig {
  const LiquidGlassConfig({
    required this.glassType,
    required this.supportsInteractive,
    required this.supportsMorphing,
    required this.supportsGlassEffectContainer,
    required this.recommendedCornerRadius,
    required this.navBarHeight,
    required this.navBarBottomPadding,
    required this.navBarHorizontalPadding,
    required this.blurStyle,
  });

  factory LiquidGlassConfig.fromMap(Map<String, dynamic> map) => LiquidGlassConfig(
        glassType: map['glassType'] as String? ?? 'visualEffect',
        supportsInteractive: map['supportsInteractive'] as bool? ?? false,
        supportsMorphing: map['supportsMorphing'] as bool? ?? false,
        supportsGlassEffectContainer: map['supportsGlassEffectContainer'] as bool? ?? false,
        recommendedCornerRadius: (map['recommendedCornerRadius'] as num?)?.toDouble() ?? 25.0,
        navBarHeight: (map['navBarHeight'] as num?)?.toDouble() ?? 56.0,
        navBarBottomPadding: (map['navBarBottomPadding'] as num?)?.toDouble() ?? 0.0,
        navBarHorizontalPadding: (map['navBarHorizontalPadding'] as num?)?.toDouble() ?? 0.0,
        blurStyle: map['blurStyle'] as String? ?? 'blur',
      );

  factory LiquidGlassConfig.fallback() => const LiquidGlassConfig(
        glassType: 'visualEffect',
        supportsInteractive: false,
        supportsMorphing: false,
        supportsGlassEffectContainer: false,
        recommendedCornerRadius: 25.0,
        navBarHeight: 56.0,
        navBarBottomPadding: 0.0,
        navBarHorizontalPadding: 0.0,
        blurStyle: 'blur',
      );

  /// iOS 26+: "liquidGlass", iOS < 26: "visualEffect"
  final String glassType;

  /// 是否支持交互效果（按压、弹跳、闪光）
  final bool supportsInteractive;

  /// 是否支持形态变换动画
  final bool supportsMorphing;

  /// 是否支持 GlassEffectContainer
  final bool supportsGlassEffectContainer;

  /// 推荐的圆角半径
  final double recommendedCornerRadius;

  /// 导航栏高度
  final double navBarHeight;

  /// 导航栏底部间距（悬浮距离）
  final double navBarBottomPadding;

  /// 导航栏水平间距
  final double navBarHorizontalPadding;

  /// 模糊样式: "blur" 或 "solid"
  final String blurStyle;

  /// 是否为 Liquid Glass 模式
  bool get isLiquidGlass => glassType == 'liquidGlass';
}
