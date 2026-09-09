# Changelog

## 0.4.0

Stable release alongside `swrly 0.4.0`.

- **Fixed: `useSwrlyQuery` re-subscribes when the `QueryClient` changes.** The
  effect's dependency array held only the key hash, so replacing a `Query` with
  one on a different client but the same key left the hook subscribed to the old
  client — the new client never received `fetch()`, and `invalidate()` and the
  unsubscribe cleanup stayed pointed at the old one. The resolved client is now
  a dependency alongside the key hash.

## 0.4.0-dev.1

Lockstep bump alongside `swrly 0.4.0-dev.1`. No hook-side source changes —
the new `Query` options (`initialData` / `initialDataUpdatedAt` /
`refetchInterval`) flow through as `Query` fields, and `useSwrlyQuery` /
`useSwrlyMutation` already consume the definition object. The new
`MutationBuilder.retry` / `QueryBuilder.notifyOn` knobs are widget-local
and don't cross into the hooks surface.

## 0.3.1-dev.1

Lockstep bump alongside `swrly 0.3.1`. No source changes to the hook
package itself — this release exists so the compatibility rule (matching
`major.minor` = compatible) keeps holding after core moves to 0.3.1.

## 0.3.0-dev.2

- Widen `flutter_hooks` constraint from `^0.20.5` to
  `>=0.20.5 <0.22.0`. The narrow pin broke `flutter pub add swrly_hooks`
  for anyone on the current `flutter_hooks` release (0.21.x) — a
  regression caught during real-world skill verification against a
  fresh Flutter project after `0.3.0-dev.1` was published. The 8
  widget tests all pass on 0.21 (the useEffect / useState / useRef /
  useStream APIs used here are stable across both).

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
