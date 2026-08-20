import 'dart:async';

import 'package:flutter/foundation.dart';

import 'query_key.dart';
import 'query_state.dart';

typedef QueryFn<T> = Future<T> Function();

class QueryEntry<T> {
  QueryEntry(this.key);

  final QueryKey key;
  QueryState<T> state = const QueryState<Never>.idle() as QueryState<T>;
  Future<T>? _inflight;
  Timer? _gcTimer;
  int subscribers = 0;

  final _controller = StreamController<QueryState<T>>.broadcast();

  Stream<QueryState<T>> get stream => _controller.stream;

  void _emit(QueryState<T> next) {
    state = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  void dispose() {
    _gcTimer?.cancel();
    _controller.close();
  }
}

class QueryClient {
  QueryClient({
    this.defaultStaleTime = Duration.zero,
    this.defaultCacheTime = const Duration(minutes: 5),
  });

  static final QueryClient instance = QueryClient();

  final Duration defaultStaleTime;
  final Duration defaultCacheTime;

  final Map<QueryKeyHash, QueryEntry<Object?>> _entries = {};

  @visibleForTesting
  int get entryCount => _entries.length;

  QueryEntry<T> _entryFor<T>(QueryKey key) {
    final hash = QueryKeyHash.of(key);
    final existing = _entries[hash];
    if (existing != null) return existing as QueryEntry<T>;
    final created = QueryEntry<T>(key);
    _entries[hash] = created as QueryEntry<Object?>;
    return created;
  }

  Stream<QueryState<T>> observe<T>(QueryKey key) {
    final entry = _entryFor<T>(key);
    return entry.stream;
  }

  QueryState<T> stateOf<T>(QueryKey key) {
    final entry = _entryFor<T>(key);
    return entry.state;
  }

  Future<T> fetchQuery<T>({
    required QueryKey key,
    required QueryFn<T> fn,
    Duration? staleTime,
  }) {
    final entry = _entryFor<T>(key);
    final effectiveStale = staleTime ?? defaultStaleTime;

    final now = DateTime.now();
    final fresh = entry.state.updatedAt != null &&
        now.difference(entry.state.updatedAt!) < effectiveStale;
    if (fresh && entry.state.isSuccess && entry.state.data != null) {
      return Future.value(entry.state.data as T);
    }

    final inflight = entry._inflight;
    if (inflight != null) return inflight;

    final future = _runFetch<T>(entry, fn);
    entry._inflight = future;
    return future;
  }

  Future<T> _runFetch<T>(QueryEntry<T> entry, QueryFn<T> fn) async {
    entry._emit(entry.state.copyWith(
      status: entry.state.isSuccess ? entry.state.status : QueryStatus.loading,
      isFetching: true,
    ));
    try {
      final result = await fn();
      entry._emit(QueryState<T>(
        status: QueryStatus.success,
        data: result,
        updatedAt: DateTime.now(),
        isFetching: false,
      ));
      return result;
    } catch (e, st) {
      entry._emit(entry.state.copyWith(
        status: QueryStatus.error,
        error: e,
        stackTrace: st,
        isFetching: false,
      ));
      rethrow;
    } finally {
      entry._inflight = null;
    }
  }

  void invalidateQueries(QueryKey prefix, {bool refetch = true}) {
    for (final entry in _entries.values) {
      if (!queryKeyStartsWith(entry.key, prefix)) continue;
      entry._emit(entry.state.copyWith(
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ));
      // Individual QueryBuilders will refetch on rebuild when refetch=true.
    }
  }

  void setQueryData<T>(QueryKey key, T data) {
    final entry = _entryFor<T>(key);
    entry._emit(QueryState<T>(
      status: QueryStatus.success,
      data: data,
      updatedAt: DateTime.now(),
      isFetching: false,
    ));
  }

  T? getQueryData<T>(QueryKey key) {
    final entry = _entries[QueryKeyHash.of(key)];
    return entry?.state.data as T?;
  }

  void removeQueries(QueryKey prefix) {
    _entries.removeWhere((_, entry) {
      final match = queryKeyStartsWith(entry.key, prefix);
      if (match) entry.dispose();
      return match;
    });
  }

  void clear() {
    for (final entry in _entries.values) {
      entry.dispose();
    }
    _entries.clear();
  }

  void _onSubscribe<T>(QueryKey key) {
    final entry = _entryFor<T>(key);
    entry.subscribers += 1;
    entry._gcTimer?.cancel();
    entry._gcTimer = null;
  }

  void _onUnsubscribe<T>(QueryKey key) {
    final entry = _entries[QueryKeyHash.of(key)];
    if (entry == null) return;
    entry.subscribers = (entry.subscribers - 1).clamp(0, 1 << 31);
    if (entry.subscribers == 0) {
      entry._gcTimer?.cancel();
      entry._gcTimer = Timer(defaultCacheTime, () {
        _entries.remove(QueryKeyHash.of(key));
        entry.dispose();
      });
    }
  }
}

extension QueryClientInternal on QueryClient {
  void onSubscribe<T>(QueryKey key) => _onSubscribe<T>(key);
  void onUnsubscribe<T>(QueryKey key) => _onUnsubscribe<T>(key);
}
