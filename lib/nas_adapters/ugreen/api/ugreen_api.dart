import 'package:dio/dio.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 绿联 NAS API 认证结果
sealed class UGreenAuthResult {}

class UGreenAuthSuccess extends UGreenAuthResult {
  UGreenAuthSuccess({
    required this.token,
    this.refreshToken,
    this.userId,
  });

  final String token;
  final String? refreshToken;
  final String? userId;
}

class UGreenAuthFailure extends UGreenAuthResult {
  UGreenAuthFailure({required this.error, this.code});

  final String error;
  final int? code;
}

class UGreenAuthRequires2FA extends UGreenAuthResult {
  UGreenAuthRequires2FA({this.methods = const ['totp']});

  final List<String> methods;
}

/// 绿联 NAS 设备信息
class UGreenDeviceInfo {
  const UGreenDeviceInfo({
    required this.hostname,
    this.model,
    this.version,
    this.serial,
    this.mac,
  });

  final String hostname;
  final String? model;
  final String? version;
  final String? serial;
  final String? mac;
}

/// 绿联 NAS 文件信息
class UGreenFileInfo {
  const UGreenFileInfo({
    required this.name,
    required this.path,
    required this.isDir,
    this.size,
    this.modified,
    this.created,
    this.mimeType,
  });

  final String name;
  final String path;
  final bool isDir;
  final int? size;
  final DateTime? modified;
  final DateTime? created;
  final String? mimeType;
}

/// 绿联 NAS API 接口
///
/// 绿联 NAS 使用 UGOS 系统，API 接口与常见的 NAS 类似
/// 主要使用 RESTful 风格的 API
class UGreenApi {
  UGreenApi({required this.dio});

  final Dio dio;
  String? _token;

  /// 是否已认证
  bool get isAuthenticated => _token != null;

  /// 当前 token
  String? get token => _token;

  /// 登录认证
  ///
  /// 绿联 NAS 通常使用以下接口进行认证:
  /// POST /api/auth/login
  Future<UGreenAuthResult> login({
    required String username,
    required String password,
    String? otpCode,
  }) async {
    logger.i('UGreenApi: 开始登录认证');
    logger.i('UGreenApi: 用户名 => $username');

    try {
      // 尝试标准的 UGOS API 登录
      final response = await dio.post(
        '/api/auth/login',
        data: {
          'username': username,
          'password': password,
          if (otpCode != null) 'otp_code': otpCode,
        },
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      logger.i('UGreenApi: 登录响应状态码 => ${response.statusCode}');
      logger.d('UGreenApi: 登录响应 => ${response.data}');

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map) {
          // 检查是否需要2FA
          if (data['require_2fa'] == true || data['need_otp'] == true) {
            logger.i('UGreenApi: 需要二次验证');
            return UGreenAuthRequires2FA();
          }

          // 获取 token
          final token = data['token'] ?? data['access_token'] ?? data['data']?['token'];
          if (token != null) {
            _token = token as String;
            logger.i('UGreenApi: 登录成功');
            return UGreenAuthSuccess(
              token: _token!,
              refreshToken: data['refresh_token'] as String?,
              userId: data['user_id']?.toString() ?? data['data']?['user_id']?.toString(),
            );
          }
        }
      } else if (response.statusCode == 401) {
        // 可能需要 2FA 或凭证错误
        final data = response.data;
        if (data is Map && (data['require_2fa'] == true || data['error_code'] == 'NEED_OTP')) {
          return UGreenAuthRequires2FA();
        }
        return UGreenAuthFailure(
          error: _extractError(data) ?? '用户名或密码错误',
          code: 401,
        );
      }

      return UGreenAuthFailure(
        error: _extractError(response.data) ?? '登录失败',
        code: response.statusCode,
      );
    } on DioException catch (e) {
      logger.e('UGreenApi: 登录请求异常', e);
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return UGreenAuthFailure(error: '连接超时，请检查网络和地址');
      }
      if (e.type == DioExceptionType.connectionError) {
        return UGreenAuthFailure(error: '无法连接到服务器，请检查地址和端口');
      }
      return UGreenAuthFailure(error: e.message ?? '网络错误');
    } catch (e) {
      logger.e('UGreenApi: 登录异常', e);
      return UGreenAuthFailure(error: e.toString());
    }
  }

  /// 登出
  Future<void> logout() async {
    if (_token == null) return;

    try {
      await dio.post(
        '/api/auth/logout',
        options: Options(
          headers: _authHeaders,
        ),
      );
    } catch (e) {
      logger.w('UGreenApi: 登出请求失败', e);
    } finally {
      _token = null;
    }
  }

  /// 获取设备信息
  Future<UGreenDeviceInfo> getDeviceInfo() async {
    final response = await dio.get(
      '/api/system/info',
      options: Options(headers: _authHeaders),
    );

    final data = response.data;
    if (data is Map) {
      final info = data['data'] ?? data;
      return UGreenDeviceInfo(
        hostname: info['hostname']?.toString() ?? info['device_name']?.toString() ?? 'UGREEN NAS',
        model: info['model']?.toString(),
        version: info['version']?.toString() ?? info['firmware_version']?.toString(),
        serial: info['serial']?.toString(),
        mac: info['mac']?.toString(),
      );
    }

    return const UGreenDeviceInfo(hostname: 'UGREEN NAS');
  }

  /// 列出目录内容
  Future<List<UGreenFileInfo>> listDirectory(String path) async {
    final response = await dio.get(
      '/api/file/list',
      queryParameters: {
        'path': path,
      },
      options: Options(headers: _authHeaders),
    );

    final data = response.data;
    final items = <UGreenFileInfo>[];

    if (data is Map) {
      final files = data['data'] ?? data['files'] ?? data['items'] ?? [];
      if (files is List) {
        for (final file in files) {
          if (file is Map) {
            items.add(_parseFileInfo(file, path));
          }
        }
      }
    }

    return items;
  }

  /// 获取文件下载链接
  Future<String> getFileUrl(String path) async {
    // 绿联 NAS 通常提供直接下载接口
    final baseUrl = dio.options.baseUrl;
    final token = _token ?? '';
    return '$baseUrl/api/file/download?path=${Uri.encodeComponent(path)}&token=$token';
  }

  /// 创建目录
  Future<void> createDirectory(String path) async {
    await dio.post(
      '/api/file/mkdir',
      data: {'path': path},
      options: Options(headers: _authHeaders),
    );
  }

  /// 删除文件或目录
  Future<void> delete(String path) async {
    await dio.post(
      '/api/file/delete',
      data: {'path': path},
      options: Options(headers: _authHeaders),
    );
  }

  /// 重命名
  Future<void> rename(String oldPath, String newPath) async {
    await dio.post(
      '/api/file/rename',
      data: {
        'path': oldPath,
        'new_path': newPath,
      },
      options: Options(headers: _authHeaders),
    );
  }

  /// 获取共享文件夹列表
  Future<List<UGreenFileInfo>> listShares() async {
    try {
      final response = await dio.get(
        '/api/share/list',
        options: Options(headers: _authHeaders),
      );

      final data = response.data;
      final items = <UGreenFileInfo>[];

      if (data is Map) {
        final shares = data['data'] ?? data['shares'] ?? [];
        if (shares is List) {
          for (final share in shares) {
            if (share is Map) {
              items.add(UGreenFileInfo(
                name: share['name']?.toString() ?? share['share_name']?.toString() ?? '',
                path: '/${share['name'] ?? share['path'] ?? ''}',
                isDir: true,
              ));
            }
          }
        }
      }

      return items;
    } catch (e) {
      // 如果获取共享列表失败，尝试列出根目录
      logger.w('UGreenApi: 获取共享列表失败，尝试列出根目录', e);
      return listDirectory('/');
    }
  }

  Map<String, String> get _authHeaders => {
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  String? _extractError(dynamic data) {
    if (data is Map) {
      return data['message']?.toString() ??
             data['error']?.toString() ??
             data['error_message']?.toString();
    }
    return null;
  }

  UGreenFileInfo _parseFileInfo(Map<dynamic, dynamic> file, String parentPath) {
    final name = file['name']?.toString() ?? file['filename']?.toString() ?? '';
    final isDir = file['is_dir'] == true ||
                  file['type'] == 'dir' ||
                  file['type'] == 'folder';

    DateTime? modified;
    if (file['modified'] != null) {
      if (file['modified'] is int) {
        modified = DateTime.fromMillisecondsSinceEpoch((file['modified'] as int) * 1000);
      } else if (file['modified'] is String) {
        modified = DateTime.tryParse(file['modified'] as String);
      }
    }

    DateTime? created;
    if (file['created'] != null) {
      if (file['created'] is int) {
        created = DateTime.fromMillisecondsSinceEpoch((file['created'] as int) * 1000);
      } else if (file['created'] is String) {
        created = DateTime.tryParse(file['created'] as String);
      }
    }

    return UGreenFileInfo(
      name: name,
      path: file['path']?.toString() ?? '$parentPath/$name',
      isDir: isDir,
      size: file['size'] as int?,
      modified: modified,
      created: created,
      mimeType: file['mime_type']?.toString() ?? file['mimetype']?.toString(),
    );
  }
}
