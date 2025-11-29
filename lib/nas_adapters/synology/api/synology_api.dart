import 'package:dio/dio.dart';
import 'package:my_nas/core/errors/exceptions.dart';
import 'package:my_nas/core/utils/logger.dart';

/// Synology DSM API 客户端
class SynologyApi {
  SynologyApi({required Dio dio}) : _dio = dio;

  final Dio _dio;
  String? _sid;

  /// API 信息查询
  Future<Map<String, dynamic>> queryApiInfo() async {
    final response = await _request(
      'SYNO.API.Info',
      'query',
      version: 1,
      params: {'query': 'all'},
    );
    return response['data'] as Map<String, dynamic>;
  }

  /// 登录认证
  Future<AuthResult> login({
    required String account,
    required String password,
    String? otpCode,
  }) async {
    logger.i('SynologyApi: 开始登录认证');
    logger.d('SynologyApi: 账号 => $account, OTP => ${otpCode != null ? "有" : "无"}');

    final params = <String, dynamic>{
      'account': account,
      'passwd': password,
      'format': 'sid',
    };

    if (otpCode != null) {
      params['otp_code'] = otpCode;
    }

    try {
      // 登录请求需要特殊处理，因为认证错误也会返回 success=false
      final response = await _requestRaw(
        'SYNO.API.Auth',
        'login',
        version: 6,
        params: params,
      );

      logger.d('SynologyApi: 登录响应 => success=${response['success']}');

      if (response['success'] != true) {
        final errorCode = response['error']?['code'] as int?;
        logger.w('SynologyApi: 登录失败, 错误码 => $errorCode');
        return _handleAuthError(errorCode);
      }

      final data = response['data'] as Map<String, dynamic>;
      _sid = data['sid'] as String;

      logger.i('SynologyApi: 登录成功, sid => ${_sid!.substring(0, 8)}...');

      return AuthSuccess(
        sid: _sid!,
        deviceId: data['did'] as String?,
      );
    } catch (e, stackTrace) {
      logger.e('SynologyApi: 登录异常', e, stackTrace);
      rethrow;
    }
  }

  /// 登出
  Future<void> logout() async {
    if (_sid == null) return;

    await _request(
      'SYNO.API.Auth',
      'logout',
      version: 1,
    );
    _sid = null;
  }

  /// 获取 DSM 信息
  Future<DsmInfo> getDsmInfo() async {
    final response = await _request(
      'SYNO.DSM.Info',
      'getinfo',
      version: 2,
    );

    final data = response['data'] as Map<String, dynamic>;
    return DsmInfo(
      hostname: data['model'] as String? ?? 'Unknown',
      model: data['model'] as String?,
      version: data['version_string'] as String?,
      serial: data['serial'] as String?,
    );
  }

  /// 列出目录
  Future<List<FileStationFile>> listFiles({
    required String folderPath,
    int offset = 0,
    int limit = 100,
    String sortBy = 'name',
    String sortDirection = 'asc',
    List<String> additional = const ['size', 'time', 'type'],
  }) async {
    final response = await _request(
      'SYNO.FileStation.List',
      'list',
      version: 2,
      params: {
        'folder_path': folderPath,
        'offset': offset,
        'limit': limit,
        'sort_by': sortBy,
        'sort_direction': sortDirection,
        'additional': additional.join(','),
      },
    );

    final data = response['data'] as Map<String, dynamic>;
    final files = data['files'] as List<dynamic>? ?? [];

    return files
        .map((f) => FileStationFile.fromJson(f as Map<String, dynamic>))
        .toList();
  }

  /// 获取共享文件夹列表
  Future<List<ShareFolder>> listShareFolders() async {
    final response = await _request(
      'SYNO.FileStation.List',
      'list_share',
      version: 2,
      params: {
        'additional': 'volume_status',
      },
    );

    final data = response['data'] as Map<String, dynamic>;
    final shares = data['shares'] as List<dynamic>? ?? [];

    return shares
        .map((s) => ShareFolder.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  /// 获取文件信息
  Future<FileStationFile> getFileInfo(String path) async {
    final response = await _request(
      'SYNO.FileStation.List',
      'getinfo',
      version: 2,
      params: {
        'path': path,
        'additional': 'size,time,type',
      },
    );

    final data = response['data'] as Map<String, dynamic>;
    final files = data['files'] as List<dynamic>;
    return FileStationFile.fromJson(files.first as Map<String, dynamic>);
  }

  /// 创建文件夹
  Future<void> createFolder({
    required String folderPath,
    required String name,
  }) async {
    await _request(
      'SYNO.FileStation.CreateFolder',
      'create',
      version: 2,
      params: {
        'folder_path': folderPath,
        'name': name,
      },
    );
  }

  /// 删除文件/文件夹
  Future<String> deleteFiles(List<String> paths) async {
    final response = await _request(
      'SYNO.FileStation.Delete',
      'start',
      version: 2,
      params: {
        'path': paths.join(','),
        'recursive': true,
      },
    );

    final data = response['data'] as Map<String, dynamic>;
    return data['taskid'] as String;
  }

  /// 重命名
  Future<void> rename({
    required String path,
    required String name,
  }) async {
    await _request(
      'SYNO.FileStation.Rename',
      'rename',
      version: 2,
      params: {
        'path': path,
        'name': name,
      },
    );
  }

  /// 获取文件下载链接
  String getDownloadUrl(String path) {
    final params = {
      'api': 'SYNO.FileStation.Download',
      'version': '2',
      'method': 'download',
      'path': path,
      'mode': 'download',
      if (_sid != null) '_sid': _sid,
    };

    final queryString =
        params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value.toString())}').join('&');

    return '${_dio.options.baseUrl}/webapi/entry.cgi?$queryString';
  }

  /// 获取缩略图链接
  String getThumbnailUrl(String path, {String size = 'small'}) {
    final params = {
      'api': 'SYNO.FileStation.Thumb',
      'version': '2',
      'method': 'get',
      'path': path,
      'size': size,
      if (_sid != null) '_sid': _sid,
    };

    final queryString =
        params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value.toString())}').join('&');

    return '${_dio.options.baseUrl}/webapi/entry.cgi?$queryString';
  }

  /// 搜索文件
  Future<String> startSearch({
    required String folderPath,
    required String pattern,
  }) async {
    final response = await _request(
      'SYNO.FileStation.Search',
      'start',
      version: 2,
      params: {
        'folder_path': folderPath,
        'pattern': pattern,
      },
    );

    final data = response['data'] as Map<String, dynamic>;
    return data['taskid'] as String;
  }

  /// 获取搜索结果
  Future<SearchResult> getSearchResult(String taskId) async {
    final response = await _request(
      'SYNO.FileStation.Search',
      'list',
      version: 2,
      params: {
        'taskid': taskId,
        'additional': 'size,time,type',
      },
    );

    final data = response['data'] as Map<String, dynamic>;
    final files = (data['files'] as List<dynamic>? ?? [])
        .map((f) => FileStationFile.fromJson(f as Map<String, dynamic>))
        .toList();

    return SearchResult(
      files: files,
      finished: data['finished'] as bool? ?? false,
      total: data['total'] as int? ?? 0,
    );
  }

  /// 原始请求方法 - 不检查 success 字段，用于登录等需要自行处理错误的场景
  Future<Map<String, dynamic>> _requestRaw(
    String api,
    String method, {
    required int version,
    Map<String, dynamic>? params,
  }) async {
    final queryParams = <String, dynamic>{
      'api': api,
      'version': version,
      'method': method,
      if (_sid != null) '_sid': _sid,
      ...?params,
    };

    logger.d('SynologyApi: 原始请求 => $api.$method (v$version)');

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/webapi/entry.cgi',
        queryParameters: queryParams,
      );

      final data = response.data;
      logger.d('SynologyApi: 响应状态码 => ${response.statusCode}');

      if (data == null) {
        logger.e('SynologyApi: 服务器返回空数据');
        throw const ServerException(message: '服务器返回空数据');
      }

      return data;
    } on DioException catch (e) {
      logger.e('SynologyApi: Dio 异常 => ${e.type}', e, e.stackTrace);
      logger.e('SynologyApi: 原始错误 => ${e.error}');
      logger.e('SynologyApi: 消息 => ${e.message}');
      rethrow;
    }
  }

  /// 通用请求方法
  Future<Map<String, dynamic>> _request(
    String api,
    String method, {
    required int version,
    Map<String, dynamic>? params,
  }) async {
    final queryParams = <String, dynamic>{
      'api': api,
      'version': version,
      'method': method,
      if (_sid != null) '_sid': _sid,
      ...?params,
    };

    logger.d('SynologyApi: 请求 => $api.$method (v$version)');

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/webapi/entry.cgi',
        queryParameters: queryParams,
      );

      final data = response.data;
      logger.d('SynologyApi: 响应状态码 => ${response.statusCode}');

      if (data == null) {
        logger.e('SynologyApi: 服务器返回空数据');
        throw const ServerException(message: '服务器返回空数据');
      }

      if (data['success'] != true) {
        final errorCode = data['error']?['code'] as int?;
        final errorMsg = _getErrorMessage(errorCode);
        logger.e('SynologyApi: API 错误 => $errorMsg (code: $errorCode)');
        throw ServerException(
          message: errorMsg,
          statusCode: errorCode,
        );
      }

      logger.d('SynologyApi: 请求成功');
      return data;
    } on DioException catch (e) {
      logger.e('SynologyApi: Dio 异常 => ${e.type}', e, e.stackTrace);
      logger.e('SynologyApi: 原始错误 => ${e.error}');
      logger.e('SynologyApi: 消息 => ${e.message}');
      rethrow;
    }
  }

  AuthResult _handleAuthError(int? errorCode) => switch (errorCode) {
        400 => const AuthFailure(error: '账号或密码错误'),
        401 => const AuthFailure(error: '账号已禁用'),
        402 => const AuthFailure(error: '权限不足'),
        403 => const AuthRequires2FA(),
        404 => const AuthFailure(error: '二次验证失败'),
        406 => const AuthFailure(error: '需要强制更改密码'),
        407 => const AuthFailure(error: 'IP 被封禁'),
        _ => AuthFailure(error: '认证失败 (错误码: $errorCode)'),
      };

  String _getErrorMessage(int? errorCode) => switch (errorCode) {
        101 => '无效参数',
        102 => 'API 不存在',
        103 => '方法不存在',
        104 => '版本不支持',
        105 => '权限不足',
        106 => '会话超时',
        107 => '重复登录',
        _ => '未知错误 ($errorCode)',
      };
}

/// 认证结果
sealed class AuthResult {
  const AuthResult();
}

class AuthSuccess extends AuthResult {
  const AuthSuccess({required this.sid, this.deviceId});
  final String sid;
  final String? deviceId;
}

class AuthFailure extends AuthResult {
  const AuthFailure({required this.error});
  final String error;
}

class AuthRequires2FA extends AuthResult {
  const AuthRequires2FA();
}

/// DSM 信息
class DsmInfo {
  const DsmInfo({
    required this.hostname,
    this.model,
    this.version,
    this.serial,
  });

  final String hostname;
  final String? model;
  final String? version;
  final String? serial;
}

/// 共享文件夹
class ShareFolder {
  const ShareFolder({
    required this.name,
    required this.path,
    this.isDir = true,
  });

  factory ShareFolder.fromJson(Map<String, dynamic> json) => ShareFolder(
        name: json['name'] as String,
        path: json['path'] as String,
      );

  final String name;
  final String path;
  final bool isDir;
}

/// FileStation 文件
class FileStationFile {
  const FileStationFile({
    required this.name,
    required this.path,
    required this.isDir,
    this.size = 0,
    this.createTime,
    this.modifyTime,
    this.type,
  });

  factory FileStationFile.fromJson(Map<String, dynamic> json) {
    final additional = json['additional'] as Map<String, dynamic>? ?? {};
    final time = additional['time'] as Map<String, dynamic>?;

    return FileStationFile(
      name: json['name'] as String,
      path: json['path'] as String,
      isDir: json['isdir'] as bool? ?? false,
      size: additional['size'] as int? ?? 0,
      createTime: time?['crtime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (time!['crtime'] as int) * 1000,
            )
          : null,
      modifyTime: time?['mtime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (time!['mtime'] as int) * 1000,
            )
          : null,
      type: additional['type'] as String?,
    );
  }

  final String name;
  final String path;
  final bool isDir;
  final int size;
  final DateTime? createTime;
  final DateTime? modifyTime;
  final String? type;
}

/// 搜索结果
class SearchResult {
  const SearchResult({
    required this.files,
    required this.finished,
    required this.total,
  });

  final List<FileStationFile> files;
  final bool finished;
  final int total;
}
