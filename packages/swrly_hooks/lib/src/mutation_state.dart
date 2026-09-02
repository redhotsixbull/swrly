import 'package:flutter/foundation.dart';

/// Small envelope returned by [useSwrlyMutation] so callers have something
/// to switch on without pulling in swrly's `MutationBuilder` internals.
@immutable
class MutationState<T> {
  const MutationState._(
    this.status, {
    this.data,
    this.error,
    this.stackTrace,
  });

  const MutationState.idle() : this._(MutationStatus.idle);
  const MutationState.loading() : this._(MutationStatus.loading);
  const MutationState.success(T value)
      : this._(MutationStatus.success, data: value);
  const MutationState.error(Object err, StackTrace? st)
      : this._(MutationStatus.error, error: err, stackTrace: st);

  final MutationStatus status;
  final T? data;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isLoading => status == MutationStatus.loading;
  bool get isSuccess => status == MutationStatus.success;
  bool get isError => status == MutationStatus.error;
}

enum MutationStatus { idle, loading, success, error }
