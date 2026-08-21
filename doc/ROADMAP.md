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

## v0.2.0 — Growth features (in progress, `dev` track)

- ✅ **Retry + backoff** — per-query `retry`/`retryDelay` + client defaults
  (`defaultRetry`/`defaultRetryDelay`). Exponential 1s→30s default. *(0.2.0-dev.1)*
- ☐ Optimistic-update helpers — `onMutate` + rollback context
- ☐ `useQueries`-style parallel combinator
- ☐ Query cancellation when subscribers all leave
- ☐ Infinite / paginated queries

## Next — Usability polish

- **`useQuery` / `useMutation` hooks** for `flutter_hooks` users
- **Structural sharing** — preserve identity of unchanged nested fields on refetch
- **Better error surface** — typed error variants, network-vs-parse distinction
- **`QueryObserver` (imperative API)** for non-widget consumers

## v0.2 — Growth features

- **Infinite queries** (`InfiniteQueryBuilder<T>`) — pagination with `getNextPageParam`
- **Optimistic-update helpers** — `mutate(input, { optimisticData, rollbackOnError })`
- **Query cancellation** — abort in-flight requests when subscribers all leave
- **Focus / online listeners** — configurable refetch triggers beyond app resume
- **Persistence adapter interface** — plug in shared_preferences / hive / drift

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
