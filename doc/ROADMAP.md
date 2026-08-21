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

## Next — Usability polish

- **`useQuery` / `useMutation` hooks** for `flutter_hooks` users
- **Structural sharing** — preserve identity of unchanged nested fields on refetch
- **Retry policy** — configurable retry count + backoff per query
- **Better error surface** — typed error variants, network-vs-parse distinction
- **Predicate-based `invalidateQueries`** — `(key) => bool` instead of just prefix
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
