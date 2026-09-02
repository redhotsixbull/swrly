# flutter_hooks × swrly

`swrly` does **not** ship hook bindings. This pattern shows the two
snippets you copy into your own project instead.

**Why the library doesn't ship hooks**: see `doc/CONVENTIONS.md §10`.
Short version:

- Dart has no peer-dep story, so making `flutter_hooks` an optional dep
  isn't clean — every swrly user would pay for it.
- A self-hosted hook runtime would silo `useSwrlyQuery` from your other
  hooks (`useState`, `useEffect`), which defeats the point of hooks.
- `Query.stream` is already a stable hooking point — the canonical hook
  is a ~10-line snippet users can own.

**What to do instead**: copy [`use_swrly.dart`](use_swrly.dart) into
`lib/hooks/` in your project. The `swrly-init` and `swrly-refactor-hooks`
Claude skills install exactly this file. `readme_snippets_test.dart` in
the swrly repo tests this snippet compiles, so it stays honest.

## The snippet at a glance

```dart
QueryState<T> useSwrlyQuery<T>(Query<T> query) {
  useEffect(() { query.fetch(); return null; }, [query.key.toString()]);
  final snapshot = useStream<QueryState<T>>(
    query.stream, initialData: query.state,
  );
  return snapshot.data ?? query.state;
}
```

Under 10 lines. This is deliberate — a canonical snippet you can read
in one glance and modify to taste.

## When to reach for `MutationBuilder` instead of `useSwrlyMutation`

Use the built-in `MutationBuilder` when you want:

- `onMutate` returning a rollback closure (auto rollback on error).
- `onSuccess` / `onSettled` callbacks that fire regardless of mount state.

Use `useSwrlyMutation` (from this snippet) when the mutation is trivial
— fire-and-forget button handler where the mount-check + async ergonomics
of a hook are what you want.
