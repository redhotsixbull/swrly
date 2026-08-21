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

## 6. Invalidation — `invalidateQueries(prefix, {refetch = true})`

- Marks every entry whose key starts with `prefix` as stale.
- When `refetch == true` (default): entries that currently have **subscribers**
  are refetched immediately using their last `queryFn` (captured per entry).
  Entries without subscribers refetch lazily on next observe.
- When `refetch == false`: entries are only marked stale.

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

## 9. Widgets

### `QueryBuilder<T>`
- Subscribes on mount, unsubscribes on dispose (drives GC).
- Emits `loading → success | error`. `state.isFetching` marks a background
  refetch while `data` is still present.
- `enabled: false` skips fetching; flipping it **false → true** MUST kick off
  the fetch that was skipped (dependent-query pattern).
- Key or client change re-subscribes to the new entry.
- `refetchOnResume: true` refetches on `AppLifecycleState.resumed`.
- `setState` is guarded by `mounted`; no setState-after-dispose.

### `MutationBuilder<T, V>`
- `mutate(variables)` transitions `idle → loading → success | error`.
- Fires `onSuccess(data, vars)` / `onError(error, stack, vars)` and always
  `onSettled(vars)`.
- Returns the result, or `null` if the mutation threw.
- Post-await `setState` is guarded by `mounted`.

## Not yet (out of scope for 0.0.x)
Infinite queries, retry/backoff, `select`/`placeholderData`, window-focus
refetch, persistence, devtools.
