# swrly — Feature Specification

Behavioral contract for each feature. "MUST/SHOULD" describe guarantees that
the test suite (`test/swrly_test.dart`) pins down.

## 1. Cache identity — `QueryKey`

- A `QueryKey` is `List<Object?>`. Two keys are the **same cache entry** iff
  their deterministic serialization is equal.
- Serialization is **structural**: nested lists recurse; `Map` keys are sorted
  so `{'a':1,'b':2}` and `{'b':2,'a':1}` collide intentionally.
- Keys MUST be built from primitives / lists / maps. A custom object falls back
  to `toString()`; two objects with equal `toString()` will collide.
- **Prefix matching**: `queryKeyStartsWith(key, prefix)` is true iff `prefix`
  is a leading sub-sequence of `key`. A prefix longer than the key never
  matches.

## 2. Freshness — `staleTime`

- Each successful fetch stamps the entry with a **monotonic** timestamp
  (`Stopwatch`, not `DateTime.now()`), so wall-clock jumps (NTP/DST) cannot
  corrupt freshness.
- `fetchQuery` returns cached data **without** calling `queryFn` iff the entry
  is a success AND `elapsed - freshAt < staleTime`.
- A successful value of `null` is still fresh. Freshness MUST NOT depend on
  `data != null`.
- `invalidateQueries` clears `freshAt`, forcing the next fetch to run `queryFn`.

## 3. Request deduplication

- Concurrent `fetchQuery` calls for the same key share **one** in-flight
  request; `queryFn` runs once and all awaiters resolve with the same value.

## 4. Response ordering — generation guard

- Every fetch takes a monotonically increasing generation token.
- A resolving request writes its result back **only** if its token is still the
  newest. A superseded request (because of a newer `fetchQuery`,
  `setQueryData`, or `invalidateQueries`) MUST silently drop its result.
- Consequence: a slow, stale response can never overwrite fresher data.

## 5. Error handling

- On `queryFn` throw, the entry transitions to `error` while **retaining the
  last successful `data`** (`isError && hasData` is possible).
- The thrown error propagates to the `fetchQuery` awaiter (widgets swallow it;
  the error is on `state.error`).
- Entering a fetch (`loading`/background refetch) and a subsequent success MUST
  clear any `error`/`stackTrace` from a previous failure. An `error`/`stackTrace`
  MUST NOT leak into a later non-error state. (`QueryState.copyWith` uses a
  sentinel so these fields can be explicitly cleared.)

### 5.1 `hasData` vs `data != null`

- `QueryState.hasData` MUST be true iff the state holds a value produced by a
  successful fetch (or `setQueryData`), **independent of whether that value is
  `null`**. A `QueryBuilder<int?>` whose `queryFn` returns `null` reports
  `isSuccess && hasData`.
- `hasData` is retained across an `error` transition (last-good data survives).

## 6. Invalidation — `invalidateQueries(prefix, {refetch = true})`

- Marks every entry whose key starts with `prefix` as stale.
- When `refetch == true` (default): entries that currently have **subscribers**
  are refetched immediately using their last captured `queryFn`. Entries without
  subscribers refetch lazily on next observe.
- When `refetch == false`: entries are only marked stale.
- **Captured `queryFn` is last-writer-wins.** Each `fetchQuery` (and each
  `QueryBuilder` rebuild, via `primeRefetcher`) re-captures the entry's
  `queryFn`. If two subscribers share one key with genuinely different
  `queryFn`s — an anti-pattern; one key SHOULD map to one data source — an
  invalidation refetch runs whichever was captured **most recently**. This is
  deterministic in call order, not internal map/subscribe order.

### 6.1 Predicate invalidation — `invalidateQueriesWhere(test, {refetch = true})`

- Same semantics as `invalidateQueries`, but selects entries via
  `bool Function(QueryKey)` instead of a prefix. Use it when a prefix can't
  express the target set (e.g. every `['post', id]` regardless of position, or a
  match on a map field inside the key). `invalidateQueries(prefix)` is defined as
  `invalidateQueriesWhere((k) => queryKeyStartsWith(k, prefix))`.

## 7. Optimistic writes — `setQueryData` / `getQueryData`

- `setQueryData` writes a success state directly (no `queryFn`), stamps
  freshness, and **supersedes any in-flight fetch** (generation bump) so a
  racing response cannot clobber the optimistic value.
- `getQueryData` returns the cached value or `null` if absent.

## 8. Garbage collection — `cacheTime`

- An entry is disposed `cacheTime` after its **last subscriber** unsubscribes.
- Any access (`fetchQuery`, `setQueryData`, `observe`, subscribe) MUST cancel a
  pending GC so an entry is never disposed out from under a live user
  ("disposal-during-use" is a bug). GC is re-armed when the entry is idle
  again.
- `removeQueries(prefix)` and `clear()` dispose immediately (closing streams,
  cancelling timers).

## 8.1 Retry + backoff (0.2.0)

- A `queryFn` that throws is retried up to `retry` times (attempts after the
  first). `retry` resolves per query, falling back to the client's
  `defaultRetry` (default `0` → no retry, errors surface immediately as in
  0.1.x).
- Between attempts the fetch waits `retryDelay(attempt)` where `attempt` is
  **1-based** (`1` is the first retry). Default is `defaultRetryDelayFn`:
  exponential 1s→30s (1s, 2s, 4s, …, capped at 30s).
- While retrying, the entry stays `isFetching` and MUST NOT emit an `error`
  state. Only after retries are exhausted does it transition to `error`
  (retaining last-good `data`). A retry that eventually succeeds emits `success`
  with **no** intervening error.
- Retries respect the generation guard (§4): if a newer `fetchQuery`,
  `setQueryData`, or `invalidateQueries` supersedes the entry (or it is
  disposed) during an attempt or its backoff, the retry loop stops and the
  result is dropped silently.
- Deduplication (§3) holds across retries: concurrent awaiters share the one
  retrying in-flight future.

## 9. Widgets

### `QueryBuilder<T>`
- Subscribes on mount, unsubscribes on dispose (drives GC).
- Emits `loading → success | error`. `state.isFetching` marks a background
  refetch while `data` is still present.
- `enabled: false` skips fetching; flipping it **false → true** MUST kick off
  the fetch that was skipped (dependent-query pattern).
- Key or client change re-subscribes to the new entry.
- A rebuild on the **same key/client** re-captures the current
  `queryFn`/`staleTime`/`retry`/`retryDelay` (so a later `invalidateQueries`
  refetch uses the current closure and retry policy) but MUST NOT refetch —
  inline closures change every build, so a `queryFn` identity change alone is
  not a refetch trigger. Priming happens only while `enabled` is true, so a
  disabled query never gets a refetcher (invalidation skips it).
- `retry`/`retryDelay` (§8.1) apply to the initial fetch, `refetch()`, and
  invalidation-driven refetches; they fall back to the client defaults.
- `keepPreviousData: true` — on a **key change**, the builder keeps receiving the
  previous key's data (with `state.isPlaceholderData == true`, `isFetching ==
  true`) until the new key produces real data, instead of dropping to a
  no-data/loading state. Placeholder data is **not** cached and does not affect
  freshness or `getQueryData`.
- `placeholderData: T?` — while the current key has no real data yet, the builder
  receives this static value (with `isPlaceholderData == true`). Superseded by
  real data as soon as it arrives; not cached.
- Real (cached) data always has `isPlaceholderData == false`.
- `refetchOnResume: true` refetches on `AppLifecycleState.resumed`.
- `setState` is guarded by `mounted`; no setState-after-dispose.

### `MutationBuilder<T, V>`
- `mutate(variables)` transitions `idle → loading → success | error`.
- If `onMutate(vars)` is provided it runs **before** `mutationFn`, may be async,
  and returns an optional **rollback** closure. On error swrly runs that
  rollback automatically **before** `onError` (so an optimistic write is undone
  on failure). On success the rollback is discarded (optimistic value kept).
- Fires `onSuccess(data, vars)` / `onError(error, stack, vars)` and always
  `onSettled(vars)`. These app-level callbacks — and the automatic rollback —
  MUST run **regardless of `mounted`** — a widget that disposes mid-flight still
  runs them (e.g. a cache invalidation in `onSuccess`, or the rollback, must not
  be silently skipped). Only `setState` is guarded by `mounted`.
- Returns the result, or `null` if the mutation threw.

## Not yet (out of scope)
Infinite queries, `select`/`placeholderData`/`keepPreviousData`, optimistic
rollback helper, request cancellation, window-focus refetch, persistence,
devtools.
