import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/router/routes.dart';
import 'package:my_nas/features/connection/presentation/pages/connection_page.dart';
import 'package:my_nas/features/file_browser/presentation/pages/file_browser_page.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart';
import 'package:my_nas/features/settings/presentation/pages/settings_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_page.dart';
import 'package:my_nas/shared/widgets/main_scaffold.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: Routes.connection,
  debugLogDiagnostics: true,
  routes: [
    // Connection page (without shell)
    GoRoute(
      path: Routes.connection,
      name: 'connection',
      builder: (context, state) => const ConnectionPage(),
    ),

    // Main shell with bottom navigation
    ShellRoute(
      navigatorKey: shellNavigatorKey,
      builder: (context, state, child) => MainScaffold(child: child),
      routes: [
        GoRoute(
          path: Routes.files,
          name: 'files',
          builder: (context, state) => const FileBrowserPage(),
        ),
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
          path: Routes.book,
          name: 'book',
          builder: (context, state) => const Placeholder(), // TODO: BookPage
        ),
        GoRoute(
          path: Routes.settings,
          name: 'settings',
          builder: (context, state) => const SettingsPage(),
        ),
      ],
    ),
  ],
);
