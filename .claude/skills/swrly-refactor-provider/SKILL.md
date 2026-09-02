---
name: swrly-refactor-provider
description: Refactor a Provider-based Flutter project where `ChangeNotifier`s hold server-fetched data (List/Model + isLoading + error) — move server state to swrly, keep client state in the ChangeNotifier. Use when the user asks to reduce Provider boilerplate for fetch code, remove `isLoading` from a ChangeNotifier, or clean up a `PostsNotifier`-style class.
---

# swrly-refactor-provider

Move **server state out of `ChangeNotifier`s**. The notifier keeps only
client state (search text, selected tab, form state); the list, its
loading, its error live in swrly.

## Prerequisites

- `provider` is in `pubspec.yaml`.
- `swrly` is installed.
- `lib/queries/` exists.

## Steps

### 1. Find candidate ChangeNotifiers

Grep for notifiers that hold fetched data:

```
grep -rn "extends ChangeNotifier" lib/
```

For each, read the file and look for the antipattern:

- A field like `List<Model> items = []` or `Model? current`
- Companion fields: `bool isLoading`, `Object? error`
- A method that calls an API and does `notifyListeners()` on completion

That's the split candidate.

### 2. Extract the fetch to a `Query`

Add to `lib/queries/`:

```dart
final postsQuery = Query<List<Post>>(
  key: const ['posts'],
  fn: () => api.getPosts(),
  staleTime: const Duration(seconds: 30),
);
```

### 3. Strip the ChangeNotifier

Remove:
- The `posts` / `items` / `data` field
- The `isLoading` / `error` fields
- The `load()` / `fetch()` method
- Any `notifyListeners()` calls that were only there for the above

Keep any actual client state (filter text, selected id, form state).
If NOTHING remains after the strip, delete the notifier and remove
its `ChangeNotifierProvider` — the widgets that consumed it now use
`QueryBuilder.of(postsQuery)` directly.

Model after [`example/lib/patterns/provider/`](../../../example/lib/patterns/provider/).

### 4. Rewrite the consumer widgets

Wherever `Consumer<PostsNotifier>` was used purely to read the fetched
list, replace with `QueryBuilder.of(postsQuery)`. Where it was used to
read client state (filter/etc.), keep the `Consumer` but only over the
remaining fields.

Both can coexist — `QueryBuilder` for the data, `Consumer` for the
client state. See the pattern example for the two-layer nesting.

### 5. Mutations

If the notifier had `Future<void> addPost(...)` that appended to a
local list, replace with a `MutationBuilder`:

```dart
MutationBuilder<Post, String>(
  mutationFn: (title) => api.createPost(title),
  onMutate: (title) {
    final prev = QueryClient.instance.getQueryData<List<Post>>(['posts']) ?? [];
    QueryClient.instance.setQueryData<List<Post>>(
      ['posts'], [Post.draft(title), ...prev],
    );
    return () => QueryClient.instance.setQueryData<List<Post>>(['posts'], prev);
  },
  onSuccess: (post, _) => QueryClient.instance.invalidateQueries(['posts']),
  builder: ...
);
```

### 6. Do NOT

- Do NOT leave `List<Post>` in a ChangeNotifier "just in case". Duplicated state → cache incoherence.
- Do NOT wrap `swrly` inside a ChangeNotifier — that recreates the antipattern.
- Do NOT batch-convert notifiers. One per diff.

## Reference

- `example/lib/patterns/provider/` — the target shape.
- `doc/CONVENTIONS.md §2` — the server/client boundary rule.
