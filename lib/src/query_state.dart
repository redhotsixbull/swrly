import 'package:flutter/foundation.dart';

enum QueryStatus { idle, loading, success, error }

/// Sentinel distinguishing "argument omitted" from "explicitly passed null" in
/// [QueryState.copyWith], so a success/loading transition can *clear* a stale
/// [error]/[stackTrace] instead of silently inheriting it.
const Object _unset = Object();

@immutable
class QueryState<T> {
  const QueryState({
    required this.status,
    this.data,
    this.hasData = false,
    this.error,
    this.stackTrace,
    this.updatedAt,
    this.isFetching = false,
  });

  const QueryState.idle()
      : status = QueryStatus.idle,
        data = null,
        hasData = false,
        error = null,
        stackTrace = null,
        updatedAt = null,
        isFetching = false;

  final QueryStatus status;
  final T? data;

  /// Whether [data] holds a value produced by a successful fetch. This is
  /// distinct from `data != null`: a query that legitimately resolves to `null`
  /// still "has data" (see SPEC §2). The flag is retained across an error
  /// transition, so last-good data survives (`isError && hasData` is possible).
  final bool hasData;

  final Object? error;
  final StackTrace? stackTrace;
  final DateTime? updatedAt;
  final bool isFetching;

  bool get isIdle => status == QueryStatus.idle;
  bool get isLoading => status == QueryStatus.loading;
  bool get isSuccess => status == QueryStatus.success;
  bool get isError => status == QueryStatus.error;

  QueryState<T> copyWith({
    QueryStatus? status,
    Object? data = _unset,
    bool? hasData,
    Object? error = _unset,
    Object? stackTrace = _unset,
    DateTime? updatedAt,
    bool? isFetching,
  }) {
    return QueryState<T>(
      status: status ?? this.status,
      data: identical(data, _unset) ? this.data : data as T?,
      hasData: hasData ?? this.hasData,
      error: identical(error, _unset) ? this.error : error,
      stackTrace: identical(stackTrace, _unset)
          ? this.stackTrace
          : stackTrace as StackTrace?,
      updatedAt: updatedAt ?? this.updatedAt,
      isFetching: isFetching ?? this.isFetching,
    );
  }
}
