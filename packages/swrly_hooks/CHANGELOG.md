# Changelog

## 0.3.0-dev.1

Initial prerelease. Versioned lockstep with `swrly` (major.minor kept
in sync so `swrly X.Y.*` and `swrly_hooks X.Y.*` are always compatible
— same pattern as `flutter_riverpod` / `hooks_riverpod`).

- `useSwrlyQuery(query)` — subscribes a `HookWidget` to a swrly `Query`
  with correct subscriber lifecycle (invalidation refetches, `cacheTime`
  GC waits) and canonical key hashing.
- `useSwrlyMutation(fn)` — fire-and-forget mutation hook; returns
  `(state, mutate)`. For optimistic / rollback semantics, use swrly's
  built-in `MutationBuilder` instead.
