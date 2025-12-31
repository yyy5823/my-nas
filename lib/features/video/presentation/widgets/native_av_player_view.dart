import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 原生 AVPlayer 视频视图
///
/// 在 iOS/macOS 上使用原生 AVPlayerLayer 显示视频
class NativeAVPlayerView extends StatelessWidget {
  const NativeAVPlayerView({
    super.key,
    required this.playerId,
    this.fit = BoxFit.contain,
  });

  /// 播放器 ID
  final int playerId;

  /// 视频填充模式
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS && !Platform.isMacOS) {
      return const Center(
        child: Text('NativeAVPlayerView 仅支持 iOS 和 macOS'),
      );
    }

    const viewType = 'native_av_player_view';
    final creationParams = <String, dynamic>{
      'playerId': playerId,
      'fit': _boxFitToString(fit),
    };

    if (Platform.isIOS) {
      return UiKitView(
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    } else if (Platform.isMacOS) {
      return AppKitView(
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    }

    return const SizedBox.shrink();
  }

  String _boxFitToString(BoxFit fit) {
    switch (fit) {
      case BoxFit.contain:
        return 'contain';
      case BoxFit.cover:
        return 'cover';
      case BoxFit.fill:
        return 'fill';
      default:
        return 'contain';
    }
  }
}
