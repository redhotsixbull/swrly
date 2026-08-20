# Architecture

## Big picture

```
┌──────────────────────────────────┐
│  QueryBuilder<T>  (Widget)       │
│    subscribes to stream,          │
│    kicks off fetch,               │
│    rebuilds on state change       │
└──────────────┬───────────────────┘
               │ observe(key) / fetchQuery(key)
               ▼
┌──────────────────────────────────┐
│  QueryClient  (in-memory cache)  │
│  ┌────────────────────────────┐   │
│  │ Map<QueryKeyHash, Entry>   │   │
│  └────────────────────────────┘   │
│    Entry{ state, stream,          │
│           inflight, gcTimer,      │
│           subscribers }           │
└──────────────────────────────────┘
```

## Core types

- **`QueryKey`** = `List<Object?>` — a serializable identity tuple.
  Serialization is deterministic (maps sort keys) so `['user', 1]` always hashes
  the same way. This lets prefix invalidation (`['user']` matches
  `['user', 1]`, `['user', 2]`, ...) work without runtime shape assumptions.

- **`QueryState<T>`** — a plain value class with `status`, `data`, `error`,
  `updatedAt`, `isFetching`. Kept as a single class instead of a sealed
  hierarchy because Flutter widget code reads it via `.isLoading`,
  `.hasData` etc., and pattern matching on 4 unrelated shapes was ergonomically
  worse for common `if (state.isLoading && !state.hasData)` flows.

- **`QueryEntry<T>`** (private) — everything the client tracks per key:
  the current `QueryState`, a broadcast `StreamController` of state changes,
  the in-flight `Future` (for dedup), a GC timer, and a subscriber count.

## Subscription lifecycle

1. `QueryBuilder.initState`:
   - `client.onSubscribe(key)` → increments the entry's subscriber count,
     cancels any pending GC timer.
   - Subscribes to `client.observe(key)` (broadcast stream).
   - Reads current state synchronously (`client.stateOf(key)`) so first paint
     reflects whatever was cached.
   - Calls `fetchQuery` which immediately emits a loading state before its
     first `await`.

2. `client.fetchQuery` decides:
   - If the entry is fresh (`updatedAt + staleTime > now`) and successful,
     returns the cached value without calling `queryFn`.
   - If there's already an in-flight `Future` for this key, returns it (dedup).
   - Otherwise starts a new fetch, sets `isFetching = true`, and on success or
     error emits the new state through the broadcast stream.

3. `QueryBuilder.dispose`:
   - Cancels stream subscription.
   - `client.onUnsubscribe(key)` → decrements count. If it hits zero, schedules
     a GC timer for `cacheTime` (default 5 min). If the timer fires with the
     count still at zero, the entry is removed.

## Why streams instead of `ChangeNotifier` / `ValueNotifier`

Broadcast streams give a natural fan-out to many subscribers plus a clean
`StreamSubscription.cancel()` model. `ChangeNotifier` would need manual
listener management and doesn't carry data as easily.

The trade-off: stream events are delivered on the next microtask, not
synchronously. That's why `QueryBuilder.initState` reads the current state
synchronously from the client (via `stateOf`) *after* kicking off the fetch
— the fetch synchronously mutates `entry.state` before its first `await`,
so the widget's initial frame can already show `loading`.

## Invalidation

`invalidateQueries(prefix)` walks the entry map, checks each key with
`queryKeyStartsWith`, and marks matching entries stale by resetting
`updatedAt` to epoch 0. The entries themselves stay in the cache and keep
their data — subscribers see it — but the next `fetchQuery` call will bypass
the freshness check and refetch.

This is intentionally the "loose" invalidation model. A stricter alternative
(force-refetch every matching subscriber immediately) would work well for
optimistic-update flows but adds complexity we defer to v0.2.

## Mutations

`MutationBuilder` is intentionally decoupled from `QueryClient`. It exposes
`onSuccess` / `onError` / `onSettled` callbacks that user code uses to call
`client.invalidateQueries` explicitly. This keeps mutations testable in
isolation and mirrors TanStack Query's separation of `useMutation` from
`useQuery`.

## What we deliberately don't do (yet)

- **Structural sharing / equality-preserving updates**: v0.1 replaces the
  whole `data` value on every fetch. React Query preserves object identity of
  unchanged nested fields; that requires a value walk that's out of scope now.
- **Retry logic**: no automatic retry with exponential backoff. Users invoke
  `refetch` themselves.
- **Focus / online / offline listeners**: only app-resume refetch is wired up
  via `WidgetsBindingObserver`. Web focus events and connectivity change
  streams belong in a separate adapter package.
