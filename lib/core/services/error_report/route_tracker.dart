import 'package:flutter/widgets.dart';

/// 路由追踪器
/// 用于记录当前页面路由，便于错误上报时附带页面信息
/// @author cq
/// @date 2025-12-11
class RouteTracker extends NavigatorObserver {
  RouteTracker._();

  static final RouteTracker _instance = RouteTracker._();
  static RouteTracker get instance => _instance;

  String? _currentRoute;
  String? _previousRoute;
  final List<String> _routeHistory = [];
  static const int _maxHistorySize = 10;

  /// 当前页面路由
  String? get currentRoute => _currentRoute;

  /// 上一个页面路由
  String? get previousRoute => _previousRoute;

  /// 路由历史（最近N个）
  List<String> get routeHistory => List.unmodifiable(_routeHistory);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _updateRoute(route.settings.name);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null) {
      _updateRoute(previousRoute.settings.name);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) {
      _updateRoute(newRoute.settings.name);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (previousRoute != null) {
      _updateRoute(previousRoute.settings.name);
    }
  }

  void _updateRoute(String? routeName) {
    if (routeName == null || routeName.isEmpty) return;

    _previousRoute = _currentRoute;
    _currentRoute = routeName;

    // 更新历史记录
    _routeHistory.add(routeName);
    if (_routeHistory.length > _maxHistorySize) {
      _routeHistory.removeAt(0);
    }
  }

  /// 手动设置当前路由（用于 GoRouter 等声明式路由）
  void setCurrentRoute(String route) {
    _updateRoute(route);
  }

  /// 清除路由历史
  void clear() {
    _currentRoute = null;
    _previousRoute = null;
    _routeHistory.clear();
  }
}
