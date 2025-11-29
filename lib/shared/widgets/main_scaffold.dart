import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/router/routes.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';

class MainScaffold extends StatelessWidget {
  const MainScaffold({required this.child, super.key});

  final Widget child;

  static final _destinations = [
    const _Destination(
      icon: Icons.folder_outlined,
      selectedIcon: Icons.folder,
      label: '文件',
      route: Routes.files,
    ),
    const _Destination(
      icon: Icons.video_library_outlined,
      selectedIcon: Icons.video_library,
      label: '视频',
      route: Routes.video,
    ),
    const _Destination(
      icon: Icons.library_music_outlined,
      selectedIcon: Icons.library_music,
      label: '音乐',
      route: Routes.music,
    ),
    const _Destination(
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book,
      label: '阅读',
      route: Routes.book,
    ),
    const _Destination(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: '设置',
      route: Routes.settings,
    ),
  ];

  int _getCurrentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    for (var i = 0; i < _destinations.length; i++) {
      if (location.startsWith(_destinations[i].route)) {
        return i;
      }
    }
    return 0;
  }

  void _onDestinationSelected(BuildContext context, int index) {
    context.go(_destinations[index].route);
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _getCurrentIndex(context);

    // Use NavigationRail for desktop, NavigationBar for mobile
    if (context.isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: context.screenWidth > 1400,
              selectedIndex: currentIndex,
              onDestinationSelected: (index) =>
                  _onDestinationSelected(context, index),
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Icon(
                  Icons.storage,
                  size: 32,
                  color: context.colorScheme.primary,
                ),
              ),
              destinations: _destinations
                  .map(
                    (d) => NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                    ),
                  )
                  .toList(),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) =>
            _onDestinationSelected(context, index),
        destinations: _destinations
            .map(
              (d) => NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _Destination {
  const _Destination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String route;
}
