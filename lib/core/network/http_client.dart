import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 支持自签名证书的 HTTP 客户端
class InsecureHttpClient {
  InsecureHttpClient._();

  static http.Client? _client;

  /// 获取允许自签名证书的 HTTP 客户端
  static http.Client get client {
    if (_client != null) return _client!;

    final httpClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;

    _client = IOClient(httpClient);
    return _client!;
  }

  /// GET 请求
  static Future<http.Response> get(Uri url, {Map<String, String>? headers}) {
    return client.get(url, headers: headers);
  }

  /// POST 请求
  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return client.post(url, headers: headers, body: body);
  }

  /// PUT 请求
  static Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return client.put(url, headers: headers, body: body);
  }

  /// DELETE 请求
  static Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
  }) {
    return client.delete(url, headers: headers);
  }

  /// 关闭客户端
  static void close() {
    _client?.close();
    _client = null;
  }
}
