import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';

/// Deep Link 服务
/// 处理来自灵动岛、Widget 等的控制命令
class DeepLinkService {
  factory DeepLinkService() => _instance ??= DeepLinkService._();
  DeepLinkService._();

  static DeepLinkService? _instance;

  AppLinks? _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  WidgetRef? _ref;

  /// 初始化服务
  void init(WidgetRef ref) {
    _ref = ref;

    // 仅在 iOS 上监听 deep links（灵动岛功能）
    if (!Platform.isIOS) return;

    try {
      _appLinks = AppLinks();

      // 监听后续的链接
      _linkSubscription = _appLinks!.uriLinkStream.listen(
        _handleDeepLink,
        onError: (Object err, StackTrace st) {
          AppError.handle(err, st, 'DeepLinkService.uriLinkStream');
        },
      );

      // 获取初始链接（如果应用是通过 deep link 启动的）
      _appLinks!.getInitialLink().then((uri) {
        if (uri != null) {
          _handleDeepLink(uri);
        }
      }).catchError((Object error, StackTrace st) {
        AppError.handle(error, st, 'DeepLinkService.getInitialLink');
      });

      logger.i('DeepLinkService: Initialized');
    } catch (e, st) {
      AppError.handle(e, st, 'DeepLinkService.init');
      // 清理资源
      _appLinks = null;
      _linkSubscription = null;
      rethrow; // 重新抛出异常，让上层处理
    }
  }

  /// 处理 deep link
  void _handleDeepLink(Uri uri) {
    logger.i('DeepLinkService: Received deep link: $uri');

    if (uri.scheme != 'mynas') return;

    final host = uri.host; // e.g., "music"
    final path = uri.path; // e.g., "/toggle"

    if (host == 'music') {
      _handleMusicCommand(path);
    }
  }

  /// 处理音乐控制命令
  void _handleMusicCommand(String path) {
    final ref = _ref;
    if (ref == null) {
      logger.w('DeepLinkService: WidgetRef not available');
      return;
    }

    final controller = ref.read(musicPlayerControllerProvider.notifier);

    switch (path) {
      case '/toggle':
        // 切换播放/暂停
        final isPlaying = ref.read(musicPlayerControllerProvider).isPlaying;
        if (isPlaying) {
          controller.pause();
          logger.d('DeepLinkService: Paused playback');
        } else {
          controller.resume();
          logger.d('DeepLinkService: Resumed playback');
        }

      case '/previous':
        // 上一首
        controller.playPrevious();
        logger.d('DeepLinkService: Playing previous track');

      case '/next':
        // 下一首
        controller.playNext();
        logger.d('DeepLinkService: Playing next track');

      case '/favorite':
        // 收藏当前歌曲
        final currentMusic = ref.read(currentMusicProvider);
        if (currentMusic != null) {
          ref.read(musicFavoritesProvider.notifier).toggleFavorite(currentMusic);
          logger.d('DeepLinkService: Toggled favorite for ${currentMusic.displayTitle}');
        }

      case '/player':
        // 打开播放器页面 - 这个由路由处理
        logger.d('DeepLinkService: Open player page request');

      default:
        logger.w('DeepLinkService: Unknown music command: $path');
    }
  }

  /// 释放资源
  void dispose() {
    _linkSubscription?.cancel();
    _ref = null;
    logger.i('DeepLinkService: Disposed');
  }
}

/// DeepLinkService Provider
final deepLinkServiceProvider = Provider<DeepLinkService>((ref) => DeepLinkService());
