/// Trakt OAuth 配置
///
/// 要使用内置的 Trakt 集成，你需要：
/// 1. 访问 https://trakt.tv/oauth/applications 创建一个应用
/// 2. 设置 Redirect URI 为: mynas://trakt/callback
/// 3. 将获取的 Client ID 和 Client Secret 填入下方
///
/// 或者保留为空，让用户在应用中自行输入
class TraktOAuthConfig {
  TraktOAuthConfig._();

  /// 内置的 Client ID（留空则要求用户输入）
  ///
  /// 从 https://trakt.tv/oauth/applications 获取
  static const String? builtInClientId = null;

  /// 内置的 Client Secret（留空则要求用户输入）
  ///
  /// 从 https://trakt.tv/oauth/applications 获取
  static const String? builtInClientSecret = null;

  /// 深度链接回调 URI
  static const String deepLinkRedirectUri = 'mynas://trakt/callback';

  /// OOB (Out-of-Band) 回调 URI（用于手动输入授权码）
  static const String oobRedirectUri = 'urn:ietf:wg:oauth:2.0:oob';

  /// 是否有内置凭证
  static bool get hasBuiltInCredentials =>
      builtInClientId != null &&
      builtInClientId!.isNotEmpty &&
      builtInClientSecret != null &&
      builtInClientSecret!.isNotEmpty;
}
