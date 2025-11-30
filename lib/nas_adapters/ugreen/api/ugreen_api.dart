import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/pkcs1.dart';
import 'package:pointycastle/asymmetric/rsa.dart';

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
/// UGOS 系统使用两步 RSA 加密登录流程:
/// 1. POST /ugreen/v1/verify/check - 获取 RSA 公钥
/// 2. POST /ugreen/v1/verify/login - 使用加密密码登录
class UGreenApi {
  UGreenApi({required this.dio});

  final Dio dio;
  String? _token;
  String? _username;
  String? _password;

  /// 是否已认证
  bool get isAuthenticated => _token != null;

  /// 当前 token
  String? get token => _token;

  /// 登录认证
  ///
  /// UGOS 使用两步 RSA 加密登录:
  /// 1. 获取公钥
  /// 2. 使用公钥加密密码后登录
  Future<UGreenAuthResult> login({
    required String username,
    required String password,
    String? otpCode,
  }) async {
    logger.i('UGreenApi: 开始登录认证 (UGOS API)');
    logger.i('UGreenApi: 用户名 => $username');

    _username = username;
    _password = password;

    try {
      // Step 1: 获取 RSA 公钥
      logger.i('UGreenApi: Step 1 - 获取 RSA 公钥');
      final checkResponse = await dio.post(
        '/ugreen/v1/verify/check',
        queryParameters: {'token': ''},
        data: {'username': username},
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      logger.d('UGreenApi: check 响应状态码 => ${checkResponse.statusCode}');
      logger.d('UGreenApi: check 响应头 => ${checkResponse.headers.map}');

      // 从响应头获取 RSA 公钥
      final rsaTokenHeader = checkResponse.headers.value('x-rsa-token');
      if (rsaTokenHeader == null) {
        logger.e('UGreenApi: 未获取到 RSA 公钥');
        return UGreenAuthFailure(error: '服务器未返回加密密钥');
      }

      logger.i('UGreenApi: 获取到 RSA 公钥');

      // Step 2: 使用 RSA 加密密码并登录
      logger.i('UGreenApi: Step 2 - 加密密码并登录');
      final encryptedPassword = _encryptPassword(password, rsaTokenHeader);
      logger.d('UGreenApi: 密码加密完成');

      final loginResponse = await dio.post(
        '/ugreen/v1/verify/login',
        data: {
          'is_simple': true,
          'keepalive': true,
          'otp': otpCode != null,
          'username': username,
          'password': encryptedPassword,
          if (otpCode != null) 'otp_code': otpCode,
        },
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      logger.i('UGreenApi: login 响应状态码 => ${loginResponse.statusCode}');
      logger.d('UGreenApi: login 响应 => ${loginResponse.data}');

      final data = loginResponse.data;
      if (data is Map) {
        final code = data['code'];

        // 成功
        if (code == 200) {
          final tokenData = data['data'];
          if (tokenData is Map && tokenData['token'] != null) {
            _token = tokenData['token'] as String;
            logger.i('UGreenApi: 登录成功');
            return UGreenAuthSuccess(
              token: _token!,
              userId: tokenData['user_id']?.toString(),
            );
          }
        }

        // 需要 2FA
        if (code == 1001 || data['need_otp'] == true || data['require_2fa'] == true) {
          logger.i('UGreenApi: 需要二次验证');
          return UGreenAuthRequires2FA();
        }

        // 其他错误
        final message = data['message']?.toString() ??
                       data['msg']?.toString() ??
                       '登录失败 (code: $code)';
        logger.e('UGreenApi: 登录失败 => $message');
        return UGreenAuthFailure(error: message, code: code as int?);
      }

      return UGreenAuthFailure(error: '服务器响应格式错误');
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
    } catch (e, st) {
      logger.e('UGreenApi: 登录异常', e, st);
      return UGreenAuthFailure(error: e.toString());
    }
  }

  /// RSA 加密密码
  String _encryptPassword(String password, String rsaPublicKeyBase64) {
    try {
      // 解码 Base64 公钥
      final publicKeyBytes = base64Decode(rsaPublicKeyBase64);
      final publicKeyPem = utf8.decode(publicKeyBytes);

      logger.d('UGreenApi: 公钥 PEM:\n$publicKeyPem');

      // 解析 PEM 格式的公钥
      final publicKey = _parsePublicKeyFromPem(publicKeyPem);

      // 使用 PKCS1 v1.5 加密
      final encryptor = PKCS1Encoding(RSAEngine())
        ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));

      final passwordBytes = utf8.encode(password);
      final encrypted = encryptor.process(Uint8List.fromList(passwordBytes));

      // Base64 编码
      return base64Encode(encrypted);
    } catch (e, st) {
      logger.e('UGreenApi: RSA 加密失败', e, st);
      rethrow;
    }
  }

  /// 从 PEM 格式解析 RSA 公钥
  RSAPublicKey _parsePublicKeyFromPem(String pem) {
    // 移除 PEM 头尾
    final lines = pem.split('\n');
    final base64String = lines
        .where((line) =>
            !line.startsWith('-----BEGIN') &&
            !line.startsWith('-----END') &&
            line.trim().isNotEmpty)
        .join('');

    final keyBytes = base64Decode(base64String);

    // 解析 ASN.1 结构
    final asn1Parser = ASN1Parser(Uint8List.fromList(keyBytes));
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

    // PKCS#1 格式: 直接包含 n 和 e
    // PKCS#8/SubjectPublicKeyInfo 格式: 包含算法标识符和公钥
    if (topLevelSeq.elements!.length == 2) {
      final firstElement = topLevelSeq.elements![0];
      if (firstElement is ASN1Integer) {
        // PKCS#1 格式
        final modulus = (firstElement).integer;
        final exponent = (topLevelSeq.elements![1] as ASN1Integer).integer;
        return RSAPublicKey(modulus!, exponent!);
      } else {
        // PKCS#8 格式
        final publicKeyBitString = topLevelSeq.elements![1] as ASN1BitString;
        final publicKeyBytes = publicKeyBitString.stringValues!;
        final publicKeyParser = ASN1Parser(Uint8List.fromList(publicKeyBytes));
        final publicKeySeq = publicKeyParser.nextObject() as ASN1Sequence;
        final modulus = (publicKeySeq.elements![0] as ASN1Integer).integer;
        final exponent = (publicKeySeq.elements![1] as ASN1Integer).integer;
        return RSAPublicKey(modulus!, exponent!);
      }
    }

    throw FormatException('无法解析公钥格式');
  }

  /// 登出
  Future<void> logout() async {
    if (_token == null) return;

    try {
      await dio.post(
        '/ugreen/v1/verify/logout',
        queryParameters: {'token': _token},
      );
    } catch (e) {
      logger.w('UGreenApi: 登出请求失败', e);
    } finally {
      _token = null;
      _username = null;
      _password = null;
    }
  }

  /// 获取设备信息
  Future<UGreenDeviceInfo> getDeviceInfo() async {
    final response = await _request('/ugreen/v1/system/info');

    final data = response.data;
    if (data is Map && data['code'] == 200) {
      final info = data['data'] ?? {};
      return UGreenDeviceInfo(
        hostname: info['hostname']?.toString() ??
                  info['device_name']?.toString() ??
                  'UGREEN NAS',
        model: info['model']?.toString(),
        version: info['version']?.toString() ??
                 info['firmware_version']?.toString(),
        serial: info['serial']?.toString(),
        mac: info['mac']?.toString(),
      );
    }

    return const UGreenDeviceInfo(hostname: 'UGREEN NAS');
  }

  /// 列出目录内容
  ///
  /// UGOS 文件管理器 API 端点尝试顺序:
  /// 1. /ugreen/v1/filemgr/list (带不同参数格式)
  /// 2. /ugreen/v1/file/list
  /// 3. /ugreen/v2/file/list
  Future<List<UGreenFileInfo>> listDirectory(String path) async {
    logger.i('UGreenApi: 列出目录 => $path');

    // 尝试不同的 API 端点和参数组合
    final attempts = [
      // 尝试 1: filemgr/list 带 path 参数
      {
        'endpoint': '/ugreen/v1/filemgr/list',
        'data': {'path': path, 'page': 1, 'page_size': 1000},
      },
      // 尝试 2: filemgr/list 带 dir 参数
      {
        'endpoint': '/ugreen/v1/filemgr/list',
        'data': {'dir': path, 'page': 1, 'limit': 1000},
      },
      // 尝试 3: file/list
      {
        'endpoint': '/ugreen/v1/file/list',
        'data': {'path': path, 'page': 1, 'page_size': 1000},
      },
      // 尝试 4: file/list 带 folder 参数
      {
        'endpoint': '/ugreen/v1/file/list',
        'data': {'folder': path, 'offset': 0, 'limit': 1000},
      },
      // 尝试 5: v2 file/list
      {
        'endpoint': '/ugreen/v2/file/list',
        'data': {'path': path, 'page': 1, 'page_size': 1000},
      },
      // 尝试 6: filemgr/dir/list
      {
        'endpoint': '/ugreen/v1/filemgr/dir/list',
        'data': {'path': path},
      },
    ];

    for (final attempt in attempts) {
      try {
        final endpoint = attempt['endpoint'] as String;
        final data = attempt['data'] as Map<String, dynamic>;
        logger.d('UGreenApi: 尝试端点 => $endpoint, 参数 => $data');

        final response = await _request(endpoint, data: data);

        final respData = response.data;
        logger.d('UGreenApi: listDirectory 响应 => $respData');

        if (respData is Map) {
          final code = respData['code'];
          if (code == 200) {
            final items = <UGreenFileInfo>[];
            // 尝试不同的响应结构
            final files = respData['data']?['list'] ??
                          respData['data']?['files'] ??
                          respData['data']?['items'] ??
                          respData['data']?['children'] ??
                          respData['data'] ??
                          [];

            if (files is List) {
              for (final file in files) {
                if (file is Map) {
                  items.add(_parseFileInfo(file, path));
                }
              }
            }

            if (items.isNotEmpty) {
              logger.i('UGreenApi: 找到 ${items.length} 个文件/目录 (使用 $endpoint)');
              return items;
            }
            logger.d('UGreenApi: $endpoint 返回空列表');
          } else {
            final msg = respData['message'] ?? respData['msg'] ?? 'code=$code';
            logger.w('UGreenApi: $endpoint 返回错误: $msg');
          }
        }
      } catch (e) {
        logger.w('UGreenApi: 尝试失败', e);
      }
    }

    logger.e('UGreenApi: 所有端点都失败了，路径: $path');
    return [];
  }

  /// 获取文件下载链接
  Future<String> getFileUrl(String path) async {
    final baseUrl = dio.options.baseUrl;
    return '$baseUrl/ugreen/v1/file/download?path=${Uri.encodeComponent(path)}&token=$_token';
  }

  /// 创建目录
  Future<void> createDirectory(String path) async {
    await _request(
      '/ugreen/v1/file/mkdir',
      data: {'path': path},
    );
  }

  /// 删除文件或目录
  Future<void> delete(String path) async {
    await _request(
      '/ugreen/v1/file/delete',
      data: {'paths': [path]},
    );
  }

  /// 重命名
  Future<void> rename(String oldPath, String newPath) async {
    await _request(
      '/ugreen/v1/file/rename',
      data: {
        'old_path': oldPath,
        'new_path': newPath,
      },
    );
  }

  /// 获取共享文件夹列表
  ///
  /// UGOS 共享文件夹 API 端点尝试顺序 (尝试多种已知的 UGOS API 格式)
  Future<List<UGreenFileInfo>> listShares() async {
    logger.i('UGreenApi: 获取共享文件夹列表');

    // 尝试不同的共享端点和参数组合
    final attempts = [
      // 存储管理相关端点
      {'endpoint': '/ugreen/v1/storage/share/list', 'data': <String, dynamic>{}},
      {'endpoint': '/ugreen/v1/storage/shares', 'data': <String, dynamic>{}},
      {'endpoint': '/ugreen/v1/storage/volume/list', 'data': <String, dynamic>{}},
      // 文件管理相关端点
      {'endpoint': '/ugreen/v1/filemgr/share/list', 'data': <String, dynamic>{}},
      {'endpoint': '/ugreen/v1/filemgr/shares', 'data': <String, dynamic>{}},
      {'endpoint': '/ugreen/v1/filemgr/root', 'data': <String, dynamic>{}},
      // 通用共享端点
      {'endpoint': '/ugreen/v1/share/list', 'data': <String, dynamic>{}},
      {'endpoint': '/ugreen/v1/shares', 'data': <String, dynamic>{}},
      // 用户目录相关
      {'endpoint': '/ugreen/v1/user/home', 'data': <String, dynamic>{}},
      {'endpoint': '/ugreen/v1/user/shares', 'data': <String, dynamic>{}},
    ];

    for (final attempt in attempts) {
      try {
        final endpoint = attempt['endpoint'] as String;
        final data = attempt['data'] as Map<String, dynamic>;
        logger.d('UGreenApi: 尝试共享端点 => $endpoint');

        final response = await _request(endpoint, data: data.isEmpty ? null : data);

        final respData = response.data;
        logger.d('UGreenApi: listShares 响应 => $respData');

        if (respData is Map && respData['code'] == 200) {
          final items = <UGreenFileInfo>[];

          // 尝试不同的响应结构
          final shares = respData['data']?['list'] ??
                         respData['data']?['shares'] ??
                         respData['data']?['volumes'] ??
                         respData['data']?['items'] ??
                         respData['data']?['folders'] ??
                         (respData['data'] is List ? respData['data'] : null) ??
                         [];

          if (shares is List) {
            for (final share in shares) {
              if (share is Map) {
                final name = share['name']?.toString() ??
                             share['share_name']?.toString() ??
                             share['volume_name']?.toString() ??
                             share['folder_name']?.toString() ??
                             '';
                if (name.isEmpty) continue;

                final path = share['path']?.toString() ??
                             share['mount_point']?.toString() ??
                             share['share_path']?.toString() ??
                             '/$name';
                items.add(UGreenFileInfo(
                  name: name,
                  path: path,
                  isDir: true,
                ));
              }
            }
          }

          if (items.isNotEmpty) {
            logger.i('UGreenApi: 找到 ${items.length} 个共享文件夹 (使用 $endpoint)');
            return items;
          }
        }
      } catch (e) {
        logger.w('UGreenApi: 尝试失败', e);
      }
    }

    // 所有共享端点都失败，尝试直接列出根目录
    logger.i('UGreenApi: 共享端点都失败，尝试直接列出根目录');
    final rootFiles = await listDirectory('/');
    if (rootFiles.isNotEmpty) {
      return rootFiles;
    }

    // 如果根目录也为空，创建默认的共享文件夹列表
    logger.w('UGreenApi: 无法获取共享列表，使用默认共享文件夹');
    return [
      const UGreenFileInfo(name: 'Public', path: '/Public', isDir: true),
      const UGreenFileInfo(name: 'home', path: '/home', isDir: true),
    ];
  }

  /// 发送 API 请求（自动处理 token）
  Future<Response<dynamic>> _request(
    String path, {
    Map<String, dynamic>? data,
    String method = 'POST',
  }) async {
    final response = await dio.request(
      path,
      queryParameters: {'token': _token ?? ''},
      data: data,
      options: Options(method: method),
    );

    // 检查 token 是否过期 (code 1024)
    if (response.data is Map && response.data['code'] == 1024) {
      logger.i('UGreenApi: Token 过期，重新登录');
      if (_username != null && _password != null) {
        final result = await login(username: _username!, password: _password!);
        if (result is UGreenAuthSuccess) {
          // 重试请求
          return dio.request(
            path,
            queryParameters: {'token': _token ?? ''},
            data: data,
            options: Options(method: method),
          );
        }
      }
    }

    return response;
  }

  UGreenFileInfo _parseFileInfo(Map<dynamic, dynamic> file, String parentPath) {
    final name = file['name']?.toString() ?? file['filename']?.toString() ?? '';
    final isDir = file['is_dir'] == true ||
                  file['isdir'] == true ||
                  file['type'] == 'dir' ||
                  file['type'] == 'folder';

    DateTime? modified;
    final modifiedValue = file['modified'] ?? file['mtime'];
    if (modifiedValue != null) {
      if (modifiedValue is int) {
        modified = DateTime.fromMillisecondsSinceEpoch(modifiedValue * 1000);
      } else if (modifiedValue is String) {
        modified = DateTime.tryParse(modifiedValue);
      }
    }

    DateTime? created;
    final createdValue = file['created'] ?? file['ctime'];
    if (createdValue != null) {
      if (createdValue is int) {
        created = DateTime.fromMillisecondsSinceEpoch(createdValue * 1000);
      } else if (createdValue is String) {
        created = DateTime.tryParse(createdValue);
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
