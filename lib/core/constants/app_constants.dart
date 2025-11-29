abstract final class AppConstants {
  static const String appName = 'MyNAS';
  static const String appVersion = '0.1.0';

  // Storage keys
  static const String themeKey = 'theme_mode';
  static const String localeKey = 'locale';
  static const String connectionsKey = 'connections';

  // Timeouts
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 60);

  // Pagination
  static const int defaultPageSize = 50;

  // Cache
  static const Duration cacheExpiry = Duration(hours: 1);
  static const int maxCacheSize = 100;
}
