sealed class AppException implements Exception {
  const AppException({this.message, this.stackTrace});

  final String? message;
  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType: $message';
}

final class ServerException extends AppException {
  const ServerException({
    super.message,
    super.stackTrace,
    this.statusCode,
  });

  final int? statusCode;
}

final class NetworkException extends AppException {
  const NetworkException({super.message, super.stackTrace});
}

final class CacheException extends AppException {
  const CacheException({super.message, super.stackTrace});
}

final class AuthException extends AppException {
  const AuthException({super.message, super.stackTrace});
}

final class ConnectionException extends AppException {
  const ConnectionException({super.message, super.stackTrace});
}

final class ValidationException extends AppException {
  const ValidationException({super.message, super.stackTrace});
}
