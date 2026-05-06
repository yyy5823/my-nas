import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Color, HSVColor;
import 'package:image/image.dart' as img;
import 'package:my_nas/core/errors/errors.dart';

/// 一对动态主题色：accent 给前景 / 强调，dark 给背景渐变
class DynamicAccent {
  const DynamicAccent({required this.accent, required this.dark});

  final Color accent;
  final Color dark;

  static const fallback = DynamicAccent(
    accent: Color(0xFF6451F9),
    dark: Color(0xFF38258F),
  );
}

/// 从封面图提取动态主题色（与 primuse `ThemeService.swift` 算法一致）：
/// 1. 下采样到 40×40
/// 2. 转 HSV，过滤 s≤0.15 / v≤0.10 / v≥0.95 的中性像素
/// 3. 按 hue 分 12 个 30° 桶
/// 4. 取像素数最多的桶，平均其 HSV
/// 5. accent: clamp s≥0.35, v∈[0.50, 0.85]；dark: 同色 v×0.65
class DynamicAccentService {
  DynamicAccentService._();

  static final DynamicAccentService instance = DynamicAccentService._();

  final Map<String, DynamicAccent> _cache = <String, DynamicAccent>{};

  /// 从本地封面文件路径计算 accent。失败 / 文件不存在 / 灰度图返回 [DynamicAccent.fallback]。
  /// 结果按 [cacheKey] 缓存，避免同一首歌重复解码。
  Future<DynamicAccent> fromCoverFile(String path, {String? cacheKey}) async {
    final key = cacheKey ?? path;
    final cached = _cache[key];
    if (cached != null) return cached;

    final bytes = await AppError.guard(
      () => File(path).readAsBytes(),
      action: 'DynamicAccent.readCover',
      fallback: Uint8List(0),
    );
    if (bytes == null || bytes.isEmpty) return DynamicAccent.fallback;

    final result = await _extractFromBytes(bytes);
    _cache[key] = result;
    return result;
  }

  /// 从内存封面字节直接计算（如刚下载的封面）
  Future<DynamicAccent> fromCoverBytes(Uint8List bytes,
      {required String cacheKey}) async {
    final cached = _cache[cacheKey];
    if (cached != null) return cached;
    final result = await _extractFromBytes(bytes);
    _cache[cacheKey] = result;
    return result;
  }

  void clearCache() => _cache.clear();

  Future<DynamicAccent> _extractFromBytes(Uint8List bytes) async {
    final result = await AppError.guard<DynamicAccent>(
      () async {
        final decoded = img.decodeImage(bytes);
        if (decoded == null) return DynamicAccent.fallback;

            // 下采样到 40×40 以加速；用 average 算法保留主色
            final small = img.copyResize(
              decoded,
              width: 40,
              height: 40,
              interpolation: img.Interpolation.average,
            );

            // 12 hue 桶（每 30°）
            final buckets = List<List<_HsvPixel>>.generate(12, (_) => []);
            for (final pixel in small) {
              final r = pixel.r.toInt() & 0xFF;
              final g = pixel.g.toInt() & 0xFF;
              final b = pixel.b.toInt() & 0xFF;
              final hsv = HSVColor.fromColor(
                Color.fromARGB(255, r, g, b),
              );
              if (hsv.saturation <= 0.15) continue;
              if (hsv.value <= 0.10 || hsv.value >= 0.95) continue;
              final hue = hsv.hue;
              final idx = (hue / 30).floor().clamp(0, 11);
              buckets[idx].add(_HsvPixel(hue, hsv.saturation, hsv.value));
            }

            // 找出像素数最多的桶
            var dominantIdx = -1;
            var maxCount = 0;
            for (var i = 0; i < buckets.length; i++) {
              if (buckets[i].length > maxCount) {
                maxCount = buckets[i].length;
                dominantIdx = i;
              }
            }
            if (dominantIdx < 0 || maxCount == 0) {
              return DynamicAccent.fallback;
            }

            final dominant = buckets[dominantIdx];
            final n = dominant.length;
            var sumH = 0.0;
            var sumS = 0.0;
            var sumV = 0.0;
            for (final p in dominant) {
              sumH += p.h;
              sumS += p.s;
              sumV += p.v;
            }
            final avgH = sumH / n;
            final avgS = sumS / n;
            final avgV = sumV / n;

            // clamp s≥0.35，v∈[0.50, 0.85]
            final accentS = avgS < 0.35 ? 0.35 : avgS;
            final accentV =
                avgV < 0.50 ? 0.50 : (avgV > 0.85 ? 0.85 : avgV);
            final accentColor =
                HSVColor.fromAHSV(1, avgH, accentS, accentV).toColor();
            final darkColor =
                HSVColor.fromAHSV(1, avgH, accentS, accentV * 0.65).toColor();
        return DynamicAccent(accent: accentColor, dark: darkColor);
      },
      action: 'DynamicAccent.extract',
      fallback: DynamicAccent.fallback,
    );
    return result ?? DynamicAccent.fallback;
  }
}

class _HsvPixel {
  const _HsvPixel(this.h, this.s, this.v);
  final double h;
  final double s;
  final double v;
}

/// 静态降低饱和度/亮度生成更深的同色（用于背景渐变末端）
Color darkenColor(Color color, {double factor = 0.55}) {
  final hsv = HSVColor.fromColor(color);
  return hsv.withValue((hsv.value * factor).clamp(0.0, 1.0)).toColor();
}

/// 用 HSV 调出更亮的同色（用于强调态）
Color lightenColor(Color color, {double factor = 1.2}) {
  final hsv = HSVColor.fromColor(color);
  return hsv.withValue((hsv.value * factor).clamp(0.0, 1.0)).toColor();
}
