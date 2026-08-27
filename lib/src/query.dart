import 'dart:async';

import 'package:flutter/foundation.dart';

import 'query_client.dart';
import 'query_key.dart';
import 'query_state.dart';

/// A reusable **definition** of one query: the key, the fetch function and the
/// per-query options, declared once and consumed from anywhere.
///
/// `QueryBuilder` and [QueryClient.fetchQuery] both need a `(key, fn)` pair, so
/// without a definition object you re-type that pair at every call site — and a
/// typo in the key is a silent cache miss rather than a compile error. A
/// [Query] is that pair, named:
///
/// ```dart
/// final postsQuery = Query<List<Post>>(
///   key: const ['posts'],
///   fn: () => api.getPosts(),
///   staleTime: const Duration(seconds: 30),
/// );
///
/// await postsQuery.fetch();                       // imperative
/// QueryBuilder.of(postsQuery, builder: ...);      // declarative
/// postsQuery.invalidate();                        // cache control
/// ```
///
/// It holds **no state** — the cache still lives in [QueryClient]. A [Query] is
/// a value object you can create per call if you like; two instances with the
/// same key address the same cache entry.
///
/// For queries that take an argument (`['post', id]`), see [QueryFamily].
@immutable
class Query<T> {
  const Query({
    required this.key,
    required this.fn,
    this.staleTime,
    this.retry,
    this.retryDelay,
    this.client,
  });

  /// The cache key this query reads and writes. Identifies exactly one entry.
  final QueryKey key;

  /// The fetch function. Stored as a field, so — unlike an inline closure that
  /// changes identity every build — an invalidation-driven refetch always runs
  /// this exact closure.
  final QueryFn<T> fn;

  /// How long a fetched value counts as fresh. Falls back to the client's
  /// `defaultStaleTime` when null.
  final Duration? staleTime;

  /// Retries (attempts after the first) when [fn] throws. Falls back to the
  /// client's `defaultRetry` when null.
  final int? retry;

  /// Backoff before each retry. Falls back to the client's `defaultRetryDelay`
  /// when null.
  final RetryDelay? retryDelay;

  /// The cache this query targets. Defaults to [QueryClient.instance].
  final QueryClient? client;

  QueryClient get _client => client ?? QueryClient.instance;

  /// Fetches through the cache: returns the cached value if it is still fresh,
  /// joins an in-flight request for the same key, otherwise runs [fn].
  ///
  /// This is exactly what `QueryBuilder` does internally, so a mounted builder
  /// on this key sees the result of this call.
  Future<T> fetch() => _client.fetchQuery<T>(
        key: key,
        fn: fn,
        staleTime: staleTime,
        retry: retry,
        retryDelay: retryDelay,
      );

  /// Fetches **past** [staleTime] — always runs [fn] (still deduped against an
  /// in-flight request). The pull-to-refresh / retry-button call.
  Future<T> refetch() => _client.fetchQuery<T>(
        key: key,
        fn: fn,
        staleTime: Duration.zero,
        retry: retry,
        retryDelay: retryDelay,
      );

  /// The cached value, or null if this key holds nothing. Synchronous; never
  /// fetches.
  T? get data => _client.getQueryData<T>(key);

  /// The current state for this key. Synchronous; never fetches.
  QueryState<T> get state => _client.stateOf<T>(key);

  /// A broadcast stream of state changes for this key.
  ///
  /// Like [QueryClient.observe], listening does **not** register a subscriber,
  /// so it does not hold the entry against `cacheTime` GC the way a mounted
  /// `QueryBuilder` does.
  Stream<QueryState<T>> get stream => _client.observe<T>(key);

  /// Writes a value directly, skipping [fn] — the optimistic-update path.
  void setData(T value) => _client.setQueryData<T>(key, value);

  /// Marks **this key only** stale (see [QueryFamily.invalidateAll] or
  /// [QueryClient.invalidateQueries] for prefix-wide invalidation). With
  /// `refetch: true` (the default) an entry that currently has subscribers is
  /// refetched immediately.
  void invalidate({bool refetch = true}) => _client.invalidateQueriesWhere(
        (candidate) => QueryKeyHash.of(candidate) == QueryKeyHash.of(key),
        refetch: refetch,
      );

  /// Drops **this key only** from the cache.
  void remove() => _client.removeQueriesWhere(
        (candidate) => QueryKeyHash.of(candidate) == QueryKeyHash.of(key),
      );

  /// A copy of this definition with individual options overridden — e.g. a
  /// one-off `staleTime` at a call site, or pointing a shared definition at a
  /// test [QueryClient].
  Query<T> copyWith({
    QueryKey? key,
    QueryFn<T>? fn,
    Duration? staleTime,
    int? retry,
    RetryDelay? retryDelay,
    QueryClient? client,
  }) {
    return Query<T>(
      key: key ?? this.key,
      fn: fn ?? this.fn,
      staleTime: staleTime ?? this.staleTime,
      retry: retry ?? this.retry,
      retryDelay: retryDelay ?? this.retryDelay,
      client: client ?? this.client,
    );
  }

  @override
  String toString() => 'Query<$T>(${QueryKeyHash.of(key)})';
}

/// A parameterised [Query] — one definition covering every argument.
///
/// ```dart
/// final postQuery = QueryFamily<Post, int>(
///   prefix: const ['post'],
///   fn: (id) => api.getPost(id),
/// );
///
/// await postQuery(3).fetch();   // key ['post', 3]
/// postQuery(3).invalidate();    // just that one
/// postQuery.invalidateAll();    // every ['post', …]
/// ```
///
/// Keys are always `[...prefix, ...argument]`, so [invalidateAll] / [removeAll]
/// are correct by construction — every member of the family shares [prefix].
@immutable
class QueryFamily<T, A> {
  const QueryFamily({
    required this.prefix,
    required this.fn,
    this.argKey,
    this.staleTime,
    this.retry,
    this.retryDelay,
    this.client,
  });

  /// The shared leading segment of every member's key.
  final QueryKey prefix;

  /// The fetch function, given the argument.
  final Future<T> Function(A arg) fn;

  /// Maps an argument to the key segments appended after [prefix]. Defaults to
  /// `[arg]`, which is right for primitives; supply this when the argument is a
  /// record or a custom object, so the key is built from primitives rather than
  /// falling back to `toString()`:
  ///
  /// ```dart
  /// QueryFamily<PostPage, (int, String)>(
  ///   prefix: const ['posts'],
  ///   argKey: (a) => [a.$1, a.$2],   // ['posts', 2, 'flutter']
  ///   fn: (a) => api.getPosts(page: a.$1, q: a.$2),
  /// );
  /// ```
  final QueryKey Function(A arg)? argKey;

  /// Applied to every member. See [Query.staleTime].
  final Duration? staleTime;

  /// Applied to every member. See [Query.retry].
  final int? retry;

  /// Applied to every member. See [Query.retryDelay].
  final RetryDelay? retryDelay;

  /// Applied to every member. See [Query.client].
  final QueryClient? client;

  QueryClient get _client => client ?? QueryClient.instance;

  /// The cache key for [arg]: `[...prefix, ...argKey(arg)]`.
  QueryKey keyFor(A arg) => [...prefix, ...(argKey?.call(arg) ?? [arg])];

  /// The [Query] for [arg]. Call the family directly — `postQuery(3)`.
  Query<T> call(A arg) => Query<T>(
        key: keyFor(arg),
        fn: () => fn(arg),
        staleTime: staleTime,
        retry: retry,
        retryDelay: retryDelay,
        client: client,
      );

  /// Marks every member of the family stale (everything under [prefix]).
  void invalidateAll({bool refetch = true}) =>
      _client.invalidateQueries(prefix, refetch: refetch);

  /// Drops every member of the family from the cache.
  void removeAll() => _client.removeQueries(prefix);

  @override
  String toString() => 'QueryFamily<$T, $A>(${QueryKeyHash.of(prefix)})';
}
