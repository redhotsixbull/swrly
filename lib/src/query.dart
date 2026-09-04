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
    this.initialData,
    this.initialDataUpdatedAt,
    this.refetchInterval,
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

  /// Seeds the cache with a value at first observation of this key — a real
  /// success value, not a placeholder. Only invoked when the entry is empty
  /// (fresh mount or after `cacheTime` GC); a subsequent fetch or another
  /// subscriber does not re-seed.
  ///
  /// Function form (rather than a plain value) avoids the "was `null` an
  /// omitted default or a legitimate initial value?" ambiguity, and lets the
  /// caller defer computation until swrly actually needs the value.
  ///
  /// Pair with [initialDataUpdatedAt] to teach [staleTime] how old the seed
  /// really is (e.g. hydrated from server state minutes ago).
  final T Function()? initialData;

  /// Wall-clock timestamp of when [initialData] was fresh. If `null`, swrly
  /// treats the seed as "fresh right now" — no refetch fires until [staleTime]
  /// elapses. Set this to an older `DateTime` when hydrating from a slow
  /// source so the freshness clock is honest.
  final DateTime? initialDataUpdatedAt;

  /// Polls this query at the given interval — for dashboards, status widgets,
  /// near-real-time UIs. `null` (the default) disables polling.
  ///
  /// Ticks only while the entry has ≥1 subscriber (nothing polls a dead key)
  /// and pauses when the last subscriber leaves. Each tick behaves like
  /// [refetch]: bypasses [staleTime] and dedupes against an in-flight request.
  final Duration? refetchInterval;

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
        initialData: initialData,
        initialDataUpdatedAt: initialDataUpdatedAt,
        refetchInterval: refetchInterval,
      );

  /// Fetches **past** [staleTime] — always runs [fn] (still deduped against an
  /// in-flight request). The pull-to-refresh / retry-button call.
  ///
  /// [refetchInterval] is forwarded intentionally — a manual refresh must not
  /// clear a polling schedule that the definition already configured.
  Future<T> refetch() => _client.fetchQuery<T>(
        key: key,
        fn: fn,
        staleTime: Duration.zero,
        retry: retry,
        retryDelay: retryDelay,
        refetchInterval: refetchInterval,
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
    T Function()? initialData,
    DateTime? initialDataUpdatedAt,
    Duration? refetchInterval,
    QueryClient? client,
  }) {
    return Query<T>(
      key: key ?? this.key,
      fn: fn ?? this.fn,
      staleTime: staleTime ?? this.staleTime,
      retry: retry ?? this.retry,
      retryDelay: retryDelay ?? this.retryDelay,
      initialData: initialData ?? this.initialData,
      initialDataUpdatedAt: initialDataUpdatedAt ?? this.initialDataUpdatedAt,
      refetchInterval: refetchInterval ?? this.refetchInterval,
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
    this.initialData,
    this.initialDataUpdatedAt,
    this.refetchInterval,
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

  /// Applied to every member with its argument. See [Query.initialData]. Given
  /// the argument so each member can synthesize its own seed (e.g. a stub
  /// `Post` shaped from a list-view item).
  final T Function(A arg)? initialData;

  /// Applied to every member. See [Query.initialDataUpdatedAt].
  final DateTime? initialDataUpdatedAt;

  /// Applied to every member. See [Query.refetchInterval].
  final Duration? refetchInterval;

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
        initialData: initialData == null ? null : () => initialData!(arg),
        initialDataUpdatedAt: initialDataUpdatedAt,
        refetchInterval: refetchInterval,
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
