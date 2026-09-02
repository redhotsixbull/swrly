---
name: swrly-refactor-riverpod
description: In a Riverpod project, migrate `FutureProvider`s that hand-roll stale/refetch/invalidation to swrly's `Query`/`QueryFamily`. Keep Riverpod for client state and DI. Use when the user asks to reduce Riverpod boilerplate for async fetches, add staleTime to a FutureProvider, or add optimistic updates to an AsyncNotifier.
---

# swrly-refactor-riverpod

`swrly` and Riverpod coexist by design. Riverpod stays for client state
and DI; swrly takes over the server-state caching layer where you would
otherwise hand-roll `staleTime` / dedupe / optimistic on `AsyncNotifier`.

## Prerequisites

- `flutter_riverpod` (or `riverpod` / `hooks_riverpod`) in `pubspec.yaml`.
- `swrly` is installed.
- `lib/queries/` exists.

## When to leave Riverpod alone

Do NOT convert Riverpod providers when:

- The provider is a `StateProvider` / `StateNotifierProvider` / `NotifierProvider`
  managing purely client state (form, filter, selected id).
- The provider is a Dependency Injection seam (`Provider((ref) => api)`).
- The user is happy hand-rolling stale-while-revalidate on Riverpod
  and has explicitly said so.

Only touch `FutureProvider` / `FutureProvider.family` / `AsyncNotifier`
that:

- Fetch data from an API.
- Hand-roll refetch or invalidation logic.
- Do optimistic writes via `state = AsyncData(...)` on top of a fetched list.

## Steps

### 1. List candidate providers

```
grep -rn "FutureProvider\|AsyncNotifier" lib/
```

For each, check if it fetches from an API and whether it's doing more
than the trivial "call once, return." Present the list to the user.

### 2. Extract to a `Query` in `lib/queries/`

Same as other refactor skills:

```dart
final postsQuery = Query<List<Post>>(
  key: const ['posts'],
  fn: () => api.getPosts(),
  staleTime: const Duration(seconds: 30),
);
```

For `FutureProvider.family`, use `QueryFamily`:

```dart
final postQuery = QueryFamily<Post, int>(
  prefix: const ['post'],
  fn: (id) => api.getPost(id),
  staleTime: const Duration(minutes: 1),
);
```

Use `argKey` if the argument isn't a primitive
(`doc/CONVENTIONS.md §7`).

### 3. Migrate consumers

Widgets that used `ref.watch(postsProvider)` → `QueryBuilder.of(postsQuery)`.

**Explicit anti-pattern** to warn the user about:

```dart
// DON'T:
final postsProvider = FutureProvider((ref) => postsQuery.fetch());
```

That creates two caches (Riverpod's + swrly's) pointing at the same
data. Consume swrly directly from the widget, don't wrap it in a
provider.

If you truly need Riverpod-shaped consumption (an existing screen deeply
uses `ref.watch(...)` shape), the acceptable bridge is
`StreamProvider((ref) => postsQuery.stream)` — but push the user to
consume `QueryBuilder.of(postsQuery)` directly when possible.

### 4. `ref.invalidate` → `query.invalidate()`

Manual invalidation sites port trivially:

- `ref.invalidate(postsProvider)` → `postsQuery.invalidate()`
- Multi-key invalidation → `postQuery.invalidateAll()` (family)
  or `QueryClient.instance.invalidateQueries(['post'])` (prefix).

### 5. Model after the pattern

[`example/lib/patterns/riverpod/`](../../../example/lib/patterns/riverpod/)
shows the coexistence — `StateProvider` for search text, `QueryBuilder`
for the list.

### 6. Do NOT

- Do NOT rewrite the whole Riverpod file. Only the async providers that fit the criteria.
- Do NOT create a wrapping `FutureProvider` around a `Query`.
- Do NOT batch-convert. One provider per diff.

## Reference

- `example/lib/patterns/riverpod/README.md` — the boundary rule and the anti-pattern.
- `doc/CONVENTIONS.md`.
