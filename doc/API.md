# API reference

## `QueryClient`

The in-memory cache. Usually you use the singleton (`QueryClient.instance`),
but you can create isolated clients for tests.

### Constructor

```dart
QueryClient({
  Duration defaultStaleTime = Duration.zero,
  Duration defaultCacheTime = const Duration(minutes: 5),
})
```

- `defaultStaleTime` — how long a fetched value counts as fresh. During this
  window, a re-fetch call returns the cached value without hitting `queryFn`.
- `defaultCacheTime` — how long an entry stays in memory after its last
  subscriber leaves. On expiry, the entry is removed.

### Methods

- `Future<T> fetchQuery<T>({key, fn, staleTime})` — imperative fetch. Uses cache if fresh, dedups in-flight requests, emits state updates through the stream.
- `Stream<QueryState<T>> observe<T>(key)` — broadcast stream of state changes.
- `QueryState<T> stateOf<T>(key)` — synchronous read of current state.
- `void invalidateQueries(prefix, {bool refetch = true})` — mark all keys starting with `prefix` stale. With `refetch: true` (default), entries that currently have subscribers are refetched immediately using their last captured `queryFn` (last-writer-wins for a shared key); others refetch on next observe.
- `void invalidateQueriesWhere(bool Function(QueryKey) test, {bool refetch = true})` — predicate form of `invalidateQueries` for sets a prefix can't express (e.g. every `['post', id]`, or a match on a map field in the key).
- `void primeRefetcher<T>({key, fn, staleTime})` — re-capture the `queryFn`/`staleTime` used by a future invalidation refetch **without** fetching. `QueryBuilder` calls this on a same-key rebuild; you rarely need it directly.
- `void setQueryData<T>(key, data)` — write a value directly (skips `queryFn`). Useful for optimistic updates.
- `T? getQueryData<T>(key)` — read the cached value.
- `void removeQueries(prefix)` — remove entries whose keys start with `prefix`.
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
})
```

The builder callback receives `(context, state, refetch)`. Call `refetch()`
to force a fresh fetch (bypassing staleness).

Setting `enabled: false` skips the initial fetch — useful for dependent
queries: don't run a `posts(userId)` query until you have the `userId`.

---

## `MutationBuilder<T, V>`

```dart
MutationBuilder<T, V>({
  Key? key,
  required Future<T> Function(V variables) mutationFn,
  required Widget Function(BuildContext, Future<T?> Function(V), MutationState<T>) builder,
  void Function(T data, V variables)? onSuccess,
  void Function(Object error, StackTrace stackTrace, V variables)? onError,
  void Function(V variables)? onSettled,
})
```

The builder receives a `mutate(variables)` function. It returns `Future<T?>`
— `null` if the mutation threw (the error is in `state.error`).

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
