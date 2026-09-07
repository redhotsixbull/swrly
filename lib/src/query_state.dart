import 'package:flutter/foundation.dart';

enum QueryStatus { idle, loading, success, error }

/// Fields of [QueryState] that a subscriber can choose to observe. Passed to
/// `QueryBuilder(notifyOn: {…})` so a rebuild only fires when a listed field
/// actually changes — a cheap opt-in perf tuning for widgets that don't care
/// about, say, `isFetching` flicker.
enum QueryProp {
  status,
  data,
  hasData,
  error,
  updatedAt,
  isFetching,
  isPlaceholderData,
}

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
    this.isPlaceholderData = false,
  });

  const QueryState.idle()
      : status = QueryStatus.idle,
        data = null,
        hasData = false,
        error = null,
        stackTrace = null,
        updatedAt = null,
        isFetching = false,
        isPlaceholderData = false;

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

  /// Whether [data] is *placeholder* data — the previous key's value (with
  /// `keepPreviousData`) or a static `placeholderData` — shown while the real
  /// value for the current key is still loading. It is **not** cached and does
  /// not affect freshness; it exists only so the UI can avoid a loading flash
  /// (and optionally dim/label the stand-in). Real data has this `false`.
  final bool isPlaceholderData;

  bool get isIdle => status == QueryStatus.idle;
  bool get isLoading => status == QueryStatus.loading;
  bool get isSuccess => status == QueryStatus.success;
  bool get isError => status == QueryStatus.error;

  /// True if any of [props] differs between [this] and [other]. Compares by
  /// `==` for scalars and identity for `data` (a `queryFn` that returns a new
  /// list every call would break structural-equality comparison here).
  bool differsFrom(QueryState<T> other, Set<QueryProp> props) {
    for (final p in props) {
      switch (p) {
        case QueryProp.status:
          if (status != other.status) return true;
        case QueryProp.data:
          if (!identical(data, other.data)) return true;
        case QueryProp.hasData:
          if (hasData != other.hasData) return true;
        case QueryProp.error:
          if (error != other.error) return true;
        case QueryProp.updatedAt:
          if (updatedAt != other.updatedAt) return true;
        case QueryProp.isFetching:
          if (isFetching != other.isFetching) return true;
        case QueryProp.isPlaceholderData:
          if (isPlaceholderData != other.isPlaceholderData) return true;
      }
    }
    return false;
  }

  QueryState<T> copyWith({
    QueryStatus? status,
    Object? data = _unset,
    bool? hasData,
    Object? error = _unset,
    Object? stackTrace = _unset,
    DateTime? updatedAt,
    bool? isFetching,
    bool? isPlaceholderData,
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
      isPlaceholderData: isPlaceholderData ?? this.isPlaceholderData,
    );
  }
}
