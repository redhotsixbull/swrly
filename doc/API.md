# API reference

## `QueryClient`

The in-memory cache. Usually you use the singleton (`QueryClient.instance`),
but you can create isolated clients for tests.

### Constructor

```dart
QueryClient({
  Duration defaultStaleTime = Duration.zero,
  Duration defaultCacheTime = const Duration(minutes: 5),
  int defaultRetry = 0,
  RetryDelay? defaultRetryDelay,   // defaults to defaultRetryDelayFn
})
```

- `defaultStaleTime` — how long a fetched value counts as fresh. During this
  window, a re-fetch call returns the cached value without hitting `queryFn`.
- `defaultCacheTime` — how long an entry stays in memory after its last
  subscriber leaves. On expiry, the entry is removed.
- `defaultRetry` — default number of retries (attempts after the first) when a
  `queryFn` throws. `0` disables retry. Override per query.
- `defaultRetryDelay` — `Duration Function(int attempt)` backoff (1-based
  attempt). Defaults to `defaultRetryDelayFn` (exponential 1s→30s).

### Methods

- `Future<T> fetchQuery<T>({key, fn, staleTime, retry, retryDelay})` — imperative fetch. Uses cache if fresh, dedups in-flight requests, emits state updates through the stream. `retry`/`retryDelay` fall back to the client defaults.
- `Stream<QueryState<T>> observe<T>(key)` — broadcast stream of state changes. Note it does **not** register a subscriber, so unlike a mounted `QueryBuilder` it does not hold the entry against `cacheTime` GC; a long-lived non-widget consumer should keep the entry warm via `fetchQuery`.
- `QueryState<T> stateOf<T>(key)` — synchronous read of current state.
- `void invalidateQueries(prefix, {bool refetch = true})` — mark all keys starting with `prefix` stale. With `refetch: true` (default), entries that currently have subscribers are refetched immediately using their last captured `queryFn` (last-writer-wins for a shared key); others refetch on next observe.
- `void invalidateQueriesWhere(bool Function(QueryKey) test, {bool refetch = true})` — predicate form of `invalidateQueries` for sets a prefix can't express (e.g. every `['post', id]`, or a match on a map field in the key).
- `void primeRefetcher<T>({key, fn, staleTime})` — re-capture the `queryFn`/`staleTime` used by a future invalidation refetch **without** fetching. `QueryBuilder` calls this on a same-key rebuild; you rarely need it directly.
- `void setQueryData<T>(key, data)` — write a value directly (skips `queryFn`). Useful for optimistic updates.
- `T? getQueryData<T>(key)` — read the cached value.
- `void removeQueries(prefix)` — remove entries whose keys start with `prefix`.
- `void removeQueriesWhere(bool Function(QueryKey) test)` — predicate form of `removeQueries`, mirroring `invalidateQueriesWhere`. Use it to drop one exact key without also dropping keys nested under it (this is what `Query.remove()` uses).
- `void clear()` — drop everything, cancel all GC timers.

---

## `QueryKey`

Type alias for `List<Object?>`. Serialized deterministically — order matters
inside each list element, but `Map` keys are sorted for hashing so
`{'a': 1, 'b': 2}` and `{'b': 2, 'a': 1}` hash the same.

Prefix semantics: `['user', 1]` starts with `['user']`, so `invalidateQueries(['user'])`
matches every user-scoped query.

---

## `QueryState<T>`

```dart
class QueryState<T> {
  final QueryStatus status;    // idle | loading | success | error
  final T? data;
  final bool hasData;          // holds a value from a successful fetch (even null)
  final Object? error;
  final StackTrace? stackTrace;
  final DateTime? updatedAt;
  final bool isFetching;       // true during background refetch even when data is present
  final bool isPlaceholderData; // data is a keepPreviousData / placeholderData stand-in

  bool get isIdle;
  bool get isLoading;
  bool get isSuccess;
  bool get isError;
}
```

`isFetching` is distinct from `isLoading`: a query that has `data` from a
previous fetch and is now refetching in the background is
`isSuccess && isFetching`.

`hasData` is **not** `data != null`: a query that successfully resolves to
`null` still reports `hasData == true`. It is retained across an error
transition, so last-good data survives (`isError && hasData` is possible).

---

## `Query<T>`

A reusable **definition** of one query — the key, the fetch function and the
per-query options — declared once and consumed from anywhere. Holds no state;
the cache still lives in `QueryClient`. Two instances with the same key address
the same entry.

```dart
final postsQuery = Query<List<Post>>(
  key: const ['posts'],
  fn: () => api.getPosts(),
  staleTime: const Duration(seconds: 30),
);
```

### Constructor

- `key` — the cache key. Identifies exactly one entry.
- `fn` — `Future<T> Function()`. Stored as a field, so an invalidation-driven
  refetch always runs this closure (an inline `queryFn` changes identity every
  build).
- `staleTime` / `retry` / `retryDelay` — per-query options; each falls back to
  the corresponding `QueryClient` default when null.
- `client` — the cache to target. Defaults to `QueryClient.instance`.

### Members

- `Future<T> fetch()` — fetch through the cache: fresh → cached value, in-flight
  → joined, otherwise runs `fn`. Identical to what `QueryBuilder` does, so a
  mounted builder on this key sees the result.
- `Future<T> refetch()` — fetch **past** `staleTime` (still deduped).
- `T? data` — the cached value, or null. Synchronous; never fetches.
- `QueryState<T> state` — the current state. Synchronous; never fetches.
- `Stream<QueryState<T>> stream` — state changes for this key. Like
  `QueryClient.observe`, listening does **not** register a subscriber.
- `void setData(T value)` — direct write, skipping `fn`.
- `void invalidate({bool refetch = true})` — marks **this key only** stale.
  Exact, not prefix: invalidating `['posts']` leaves `['posts', 'page', 2]`
  alone.
- `void remove()` — drops **this key only** from the cache.
- `Query<T> copyWith({key, fn, staleTime, retry, retryDelay, client})` — a copy
  with individual options overridden (a one-off `staleTime` at a call site, or
  pointing a shared definition at a test client).

---

## `QueryFamily<T, A>`

A parameterised `Query` — one definition covering every argument.

```dart
final postQuery = QueryFamily<Post, int>(
  prefix: const ['post'],
  fn: (id) => api.getPost(id),
);

await postQuery(3).fetch();   // key ['post', 3]
postQuery.invalidateAll();    // every ['post', …]
```

### Constructor

- `prefix` — the shared leading segment of every member's key.
- `fn` — `Future<T> Function(A arg)`.
- `argKey` — `QueryKey Function(A arg)`, the segments appended after `prefix`.
  Defaults to `[arg]`. Supply it when the argument is a record or custom object
  so the key is built from primitives rather than falling back to `toString()`.
- `staleTime` / `retry` / `retryDelay` / `client` — applied to every member.

### Members

- `Query<T> call(A arg)` — the member for `arg`; call the family directly
  (`postQuery(3)`).
- `QueryKey keyFor(A arg)` — `[...prefix, ...argKey(arg)]`.
- `void invalidateAll({bool refetch = true})` — marks everything under `prefix`
  stale.
- `void removeAll()` — drops everything under `prefix`.

Because keys are always built as `[...prefix, ...]`, `invalidateAll` /
`removeAll` are correct by construction.

---

## `QueryBuilder<T>`

```dart
QueryBuilder<T>({
  Key? key,
  required QueryKey queryKey,
  required Future<T> Function() queryFn,
  required Widget Function(BuildContext, QueryState<T>, Future<void> Function()) builder,
  Duration? staleTime,
  QueryClient? client,            // defaults to QueryClient.instance
  bool enabled = true,
  bool refetchOnResume = true,
  int? retry,                     // falls back to client.defaultRetry
  RetryDelay? retryDelay,         // falls back to client.defaultRetryDelay
  bool keepPreviousData = false,  // keep previous key's data on key change
  T? placeholderData,             // static stand-in until real data arrives
})
```

The builder callback receives `(context, state, refetch)`. Call `refetch()`
to force a fresh fetch (bypassing staleness).

`retry` retries a throwing `queryFn` that many times with a `retryDelay(attempt)`
backoff; while retrying the state stays `isFetching` and only becomes `isError`
once retries are exhausted.

Setting `enabled: false` skips the initial fetch — useful for dependent
queries: don't run a `posts(userId)` query until you have the `userId`.

---

### `QueryBuilder.of(query, {builder, enabled, refetchOnResume, keepPreviousData, placeholderData})`

Builds from a `Query` definition instead of a loose `queryKey`/`queryFn` pair.
`staleTime`, `retry`, `retryDelay` and `client` come from the definition; the
widget-only options stay on the constructor. To override one of the definition's
options at a single call site, pass `query.copyWith(staleTime: ...)`.

```dart
QueryBuilder.of(postsQuery, builder: (context, state, refetch) => ...);
```

---

## `MutationBuilder<T, V>`

```dart
MutationBuilder<T, V>({
  Key? key,
  required Future<T> Function(V variables) mutationFn,
  required Widget Function(BuildContext, Future<T?> Function(V), MutationState<T>) builder,
  FutureOr<void Function()?> Function(V variables)? onMutate,
  void Function(T data, V variables)? onSuccess,
  void Function(Object error, StackTrace stackTrace, V variables)? onError,
  void Function(V variables)? onSettled,
})
```

The builder receives a `mutate(variables)` function. It returns `Future<T?>`
— `null` if the mutation threw (the error is in `state.error`).

`onMutate` runs before `mutationFn` (optimistic update). Return a rollback
closure and swrly runs it automatically if the mutation fails, **before**
`onError`; on success the optimistic value is kept:

```dart
MutationBuilder<Post, String>(
  mutationFn: createPost,
  onMutate: (title) {
    final prev = client.getQueryData<List<Post>>(['posts']);
    client.setQueryData<List<Post>>(['posts'], [draft(title), ...?prev]);
    return () => client.setQueryData<List<Post>>(['posts'], prev ?? []);
  },
  onSettled: (_) => client.invalidateQueries(['posts']),
)
```

---

## `MutationState<T>`

Same shape as `QueryState` but without staleness / fetching separation —
mutations are always one-shot.

```dart
class MutationState<T> {
  final MutationStatus status;   // idle | loading | success | error
  final T? data;
  final Object? error;
  final StackTrace? stackTrace;
}
```
