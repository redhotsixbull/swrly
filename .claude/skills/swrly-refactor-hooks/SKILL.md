---
name: swrly-refactor-hooks
description: In a flutter_hooks project, install the canonical `useSwrlyQuery`/`useSwrlyMutation` snippet at `lib/hooks/use_swrly.dart` and refactor `useState`/`useEffect`-based fetch code to use it. Use when the user asks to reduce useEffect + useState fetch boilerplate in a HookWidget, or convert hook-based fetches to a cache.
---

# swrly-refactor-hooks

`swrly` does NOT ship hook bindings — see `doc/CONVENTIONS.md §10`.
This skill installs the canonical snippet the swrly library documents,
then refactors hook-based fetches to use it.

## Prerequisites

- `flutter_hooks` in `pubspec.yaml`.
- `swrly` installed.
- `lib/queries/` exists.

If `flutter_hooks` is NOT in the project, halt and redirect user to
`swrly-refactor-stateful` — DO NOT suggest adding flutter_hooks.

## Steps

### 1. Install the canonical hook snippet

If `lib/hooks/use_swrly.dart` doesn't exist, copy the template from
this skill's `templates/use_swrly.dart.tmpl` (identical to the swrly
repo's `example/lib/patterns/hooks/use_swrly.dart`). This is the source
of truth — do not modify it during install.

### 2. Find candidate `HookWidget`s

Grep for HookWidgets that fetch data via `useEffect` + `useState`:

```
grep -rn "class .* extends HookWidget" lib/
grep -rn "useState.*loading\|useEffect.*fetch\|useEffect.*load" lib/
```

Typical target shape:

```dart
class UserPage extends HookWidget {
  final int id;
  @override
  Widget build(BuildContext context) {
    final data = useState<User?>(null);
    final loading = useState<bool>(true);
    final error = useState<Object?>(null);

    useEffect(() {
      loading.value = true;
      api.getUser(id).then(
        (u) { data.value = u; loading.value = false; },
        onError: (e) { error.value = e; loading.value = false; },
      );
      return null;
    }, [id]);

    if (loading.value) return CircularProgressIndicator();
    if (error.value != null) return Text('${error.value}');
    return UserView(data.value!);
  }
}
```

### 3. Extract fetch to a `Query`

Add to `lib/queries/`:

```dart
final userQuery = QueryFamily<User, int>(
  prefix: const ['user'],
  fn: (id) => api.getUser(id),
  staleTime: const Duration(seconds: 30),
);
```

### 4. Rewrite the HookWidget

```dart
class UserPage extends HookWidget {
  final int id;
  @override
  Widget build(BuildContext context) {
    final state = useSwrlyQuery(userQuery(id));
    if (state.isLoading && !state.hasData) return const CircularProgressIndicator();
    if (state.isError && !state.hasData) return Text('${state.error}');
    return UserView(state.data!);
  }
}
```

Model after [`example/lib/patterns/hooks/`](../../../example/lib/patterns/hooks/).

### 5. Mutations

For fire-and-forget button handlers, `useSwrlyMutation` is enough.
For anything that needs `onMutate` rollback closures, `onSuccess`, or
`onSettled` — use the built-in `MutationBuilder` (not a hook).

### 6. Do NOT

- Do NOT add `flutter_hooks` to a project that doesn't already have it.
- Do NOT modify the canonical `use_swrly.dart` snippet — it's a copy
  of the swrly-repo canonical version and must match to stay in sync.
- Do NOT split into "swrly_hooks" or a similar companion package.
- Do NOT batch-convert. One HookWidget per diff.

## Reference

- `example/lib/patterns/hooks/use_swrly.dart` — canonical snippet.
- `example/lib/patterns/hooks/README.md` — the "why no library hooks" rationale.
- `doc/CONVENTIONS.md §10`.
