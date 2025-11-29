import 'package:equatable/equatable.dart';

sealed class Failure extends Equatable {
  const Failure({this.message, this.stackTrace});

  final String? message;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => [message];
}

final class ServerFailure extends Failure {
  const ServerFailure({
    super.message,
    super.stackTrace,
    this.statusCode,
  });

  final int? statusCode;

  @override
  List<Object?> get props => [message, statusCode];
}

final class NetworkFailure extends Failure {
  const NetworkFailure({super.message, super.stackTrace});
}

final class CacheFailure extends Failure {
  const CacheFailure({super.message, super.stackTrace});
}

final class AuthFailure extends Failure {
  const AuthFailure({super.message, super.stackTrace});
}

final class ConnectionFailure extends Failure {
  const ConnectionFailure({super.message, super.stackTrace});
}

final class ValidationFailure extends Failure {
  const ValidationFailure({super.message, super.stackTrace});
}

final class UnknownFailure extends Failure {
  const UnknownFailure({super.message, super.stackTrace});
}
