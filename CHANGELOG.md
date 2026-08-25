## 0.2.1

Docs-only patch — no API changes.

- **README: "Using swrly without widgets".** `QueryClient` is a complete API on
  its own; the README now documents the imperative path (`fetchQuery`) and the
  observe path (`observe` / `stateOf`) alongside `QueryBuilder`, with a table of
  the three ways to read a query and patterns for prefetch-before-navigate,
  synchronous peeks and non-widget subscriptions.
- **Documented that `observe()` does not register a subscriber**, so it does not
  hold an entry against `cacheTime` GC (README + `doc/API.md`).
- README status/install corrected for the released `0.2.0` (they still described
  `0.2.0` as a prerelease and pinned `^0.1.0`).
- **Example:** don't notify instrumentation `ValueNotifier`s during build.

## 0.2.0

Stable release of the 0.2.0 line (the `0.2.0-dev.*` notes below are the full
history). Headline additions since `0.1.x`:

- **Retry + backoff** — `retry` / `retryDelay` on `QueryBuilder` / `fetchQuery`,
  exponential default (1s→30s).
- **Optimistic updates with automatic rollback** — `MutationBuilder.onMutate`
  applies an optimistic write and returns a rollback closure run on error.
- **`keepPreviousData` / `placeholderData`** — no loading flash on key changes
  (search / pagination); new `QueryState.isPlaceholderData`.
- **Example:** a new **Stress test** screen — an in-app performance harness with
  a live FPS / build / raster / jank readout, a cache-ops micro-benchmark, and
  hundreds of live `QueryBuilder`s under continuous invalidation.
- **Docs:** the README now has a measured **Performance** section.

Backward compatible with `0.1.x`.

## 0.2.0-dev.4

- **Example:** rebuilt as a verification harness for all 0.2.0 features —
  pagination with `keepPreviousData` (dimmed previous page while loading), a
  "Fail next" retry demo, and a "make next create fail" toggle that shows the
  optimistic insert being rolled back automatically.
- **Tests:** 100% line coverage on `lib/src` (added `refetch()`,
  `refetchOnResume`, custom-key `toString` fallback, idle getters, singleton).
- **Docs:** added `doc/VERIFICATION.md` (status, remaining TODOs, how to verify
  the prerelease). README updated for the 0.2.0-dev feature set.

## 0.2.0-dev.3

- **New: `keepPreviousData` / `placeholderData`.** `QueryBuilder.keepPreviousData`
  keeps rendering the previous key's data (flagged `state.isPlaceholderData`)
  while a new key loads, instead of flashing to a spinner — ideal for search /
  pagination. `QueryBuilder.placeholderData` shows a static stand-in until the
  first real value arrives. Neither is cached or affects freshness. New
  `QueryState.isPlaceholderData` flag. See SPEC §9.

## 0.2.0-dev.2

- **New: optimistic updates with automatic rollback.** `MutationBuilder.onMutate`
  runs before `mutationFn`, applies your optimistic write, and returns a rollback
  closure; swrly runs it automatically on error (before `onError`) and keeps the
  optimistic value on success. Backward compatible — existing
  `onSuccess`/`onError`/`onSettled` signatures are unchanged. See SPEC §9.

## 0.2.0-dev.1

First 0.2.0 feature, on the `dev` prerelease track for real-world verification.

- **New: retry + backoff.** A `queryFn` that throws is retried up to `retry`
  times with a `retryDelay(attempt)` backoff. Configure per query
  (`QueryBuilder.retry` / `retryDelay`, `fetchQuery(retry:, retryDelay:)`) or
  globally (`QueryClient(defaultRetry:, defaultRetryDelay:)`). Default is `0`
  retries (unchanged 0.1.x behaviour); `defaultRetryDelayFn` provides an
  exponential 1s→30s backoff. While retrying the query stays `isFetching` and
  only surfaces an `error` after retries are exhausted; retries respect the
  generation guard (a supersede/dispose stops them). See SPEC §8.1.

## 0.1.1-dev.1

Prerelease of the 0.1.1 correctness patch, published for verification before the
stable `0.1.1` release. Everything below plus the review fix noted here.

- **Fix (review):** `QueryBuilder` only re-captures the refetcher (`primeRefetcher`)
  on a same-key rebuild **when `enabled` is true**. Previously a disabled query
  that rebuilt could get a refetcher installed, so a later `invalidateQueries`
  would fetch a query the caller set `enabled: false` — violating SPEC §9. Added
  a regression test plus tests for `onError`/`onSettled` on unmount, `hasData`
  retention across errors, and `copyWith` field clearing (31 tests total).

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
