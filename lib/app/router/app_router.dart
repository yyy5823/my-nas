import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/router/routes.dart';
import 'package:my_nas/features/connection/presentation/pages/connection_page.dart';
import 'package:my_nas/features/mine/presentation/pages/mine_page.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_list_page.dart';
import 'package:my_nas/features/reading/presentation/pages/reading_page.dart';
import 'package:my_nas/features/startup/presentation/pages/startup_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_page.dart';
import 'package:my_nas/shared/widgets/main_scaffold.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: Routes.startup,
  debugLogDiagnostics: true,
  routes: [
    // Startup page (handles auto-login)
    GoRoute(
      path: Routes.startup,
      name: 'startup',
      builder: (context, state) => const StartupPage(),
    ),

    // Connection page (without shell)
    GoRoute(
      path: Routes.connection,
      name: 'connection',
      builder: (context, state) => const ConnectionPage(),
    ),

    // Main shell with bottom navigation (5 tabs)
    ShellRoute(
      navigatorKey: shellNavigatorKey,
      builder: (context, state, child) => MainScaffold(child: child),
      routes: [
        GoRoute(
          path: Routes.video,
          name: 'video',
          builder: (context, state) => const VideoListPage(),
        ),
        GoRoute(
          path: Routes.music,
          name: 'music',
          builder: (context, state) => const MusicListPage(),
        ),
        GoRoute(
          path: Routes.photo,
          name: 'photo',
          builder: (context, state) => const PhotoListPage(),
        ),
        GoRoute(
          path: Routes.reading,
          name: 'reading',
          builder: (context, state) => const ReadingPage(),
        ),
        GoRoute(
          path: Routes.mine,
          name: 'mine',
          builder: (context, state) => const MinePage(),
        ),
      ],
    ),
  ],
);
