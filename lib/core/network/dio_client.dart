import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/errors/exceptions.dart';
import 'package:my_nas/core/utils/logger.dart';

class DioClient {
  DioClient({String? baseUrl, bool allowSelfSigned = false}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? '',
        connectTimeout: AppConstants.connectionTimeout,
        receiveTimeout: AppConstants.receiveTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.addAll([
      _LoggingInterceptor(),
      _ErrorInterceptor(),
    ]);

    if (allowSelfSigned) {
      setAllowSelfSignedCert(true);
    }
  }

  late final Dio _dio;

  Dio get dio => _dio;

  void updateBaseUrl(String baseUrl) {
    logger.i('DioClient: 更新 baseUrl => $baseUrl');
    _dio.options.baseUrl = baseUrl;
  }

  void updateHeaders(Map<String, dynamic> headers) {
    _dio.options.headers.addAll(headers);
  }

  void addInterceptor(Interceptor interceptor) {
    _dio.interceptors.add(interceptor);
  }

  /// 设置是否允许自签名证书
  void setAllowSelfSignedCert(bool allow) {
    if (allow) {
      logger.i('DioClient: 允许自签名 SSL 证书');
      (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) {
          logger.w('DioClient: 接受自签名证书 - host: $host, port: $port');
          return true;
        };
        return client;
      };
    }
  }
}

class _LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    logger.d(
      'REQUEST[${options.method}] => PATH: ${options.path}',
    );
    super.onRequest(options, handler);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    logger.d(
      'RESPONSE[${response.statusCode}] => PATH: ${response.requestOptions.path}',
    );
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    logger.e(
      'ERROR[${err.response?.statusCode}] => PATH: ${err.requestOptions.path}',
      err,
      err.stackTrace,
    );
    super.onError(err, handler);
  }
}

class _ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final exception = switch (err.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        NetworkException(
          message: '连接超时',
          stackTrace: err.stackTrace,
        ),
      DioExceptionType.connectionError => NetworkException(
          message: '网络连接失败',
          stackTrace: err.stackTrace,
        ),
      DioExceptionType.badResponse => _handleBadResponse(err),
      DioExceptionType.cancel => NetworkException(
          message: '请求已取消',
          stackTrace: err.stackTrace,
        ),
      _ => ServerException(
          message: err.message ?? '未知错误',
          stackTrace: err.stackTrace,
          statusCode: err.response?.statusCode,
        ),
    };

    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        error: exception,
        type: err.type,
        response: err.response,
      ),
    );
  }

  AppException _handleBadResponse(DioException err) {
    final statusCode = err.response?.statusCode;
    return switch (statusCode) {
      401 => AuthException(
          message: '认证失败',
          stackTrace: err.stackTrace,
        ),
      403 => AuthException(
          message: '权限不足',
          stackTrace: err.stackTrace,
        ),
      404 => ServerException(
          message: '资源不存在',
          statusCode: statusCode,
          stackTrace: err.stackTrace,
        ),
      final code when code != null && code >= 500 => ServerException(
          message: '服务器错误',
          statusCode: code,
          stackTrace: err.stackTrace,
        ),
      _ => ServerException(
          message: err.message ?? '请求失败',
          statusCode: statusCode,
          stackTrace: err.stackTrace,
        ),
    };
  }
}
