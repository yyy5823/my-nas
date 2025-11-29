import 'package:my_nas/core/errors/failures.dart';

sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Error<T>;

  T? get valueOrNull => switch (this) {
        Success(:final value) => value,
        Error() => null,
      };

  Failure? get failureOrNull => switch (this) {
        Success() => null,
        Error(:final failure) => failure,
      };

  R when<R>({
    required R Function(T value) success,
    required R Function(Failure failure) error,
  }) =>
      switch (this) {
        Success(:final value) => success(value),
        Error(:final failure) => error(failure),
      };

  Result<R> map<R>(R Function(T value) transform) => switch (this) {
        Success(:final value) => Success(transform(value)),
        Error(:final failure) => Error(failure),
      };

  Future<Result<R>> mapAsync<R>(Future<R> Function(T value) transform) async =>
      switch (this) {
        Success(:final value) => Success(await transform(value)),
        Error(:final failure) => Error(failure),
      };

  Result<R> flatMap<R>(Result<R> Function(T value) transform) => switch (this) {
        Success(:final value) => transform(value),
        Error(:final failure) => Error(failure),
      };
}

final class Success<T> extends Result<T> {
  const Success(this.value);

  final T value;
}

final class Error<T> extends Result<T> {
  const Error(this.failure);

  final Failure failure;
}
