## 0.1.1

Correctness patch — behaviour fixes found in review, all backward compatible.

- **Fix:** `QueryState.hasData` is now based on a stored "has a successful value"
  flag instead of `data != null`. A query that legitimately resolves to `null`
  now reports `isSuccess && hasData` at the widget layer, matching the cache's
  own freshness contract (SPEC §2/§5.1).
- **Fix:** `QueryState.copyWith` can now **clear** `data`/`error`/`stackTrace`
  (via a sentinel). Entering a fetch and a successful refetch clear a stale
  error/stackTrace, so an old failure no longer leaks into a later
  loading/success state.
- **Fix:** `MutationBuilder` now runs `onSuccess`/`onError`/`onSettled`
  **regardless of `mounted`** — a widget that disposes mid-flight no longer
  silently skips a cache invalidation done in `onSuccess`. Only `setState` is
  guarded.
- **Fix:** `QueryBuilder` re-captures the current `queryFn`/`staleTime` on a
  same-key rebuild (new `QueryClient.primeRefetcher`), so a later
  `invalidateQueries` refetch uses the current closure rather than a stale one.
  It still does **not** refetch on a plain `queryFn` identity change.
- **New:** `QueryClient.invalidateQueriesWhere((key) => bool)` — predicate form
  of `invalidateQueries` for sets a prefix can't express.
- **Docs:** documented the last-writer-wins semantics for an entry's captured
  `queryFn` when subscribers share a key (SPEC §6). Added 6 tests.

## 0.1.0

- **Example:** rebuilt around a real **dio** client hitting a public API, with a
  live request counter + event log so the cache is *observable* — cache hits
  show as "0 requests", keyed detail queries (`['post', id]`) demonstrate
  per-key caching, and mutations show optimistic `setQueryData`. Runs on web.
- **Docs:** README overhauled — "why server state", how-it-works flow, and
  comparison tables (vs `FutureBuilder`, vs Riverpod/Bloc, vs a dio cache
  interceptor). `docs/` renamed to `doc/` (pub convention); added pubspec topics.
- Bundles all the `0.0.2` cache-correctness fixes below.

## 0.0.2

- **Fix:** `invalidateQueries(refetch: true)` now actually refetches active
  subscribers (the last `queryFn` is captured per entry) instead of only
  marking data stale.
- **Fix:** stale responses can no longer overwrite fresher data — each fetch
  carries a generation token and only the newest may write back.
- **Fix:** a successful `null` value is treated as fresh; nullable-data queries
  no longer refetch on every call.
- **Fix:** freshness uses a monotonic clock, immune to wall-clock jumps.
- **Fix:** garbage collection can no longer dispose an entry that is being
  reused imperatively; idle imperatively-created entries are now collected too.
- **Fix:** `QueryBuilder` kicks off the fetch when `enabled` flips false → true.
- Docs: added `docs/SPEC.md`; expanded test coverage (dedup, race, GC,
  nullable, invalidate-refetch, widget lifecycle).

## 0.0.1

- Initial scaffold: `QueryClient`, `QueryBuilder`, `MutationBuilder`, prefix invalidation, refetch-on-resume.
