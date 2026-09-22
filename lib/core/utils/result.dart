import 'package:flutter/foundation.dart';
import '../errors/failures.dart';

// FIX-A2: Provide AppResult<T> alias for unified domain outcome handling
typedef AppResult<T> = Result<T>;

/// A sealed class representing the outcome of an operation or async state:
/// [ResultSuccess], [ResultFailure], or [ResultLoading].
@immutable
sealed class Result<T> {
  const Result();

  const factory Result.success(T data) = ResultSuccess<T>;
  const factory Result.failure(AppFailure failure, [String? message]) = ResultFailure<T>;
  const factory Result.loading() = ResultLoading<T>;

  bool get isSuccess => this is ResultSuccess<T>;
  bool get isFailure => this is ResultFailure<T>;
  bool get isLoading => this is ResultLoading<T>;

  T? get dataOrNull => switch (this) {
        ResultSuccess<T>(data: final d) => d,
        _ => null,
      };

  AppFailure? get failureOrNull => switch (this) {
        ResultFailure<T>(failure: final f) => f,
        _ => null,
      };

  R when<R>({
    required R Function(T data) success,
    required R Function(AppFailure failure, String? message) failure,
    required R Function() loading,
  }) =>
      switch (this) {
        ResultSuccess<T>(data: final d) => success(d),
        ResultFailure<T>(failure: final f, message: final m) => failure(f, m),
        ResultLoading<T>() => loading(),
      };

  R fold<R>(
    R Function(AppFailure failure) onFailure,
    R Function(T data) onSuccess,
  ) =>
      switch (this) {
        ResultSuccess<T>(data: final d) => onSuccess(d),
        ResultFailure<T>(failure: final f) => onFailure(f),
        ResultLoading<T>() =>
          onFailure(const DatabaseFailure('Operation is loading')),
      };
}

class ResultSuccess<T> extends Result<T> {
  final T data;
  const ResultSuccess(this.data);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResultSuccess<T> &&
          runtimeType == other.runtimeType &&
          data == other.data;

  @override
  int get hashCode => data.hashCode;
}

class ResultFailure<T> extends Result<T> {
  final AppFailure failure;
  final String? message;
  const ResultFailure(this.failure, [this.message]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResultFailure<T> &&
          runtimeType == other.runtimeType &&
          failure == other.failure &&
          message == other.message;

  @override
  int get hashCode => Object.hash(failure, message);
}

class ResultLoading<T> extends Result<T> {
  const ResultLoading();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResultLoading<T> && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}
