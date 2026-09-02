# Changelog

## 0.1.0-dev.1

- Initial prerelease.
- `useSwrlyQuery(query)` — subscribes a `HookWidget` to a swrly `Query`
  with correct subscriber lifecycle (invalidation refetches, `cacheTime`
  GC waits) and canonical key hashing.
- `useSwrlyMutation(fn)` — fire-and-forget mutation hook; returns
  `(state, mutate)`. For optimistic / rollback semantics, use swrly's
  built-in `MutationBuilder` instead.
