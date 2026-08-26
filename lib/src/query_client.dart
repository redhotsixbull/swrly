import 'dart:async';

import 'package:flutter/foundation.dart';

import 'query_key.dart';
import 'query_state.dart';

typedef QueryFn<T> = Future<T> Function();

/// Computes the delay before retry attempt [attempt] (1-based: `1` is the first
/// retry). Return [Duration.zero] for an immediate retry.
typedef RetryDelay = Duration Function(int attempt);

/// Default backoff: exponential from 1s, doubling each attempt, capped at 30s
/// (1s, 2s, 4s, 8s, …). Mirrors TanStack Query's default.
Duration defaultRetryDelayFn(int attempt) {
  final exp = attempt <= 0 ? 0 : (attempt - 1).clamp(0, 30);
  final ms = (1000 * (1 << exp)).clamp(0, 30000);
  return Duration(milliseconds: ms);
}

/// A single cache slot for one [QueryKey]. Holds the current [state], the
/// broadcast [stream] that widgets subscribe to, the in-flight request (for
/// deduplication), a monotonic freshness stamp and a garbage-collection timer.
class QueryEntry<T> {
  QueryEntry(this.key);

  final QueryKey key;
  QueryState<T> state = const QueryState<Never>.idle() as QueryState<T>;

  /// The current shared request, if any. Concurrent [QueryClient.fetchQuery]
  /// calls await the same future instead of firing the [QueryFn] twice.
  Future<T>? _inflight;

  /// Cancels the entry after the last subscriber leaves (see cacheTime).
  Timer? _gcTimer;

  /// Number of live [QueryBuilder]s (or manual subscribers) for this key.
  int subscribers = 0;

  /// Monotonic elapsed time (from the owning client's clock) at which [state]
  /// last became a fresh success. Compared against `staleTime`. `null` means
  /// "no fresh data" — either never fetched or explicitly invalidated.
  Duration? freshAt;

  /// Monotonically increasing token identifying the newest fetch. A resolving
  /// request only writes its result back if its token still matches, so a slow
  /// stale response can never clobber newer data (see [QueryClient._runFetch]).
  int generation = 0;

  /// Re-runs the most recently captured [QueryFn] with its original type
  /// argument. Populated by [QueryClient.fetchQuery] and
  /// [QueryClient.primeRefetcher]; used by `invalidateQueries` to actively
  /// refetch active subscribers.
  ///
  /// Semantics are **last-writer-wins**: the entry keeps whichever `queryFn`
  /// was captured most recently. If two subscribers share one key with
  /// genuinely different `queryFn`s (an anti-pattern — one key should map to one
  /// data source), an invalidation refetch runs the last one captured. See
  /// SPEC §6.
  void Function()? refetcher;

  final _controller = StreamController<QueryState<T>>.broadcast();

  Stream<QueryState<T>> get stream => _controller.stream;

  void _emit(QueryState<T> next) {
    state = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  void dispose() {
    _gcTimer?.cancel();
    _gcTimer = null;
    _controller.close();
  }
}

/// In-memory server-state cache. Create one per app (or use [instance]) and
/// drive it through [QueryBuilder] / [MutationBuilder], or imperatively via
/// [fetchQuery] / [setQueryData] / [invalidateQueries].
class QueryClient {
  QueryClient({
    this.defaultStaleTime = Duration.zero,
    this.defaultCacheTime = const Duration(minutes: 5),
    this.defaultRetry = 0,
    RetryDelay? defaultRetryDelay,
  }) : defaultRetryDelay = defaultRetryDelay ?? defaultRetryDelayFn;

  static final QueryClient instance = QueryClient();

  final Duration defaultStaleTime;
  final Duration defaultCacheTime;

  /// Default number of **retries** (attempts after the first) when a `queryFn`
  /// throws. `0` (the default) disables retry — errors surface immediately, as
  /// in 0.1.x. Override per query via [fetchQuery]/`QueryBuilder.retry`.
  final int defaultRetry;

  /// Default backoff between retries. See [defaultRetryDelayFn] (exponential,
  /// 1s→30s). Override per query via [fetchQuery]/`QueryBuilder.retryDelay`.
  final RetryDelay defaultRetryDelay;

  /// Monotonic clock used for freshness checks. Immune to wall-clock jumps
  /// (NTP sync, timezone/DST changes) that would corrupt `DateTime.now()`
  /// comparisons.
  final Stopwatch _clock = Stopwatch()..start();

  final Map<QueryKeyHash, QueryEntry<Object?>> _entries = {};

  @visibleForTesting
  int get entryCount => _entries.length;

  QueryEntry<T> _entryFor<T>(QueryKey key) {
    final hash = QueryKeyHash.of(key);
    final existing = _entries[hash];
    if (existing != null) {
      // Pause GC while the entry is being touched so it can never be disposed
      // out from under an imperative caller.
      existing._gcTimer?.cancel();
      existing._gcTimer = null;
      return existing as QueryEntry<T>;
    }
    final created = QueryEntry<T>(key);
    _entries[hash] = created as QueryEntry<Object?>;
    return created;
  }

  /// Schedules garbage collection for an entry that currently has no
  /// subscribers, so imperatively-created entries don't leak forever.
  void _armGcIfIdle(QueryEntry<Object?> entry) {
    if (entry.subscribers > 0) return;
    entry._gcTimer?.cancel();
    entry._gcTimer = Timer(defaultCacheTime, () {
      if (entry.subscribers > 0) return;
      final hash = QueryKeyHash.of(entry.key);
      if (identical(_entries[hash], entry)) _entries.remove(hash);
      entry.dispose();
    });
  }

  /// Broadcast stream of state changes for [key].
  ///
  /// Listening does **not** register a subscriber — only a mounted
  /// `QueryBuilder` (via `onSubscribe`) does that. Touching the entry cancels a
  /// pending GC, so this re-arms one afterwards: without it an `observe` on an
  /// unsubscribed key would disarm GC permanently and leak the entry.
  Stream<QueryState<T>> observe<T>(QueryKey key) {
    final entry = _entryFor<T>(key);
    _armGcIfIdle(entry);
    return entry.stream;
  }

  /// Synchronous read of the current state for [key]. Never fetches.
  ///
  /// Re-arms GC for the same reason as [observe] — reading an absent key
  /// creates an idle entry, which must not outlive `cacheTime`.
  QueryState<T> stateOf<T>(QueryKey key) {
    final entry = _entryFor<T>(key);
    _armGcIfIdle(entry);
    return entry.state;
  }

  /// Returns cached data if it is still fresh (within `staleTime`), otherwise
  /// fires [fn]. Concurrent calls for the same key share one in-flight request.
  Future<T> fetchQuery<T>({
    required QueryKey key,
    required QueryFn<T> fn,
    Duration? staleTime,
    int? retry,
    RetryDelay? retryDelay,
  }) {
    final entry = _entryFor<T>(key);
    final effectiveStale = staleTime ?? defaultStaleTime;

    // Capture the typed fn/entry so invalidateQueries can refetch with the
    // correct type argument later (last-writer-wins, see [QueryEntry.refetcher]).
    entry.refetcher = () {
      entry._inflight =
          _runFetch<T>(entry, fn, retry: retry, retryDelay: retryDelay);
    };

    final fresh = entry.freshAt != null &&
        entry.state.isSuccess &&
        (_clock.elapsed - entry.freshAt!) < effectiveStale;
    // Note: does NOT require data != null — a successful query whose value is
    // legitimately null is still fresh.
    if (fresh) {
      _armGcIfIdle(entry);
      return Future.value(entry.state.data as T);
    }

    final inflight = entry._inflight;
    if (inflight != null) return inflight;

    final future = _runFetch<T>(entry, fn, retry: retry, retryDelay: retryDelay);
    entry._inflight = future;
    _armGcIfIdle(entry);
    return future;
  }

  /// Re-captures the [QueryFn]/[staleTime] used for future
  /// invalidation-driven refetches **without** triggering a fetch. Called by
  /// [QueryBuilder] when it rebuilds with a new `queryFn`/`staleTime` on the
  /// same key, so a later `invalidateQueries` refetch runs the current closure
  /// rather than a stale one. Inline closures change every build, so priming
  /// deliberately does not fetch.
  void primeRefetcher<T>({
    required QueryKey key,
    required QueryFn<T> fn,
    Duration? staleTime,
    int? retry,
    RetryDelay? retryDelay,
  }) {
    final entry = _entryFor<T>(key);
    entry.refetcher = () {
      entry._inflight =
          _runFetch<T>(entry, fn, retry: retry, retryDelay: retryDelay);
    };
    _armGcIfIdle(entry);
  }

  Future<T> _runFetch<T>(
    QueryEntry<T> entry,
    QueryFn<T> fn, {
    int? retry,
    RetryDelay? retryDelay,
  }) async {
    final token = ++entry.generation;
    final maxRetries = retry ?? defaultRetry;
    final delayFn = retryDelay ?? defaultRetryDelay;

    // True while this fetch is still the newest and the entry is alive. A
    // superseded (newer fetch / setQueryData / invalidate) or disposed entry
    // must silently drop its result and stop retrying.
    bool isCurrent() => token == entry.generation && !entry._controller.isClosed;

    // Entering a fetch clears any stale error/stackTrace so a loading state
    // never carries an error left over from a previous failure.
    entry._emit(entry.state.copyWith(
      status: entry.state.isSuccess ? entry.state.status : QueryStatus.loading,
      isFetching: true,
      error: null,
      stackTrace: null,
    ));

    var attempt = 0;
    while (true) {
      try {
        final result = await fn();
        // Only write back if we are still the newest fetch.
        if (isCurrent()) {
          entry.freshAt = _clock.elapsed;
          entry._emit(QueryState<T>(
            status: QueryStatus.success,
            data: result,
            hasData: true,
            updatedAt: DateTime.now(),
            isFetching: false,
          ));
          entry._inflight = null;
        }
        return result;
      } catch (e, st) {
        // Superseded/disposed while awaiting → drop silently, do not retry and
        // do not touch _inflight (a newer fetch now owns it).
        if (!isCurrent()) rethrow;

        if (attempt >= maxRetries) {
          // Retries exhausted → surface the error, retaining last-good data.
          entry._emit(entry.state.copyWith(
            status: QueryStatus.error,
            error: e,
            stackTrace: st,
            isFetching: false,
          ));
          entry._inflight = null;
          rethrow;
        }

        attempt += 1;
        await Future<void>.delayed(delayFn(attempt));
        // Re-check after the backoff: a supersede/dispose during the wait must
        // abort the retry.
        if (!isCurrent()) rethrow;
        // loop → next attempt (still isFetching, no error emitted yet)
      }
    }
  }

  /// Marks every entry whose key starts with [prefix] as stale. When [refetch]
  /// is true (the default), entries that currently have subscribers are
  /// actively refetched using their last [QueryFn]; entries without subscribers
  /// simply refetch the next time they are observed.
  void invalidateQueries(QueryKey prefix, {bool refetch = true}) {
    invalidateQueriesWhere(
      (key) => queryKeyStartsWith(key, prefix),
      refetch: refetch,
    );
  }

  /// Predicate form of [invalidateQueries]: marks every entry whose key
  /// satisfies [test] as stale (and, when [refetch] is true, actively refetches
  /// those with subscribers). Use this when a prefix can't express the set —
  /// e.g. invalidate every `['post', id]` regardless of position, or match on a
  /// map field inside the key.
  void invalidateQueriesWhere(
    bool Function(QueryKey key) test, {
    bool refetch = true,
  }) {
    for (final entry in _entries.values) {
      if (!test(entry.key)) continue;
      entry.freshAt = null;
      entry._emit(entry.state.copyWith(
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ));
      if (refetch && entry.subscribers > 0) {
        entry.refetcher?.call();
      }
    }
  }

  void setQueryData<T>(QueryKey key, T data) {
    final entry = _entryFor<T>(key);
    // Supersede any in-flight fetch so its late result can't overwrite this.
    entry.generation++;
    entry._inflight = null;
    entry.freshAt = _clock.elapsed;
    entry._emit(QueryState<T>(
      status: QueryStatus.success,
      data: data,
      hasData: true,
      updatedAt: DateTime.now(),
      isFetching: false,
    ));
    _armGcIfIdle(entry);
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
      _armGcIfIdle(entry);
    }
  }
}

extension QueryClientInternal on QueryClient {
  void onSubscribe<T>(QueryKey key) => _onSubscribe<T>(key);
  void onUnsubscribe<T>(QueryKey key) => _onUnsubscribe<T>(key);
}
