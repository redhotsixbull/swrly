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

## Hard-stop check — features swrly cannot yet replace

BEFORE proposing any conversion, grep the target provider file for these
Riverpod features. If ANY are present, HALT and tell the user the
migration would regress functionality. swrly's roadmap covers these in
v0.4+ but they are not in the current release.

```
grep -nE "cancelToken|ref\.onDispose|ref\.keepAlive|ref\.watch\(.*[Pp]rovider" <file>
```

| Feature in the code | Why swrly can't replace it (yet) |
|---|---|
| `ref.cancelToken()` + dio `CancelToken` | swrly does not cancel in-flight requests on subscriber departure (v0.4 roadmap). Migration would silently keep abandoned requests running. |
| `ref.onDispose(...)` tied to fetch cleanup | swrly's cache lifecycle (`cacheTime` GC after last subscriber) is different — the user's cleanup contract disappears. |
| `ref.keepAlive()` / explicit AutoDispose tuning | swrly's GC is opinionated (`cacheTime` after last subscriber) — no explicit "keepAlive" primitive. |
| Provider composition: `ref.watch(otherProvider)` **inside another provider's body** | swrly Queries do not compose across each other automatically; the graph the user built with `ref.watch` chaining doesn't have a 1:1 swrly equivalent. |
| Inline debounce (`Future.delayed` + `cancelToken.isCancelled`) | swrly has no debounce primitive. |

If the provider is "clean" — plain `FutureProvider((ref) async => api.getX())`
with no cancellation, no composition, no debounce — proceed to Step 1.

## Codegen (`@riverpod` annotation)

Modern Riverpod projects use the `@riverpod` code generator instead of
constructor-style providers. Detection:

```
grep -rnE "@riverpod|@Riverpod" lib/ --include='*.dart' --exclude='*.g.dart'
```

The constructor-form grep (`FutureProvider\|AsyncNotifier`) misses these
— add the annotation grep. When you find annotated providers, apply the
**same** hard-stop check (cancelToken, composition, etc.) to the
annotated function body.

Only after both filters pass should you proceed with the conversion.

## Steps

### 1. List candidate providers

```
grep -rnE "FutureProvider|AsyncNotifier|@riverpod|@Riverpod" lib/ --include='*.dart' --exclude='*.g.dart'
```

The alternation is intentional: constructor-form + codegen-form both
count. Excluding `.g.dart` keeps generator output out of the results
(which is where matches for `$FutureProvider` etc. also live).

For each, apply the "Hard-stop check" above. If it uses cancelToken,
composition, debounce, or explicit keepAlive — do NOT propose a
conversion; explain to the user which feature blocks it and stop.

For the survivors: check if it fetches from an API and whether it's
doing more than the trivial "call once, return." Present the list to
the user.

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
