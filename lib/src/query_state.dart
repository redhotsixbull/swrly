import 'package:flutter/foundation.dart';

enum QueryStatus { idle, loading, success, error }

@immutable
class QueryState<T> {
  const QueryState({
    required this.status,
    this.data,
    this.error,
    this.stackTrace,
    this.updatedAt,
    this.isFetching = false,
  });

  const QueryState.idle()
      : status = QueryStatus.idle,
        data = null,
        error = null,
        stackTrace = null,
        updatedAt = null,
        isFetching = false;

  final QueryStatus status;
  final T? data;
  final Object? error;
  final StackTrace? stackTrace;
  final DateTime? updatedAt;
  final bool isFetching;

  bool get isIdle => status == QueryStatus.idle;
  bool get isLoading => status == QueryStatus.loading;
  bool get isSuccess => status == QueryStatus.success;
  bool get isError => status == QueryStatus.error;
  bool get hasData => data != null;

  QueryState<T> copyWith({
    QueryStatus? status,
    T? data,
    Object? error,
    StackTrace? stackTrace,
    DateTime? updatedAt,
    bool? isFetching,
  }) {
    return QueryState<T>(
      status: status ?? this.status,
      data: data ?? this.data,
      error: error ?? this.error,
      stackTrace: stackTrace ?? this.stackTrace,
      updatedAt: updatedAt ?? this.updatedAt,
      isFetching: isFetching ?? this.isFetching,
    );
  }
}
