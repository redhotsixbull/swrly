import 'package:flutter/foundation.dart';

enum MutationStatus { idle, loading, success, error }

@immutable
class MutationState<T> {
  const MutationState({
    required this.status,
    this.data,
    this.error,
    this.stackTrace,
  });

  const MutationState.idle()
      : status = MutationStatus.idle,
        data = null,
        error = null,
        stackTrace = null;

  final MutationStatus status;
  final T? data;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isIdle => status == MutationStatus.idle;
  bool get isLoading => status == MutationStatus.loading;
  bool get isSuccess => status == MutationStatus.success;
  bool get isError => status == MutationStatus.error;
}
