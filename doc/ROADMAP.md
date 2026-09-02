# Roadmap

## v0.0.1 — Scaffold (shipped)

- `QueryClient` (in-memory), `QueryKey` (list, deterministic hash), `QueryState`
- `QueryBuilder<T>` widget: subscribe / fetch / rebuild / auto-cleanup
- `MutationBuilder<T, V>` with success / error / settled callbacks
- Prefix-based `invalidateQueries`
- `setQueryData` / `getQueryData` for optimistic writes
- `cacheTime` GC after last subscriber leaves
- `refetchOnResume` via `WidgetsBindingObserver`

## v0.1.0 — Correctness + real-world example (shipped)

- Cache-correctness fixes: real `invalidateQueries` refetch, per-fetch
  generation guard (no stale-overwrites-fresh), nullable-data freshness,
  monotonic-clock staleTime, disposal-safe GC, `enabled` false→true kick-off.
- Example rebuilt around a real **dio** client with a live request counter, a
  keyed detail query, and optimistic `setQueryData`. README with comparison
  tables. Runs on web.

## v0.1.1 — Correctness patch (shipped)

- `hasData` no longer conflates a successful `null` with "no data".
- `QueryState.copyWith` can clear `data`/`error`/`stackTrace`; stale errors no
  longer leak into later loading/success states.
- `MutationBuilder` runs `onSuccess`/`onError`/`onSettled` regardless of
  `mounted` (only `setState` is guarded).
- `QueryBuilder` re-captures `queryFn`/`staleTime` on same-key rebuild
  (`primeRefetcher`) without refetching.
- **Predicate-based `invalidateQueries`** — `invalidateQueriesWhere((key) => bool)`.
- Documented last-writer-wins semantics for a shared key's captured `queryFn`.

## v0.2.0 — Growth features (shipped)

- ✅ **Retry + backoff** — per-query `retry`/`retryDelay` + client defaults
  (`defaultRetry`/`defaultRetryDelay`). Exponential 1s→30s default. *(0.2.0-dev.1)*
- ✅ **Optimistic-update helpers** — `onMutate` returns a rollback closure, run
  automatically on error *(0.2.0-dev.2)*
- ✅ **`keepPreviousData` / `placeholderData`** — no loading flash on key change
  *(0.2.0-dev.3)*
- ⊘ `useQueries` — intentionally skipped (too React-flavored); if parallel is
  needed, prefer a type-safe record combinator (`QueryGroup2Builder`)

  *(Query cancellation and infinite queries moved out of the 0.2.0 line — see v0.4.)*

## v0.3.0 — Definition objects (shipped)

- ✅ **`Query<T>` / `QueryFamily<T, A>`** — declare a query's key + fetch fn once,
  then consume it imperatively (`q.fetch()`), declaratively
  (`QueryBuilder.of(q)`) or for cache control (`q.invalidate()`). Exact
  invalidate/remove; families derive `[...prefix, ...arg]` keys so
  `invalidateAll` is correct by construction. *(0.3.0-dev.1)*
- ✅ **`QueryBuilder.of(query)`** *(0.3.0-dev.1)*
- ✅ **`QueryClient.removeQueriesWhere(test)`** — predicate form of
  `removeQueries` *(0.3.0-dev.1)*
- ✅ **Docs that can't rot** — the README carries no version numbers, and
  `docs_freshness_test.dart` / `readme_snippets_test.dart` fail the suite if a
  version literal, a stale CHANGELOG, an undocumented public type or a broken
  code sample creeps in *(0.3.0-dev.2)*

  *(Query cancellation, infinite queries and an example screen for definitions
  moved to v0.4 — 0.3.0 was cut on the definition objects and the docs guards.)*

## Next — Usability polish

- **`QueryObserver` (imperative API)** for non-widget consumers — owns its
  subscription, so `observe` no longer leaves the `cacheTime` GC question to the
  caller
- ✅ **`useSwrlyQuery` / `useSwrlyMutation` hooks** — shipped in the
  [`swrly_hooks`](https://pub.dev/packages/swrly_hooks) companion package
- **Structural sharing** — preserve identity of unchanged nested fields on refetch
- **Better error surface** — typed error variants, network-vs-parse distinction
- **`initialData` / `initialDataUpdatedAt`** — seed the cache at Query
  definition time (hydrate from server state, test fixtures, no-flash first
  paint). Distinct from `placeholderData` (which marks the value as
  `isPlaceholderData`). See [`BACKLOG_TRIAGE.md B1`](BACKLOG_TRIAGE.md).
- **`throwOnError`** — opt-in: rethrow errors so `ErrorWidget.builder` or
  an `ErrorBoundary`-style widget catches them, instead of surfacing via
  `state.error`. Off by default. See [`BACKLOG_TRIAGE.md B2`](BACKLOG_TRIAGE.md).
- **`notifyOnChangeProps`** — rebuild only when specific state fields
  change; cheap opt-in perf tuning. See [`BACKLOG_TRIAGE.md B3`](BACKLOG_TRIAGE.md).
- **Dependent queries — first-class `dependsOn`** — replaces the fragile
  `enabled: otherQuery.hasData` pattern. See [`BACKLOG_TRIAGE.md B4`](BACKLOG_TRIAGE.md).

## v0.4 — Robustness

- **Infinite queries** (`InfiniteQueryBuilder<T>`) — pagination with `getNextPageParam`
- **Query cancellation** — abort in-flight requests when subscribers all leave
- **Focus / online listeners** — configurable refetch triggers beyond app resume
- **Persistence adapter interface** — plug in shared_preferences / hive / drift
- **`refetchInterval`** — per-query polling; fires only while the entry has
  subscribers, pauses on app background. Common ask for dashboards /
  status widgets. See [`BACKLOG_TRIAGE.md A1`](BACKLOG_TRIAGE.md).
- **`select` transform** — pass a selector; `QueryBuilder` only rebuilds
  when the selected slice changes. Lands with structural sharing so the
  identity of unchanged slices stays stable. See [`BACKLOG_TRIAGE.md A2`](BACKLOG_TRIAGE.md).
- **`IsFetchingBuilder`** — top-of-app pattern for "any query fetching → show
  global spinner." Reads from `QueryClient` aggregate. See [`BACKLOG_TRIAGE.md A3`](BACKLOG_TRIAGE.md).
- **Mutation `retry` / `retryDelay`** — same options `Query` already has;
  off by default (writes are not idempotent in general). Rollback only
  fires when all retries exhaust. See [`BACKLOG_TRIAGE.md A4`](BACKLOG_TRIAGE.md).
- **Example screen for definitions** — an in-app harness for `Query` /
  `QueryFamily`, matching the 0.2.0-dev.4 verification pattern

## v0.5 — Ecosystem

- **Devtools panel** (Flutter DevTools extension) — inspect cache, timings, invalidations
- **Persistence plugins** — official `swrly_persist_hive`, `swrly_persist_prefs`
- **Riverpod / Bloc bridges** — `AsyncValue<T>` adapters
- **Codegen** — typed query keys and endpoints from OpenAPI / GraphQL schemas

## v1.0 — Stability

- API surface frozen (breaking changes require major bump)
- Comprehensive documentation site
- 90%+ test coverage
- Battle-tested via at least three real production apps

## Explicit non-goals

- **A GraphQL client** — swrly is transport-agnostic. Users bring their own fetch layer.
- **Server-side rendering / hydration** — Flutter doesn't ship SSR in a meaningful way for mobile.
- **Reactive database sync** — that's what Drift / Isar / Realm are for.
- **`refetchOnMount: 'always'|'never'|'if-stale'` axis** — redundant with
  `staleTime` (`Duration.zero` = always, huge duration = never, default =
  if-stale). Adding a second overlapping axis forces users to reason about
  which wins. See [`BACKLOG_TRIAGE.md R1`](BACKLOG_TRIAGE.md).
- **Query `meta` field** — free-form metadata slot with no consumer API.
  Adds dead weight, erodes the "narrow, opinionated cache" boundary, and
  pre-empts the typed design that DevTools / observability should get
  when those land. See [`BACKLOG_TRIAGE.md R2`](BACKLOG_TRIAGE.md).
- **`useQueries` / dynamic-parallel** — too React-flavored; a type-safe
  record combinator (`QueryGroup2Builder` etc.) is the preferred path
  when actual demand appears.
