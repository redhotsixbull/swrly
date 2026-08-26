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

  *(Query cancellation and infinite queries moved to v0.3.0.)*

## v0.3.0 — Definition objects (in progress, `dev` track)

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
- ☐ Example harness screen demonstrating definitions (matching the 0.2.0-dev.4
  verification pattern)
- ☐ Query cancellation when subscribers all leave
- ☐ Infinite / paginated queries

## Next — Usability polish

- **`QueryObserver` (imperative API)** for non-widget consumers — owns its
  subscription, so `observe` no longer leaves the `cacheTime` GC question to the
  caller
- **`useQuery` / `useMutation` hooks** for `flutter_hooks` users — nearly free on
  top of `Query` (`useQuery(postsQuery)`)
- **Structural sharing** — preserve identity of unchanged nested fields on refetch
- **Better error surface** — typed error variants, network-vs-parse distinction

## v0.4 — Robustness

- **Infinite queries** (`InfiniteQueryBuilder<T>`) — pagination with `getNextPageParam`
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
