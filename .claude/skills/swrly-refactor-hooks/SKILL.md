---
name: swrly-refactor-hooks
description: In a flutter_hooks project, install the `swrly_hooks` companion package and refactor `useState`/`useEffect`-based fetch code to `useSwrlyQuery`. Use when the user asks to reduce useEffect + useState fetch boilerplate in a HookWidget, or convert hook-based fetches to a cache.
---

# swrly-refactor-hooks

`swrly` core does not ship hook bindings. The **`swrly_hooks`** companion
package does — see `doc/CONVENTIONS.md §10`. This skill installs the
package and refactors hook-based fetches to use it.

## Prerequisites

- `flutter_hooks` in `pubspec.yaml`.
- `swrly` installed.
- `lib/queries/` exists (per `swrly-init` scaffolding).

If `flutter_hooks` is NOT in the project, halt and redirect the user to
`swrly-refactor-stateful` — DO NOT suggest adding flutter_hooks.

## Steps

### 1. Install `swrly_hooks`

```
flutter pub add swrly_hooks
```

Do NOT copy a hand-rolled snippet into `lib/hooks/`. The
package supersedes that pattern and handles subscriber lifecycle,
canonical key hashing, and unhandled-async details correctly — bugs
that a copy-paste snippet routinely gets wrong (documented in the
package's README).

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

Add to `lib/queries/<resource>.dart`:

```dart
import 'package:swrly/swrly.dart';
import '../api.dart';

final userQuery = QueryFamily<User, int>(
  prefix: const ['user'],
  fn: (id) => api.getUser(id),
  staleTime: const Duration(seconds: 30),
);
```

### 4. Rewrite the HookWidget

```dart
import 'package:swrly_hooks/swrly_hooks.dart';

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

For fire-and-forget button handlers, `useSwrlyMutation` (from
`swrly_hooks`) is enough. For anything that needs `onMutate` rollback
closures, `onSuccess`/`onSettled` callbacks that fire regardless of
mount state — use swrly's built-in `MutationBuilder` (not a hook).

### 6. Do NOT

- Do NOT add `flutter_hooks` to a project that doesn't already have it.
- Do NOT copy `useSwrlyQuery`/`useSwrlyMutation` into the user project's
  `lib/hooks/` folder. Install the package.
- Do NOT batch-convert. One HookWidget per diff.

## Reference

- `packages/swrly_hooks/` — the companion package source in the swrly repo.
- `example/lib/patterns/hooks/` — hook pattern demo using the package.
- `doc/CONVENTIONS.md §10`.
