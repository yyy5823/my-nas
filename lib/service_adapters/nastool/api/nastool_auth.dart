import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// NASTool 认证管理器
///
/// 使用 /user/login 端点进行会话认证
class NasToolAuth {
  NasToolAuth({required this.baseUrl});

  final String baseUrl;

  String? _sessionToken;
  String? _username;
  bool _isCookieAuth = false;

  /// 是否已认证
  bool get isAuthenticated => _sessionToken != null;

  /// 当前用户名
  String? get username => _username;

  /// 获取认证头
  Map<String, String> get authHeaders {
    if (_sessionToken == null) return {};

    // 根据认证类型返回正确的头
    if (_isCookieAuth) {
      return {'Cookie': _sessionToken!};
    }
    return {'Authorization': _sessionToken!};
  }

  /// 登录
  /// 
  /// 调用 /user/login 端点获取会话 Token
  Future<NasToolLoginResult> login(String username, String password) async {
    try {
      final url = Uri.parse('$baseUrl/api/v1/user/login');
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'username': username, 'password': password},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        // 检查返回结果
        final code = data['code'] as int? ?? -1;
        final success = data['success'] as bool? ?? false;
        final token = data['token'] as String? ?? 
                      (data['data'] as Map<String, dynamic>?)?['token'] as String?;
        
        if (code == 0 || success || token != null) {
          // 登录成功，保存 token
          _sessionToken = token ?? response.headers['authorization'];
          _username = username;
          _isCookieAuth = false;

          // 如果没有返回 token，尝试从 cookie 获取
          if (_sessionToken == null) {
            final cookies = response.headers['set-cookie'];
            if (cookies != null) {
              _sessionToken = cookies;
              _isCookieAuth = true;
            }
          }

          return NasToolLoginResult.success(
            token: _sessionToken,
            username: username,
          );
        } else {
          final message = data['message'] as String? ?? 
                          data['msg'] as String? ?? 
                          '登录失败';
          return NasToolLoginResult.failure(message);
        }
      } else if (response.statusCode == 401) {
        return const NasToolLoginResult.failure('用户名或密码错误');
      } else {
        return NasToolLoginResult.failure(
          '请求失败: ${response.statusCode}',
        );
      }
    } on SocketException catch (e) {
      return NasToolLoginResult.failure('无法连接服务器: ${e.message}');
    } on Exception catch (e) {
      return NasToolLoginResult.failure('登录异常: $e');
    }
  }

  /// 登出
  Future<void> logout() async {
    if (!isAuthenticated) return;
    
    try {
      final url = Uri.parse('$baseUrl/api/v1/system/logout');
      await http.post(
        url,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          ...authHeaders,
        },
      );
    } on Exception {
      // 忽略登出错误
    } finally {
      _sessionToken = null;
      _username = null;
    }
  }

  /// 验证会话是否有效
  Future<bool> validateSession() async {
    if (!isAuthenticated) return false;
    
    try {
      final url = Uri.parse('$baseUrl/api/v1/system/version');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          ...authHeaders,
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['code'] == 0 || data['version'] != null;
      }
      return false;
    } on Exception {
      return false;
    }
  }

  /// 设置 API Token（用于 API Token 认证）
  void setApiToken(String token) {
    _sessionToken = token;
    _username = 'API Token';
  }

  /// 验证 API Token 是否有效
  Future<bool> validateApiToken(String token) async {
    try {
      final url = Uri.parse('$baseUrl/api/v1/system/version');
      
      // 尝试多种 Authorization 格式
      final authFormats = [token, 'Bearer $token', 'Token $token'];
      
      for (final auth in authFormats) {
        final response = await http.post(
          url,
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Authorization': auth,
          },
        );
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (data['code'] == 0 || data['version'] != null) {
            // Token 有效，设置认证信息
            _sessionToken = auth;
            _username = 'API Token';
            return true;
          }
        }
      }
      return false;
    } on Exception {
      return false;
    }
  }

  /// 清除认证状态
  void clear() {
    _sessionToken = null;
    _username = null;
    _isCookieAuth = false;
  }
}

/// 登录结果
sealed class NasToolLoginResult {
  const NasToolLoginResult();
  
  const factory NasToolLoginResult.success({
    String? token,
    required String username,
  }) = NasToolLoginSuccess;
  
  const factory NasToolLoginResult.failure(String message) = NasToolLoginFailure;
  
  T when<T>({
    required T Function(String? token, String username) success,
    required T Function(String message) failure,
  });
}

class NasToolLoginSuccess extends NasToolLoginResult {
  const NasToolLoginSuccess({this.token, required this.username});
  
  final String? token;
  final String username;
  
  @override
  T when<T>({
    required T Function(String? token, String username) success,
    required T Function(String message) failure,
  }) => success(token, username);
}

class NasToolLoginFailure extends NasToolLoginResult {
  const NasToolLoginFailure(this.message);
  
  final String message;
  
  @override
  T when<T>({
    required T Function(String? token, String username) success,
    required T Function(String message) failure,
  }) => failure(message);
}
