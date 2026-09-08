---
name: swrly-refactor-futurebuilder
description: Convert `FutureBuilder` usage in a Flutter project to `swrly`'s `QueryBuilder` — the safest swrly migration path. Use when the user asks to replace FutureBuilder with swrly, migrate FutureBuilder to a cache, or generally cache Future-based fetches.
---

# swrly-refactor-futurebuilder

The safest swrly migration: `FutureBuilder` → `QueryBuilder`. Nearly 1:1
but not blind — `FutureBuilder`'s re-fetch-on-rebuild is sometimes
intentional.

## Prerequisites

- `swrly` in `pubspec.yaml`.
- A `Query`/`QueryFamily` folder exists (`lib/queries/` or
  `lib/<feature>/queries/`). If it does NOT exist, halt and run
  `swrly-init` first (which creates it and scaffolds the first
  Query). Do not create the folder silently as part of this skill.

## Steps

### 1. Find all `FutureBuilder` usages

Grep the project:

```
grep -rn "FutureBuilder" lib/
```

Present the list to the user. Do NOT batch-convert. Confirm one file at
a time.

### 2. For each usage, classify

Look at the `future:` parameter:

- **Constant call** (`fetchPosts()`, `api.getUser(id)`) → safe candidate.
- **Inline closure with captured state** (`() async { ...uses widget.foo... }`) → still convertible but the `queryKey` must include the captured state.
- **Deliberately re-runs on rebuild** (e.g., re-fires when a controller ticks): halt and confirm with user — this is the case where `FutureBuilder`'s no-cache behavior is intentional.

### 3. Extract to a `Query` in `lib/queries/`

Do NOT create inline `Query(...)` inside the widget file — that violates
`doc/CONVENTIONS.md §5`. Add a new definition to the appropriate
`lib/queries/` file:

```dart
final userQuery = QueryFamily<User, int>(
  prefix: const ['user'],
  fn: (id) => api.getUser(id),
  staleTime: const Duration(seconds: 30),   // §6 — always specify
);
```

### 4. Replace `FutureBuilder` with `QueryBuilder.of(...)`

Model after [`example/lib/patterns/plain/posts_screen.dart`](../../../example/lib/patterns/plain/posts_screen.dart)
in the swrly repo.

Before:
```dart
FutureBuilder<User>(
  future: api.getUser(id),
  builder: (context, snap) {
    if (snap.connectionState == ConnectionState.waiting) return CircularProgressIndicator();
    if (snap.hasError) return Text('${snap.error}');
    return UserView(snap.data!);
  },
)
```

After:
```dart
QueryBuilder.of(
  userQuery(id),
  builder: (context, state, refetch) {
    if (state.isLoading && !state.hasData) return const CircularProgressIndicator();
    if (state.isError && !state.hasData) return Text('${state.error}');
    return UserView(state.data!);
  },
)
```

### 5. Give the user the win to look for

After the diff, tell the user what to verify:

- Re-mounting the widget within `staleTime` should not fire a new HTTP request.
- Two widgets on the same key share one in-flight request.

### 6. Do NOT

- Do NOT convert `FutureBuilder`s whose `future:` is a rebuild-driven
  side effect (see step 2).
- Do NOT collapse multiple `FutureBuilder`s into one giant `Query` —
  each logical fetch keeps its own key.
- Do NOT bulk-apply — one file per pass, wait for approval.

## Reference

- `doc/CONVENTIONS.md` — every rule the diffs follow.
- `example/lib/patterns/plain/` — the canonical target shape.
