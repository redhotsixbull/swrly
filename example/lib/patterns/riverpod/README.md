# Riverpod × swrly

**Client state**: `StateProvider<String>` for the search filter.
**Server state**: `postsQuery` / `postQuery(id)` via `QueryBuilder.of(...)`.

## Why not `FutureProvider.family` for the posts?

You *can*. Riverpod supports it. The honest comparison from the README's
table:

| | Riverpod async providers | swrly |
|---|---|---|
| Cache keyed by request args | ✅ `.family` | ✅ `queryKey` |
| Invalidate | ✅ `ref.invalidate` | ✅ `invalidateQueries` (prefix) |
| `staleTime` / stale-while-revalidate | hand-rolled | ✅ built-in |
| Request dedupe across widgets | ✅ | ✅ |
| Optimistic `setQueryData` + GC by subscription | hand-rolled | ✅ built-in |
| Requires adopting the framework | yes (providers everywhere) | no — just an object |

If you're happy hand-rolling `staleTime` on `AsyncNotifier` and love a
Riverpod-only stack, you don't need swrly. This pattern is for the middle
ground: use Riverpod for client state and DI, use swrly for the
stale-while-revalidate semantics on server data.

## The scope boundary — don't wrap swrly in a Riverpod provider

Tempting but wrong:

```dart
final postsProvider = FutureProvider((ref) => postsQuery.fetch());
```

Now you have two caches — Riverpod's and swrly's — pointing at the same
data, and neither knows when the other invalidates. Consume `swrly`
directly with `QueryBuilder.of(postsQuery)` (or `postsQuery.stream` in a
`StreamProvider`, if you insist on the Riverpod-shaped consumption).

## Refactoring an existing Riverpod app

Look for `FutureProvider`s that:

- Hand-roll a "refetch after N seconds" or "refetch on this event" pattern.
- Are `.family` with a fetcher that manages its own optimistic writes.
- Duplicate state (a `FutureProvider` for the list + a mutation provider
  that writes to it).

Those are the parts to move to a `Query` / `QueryFamily`. Keep everything
else in Riverpod.
