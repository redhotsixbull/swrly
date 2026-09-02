---
name: swrly-init
description: Add `swrly` (server-state cache for Flutter) to a Flutter project — detect the project's state management, install the dependency, scaffold a `lib/queries/` folder with a first `Query` definition, and (for `flutter_hooks` projects) drop in the canonical `useSwrlyQuery` snippet. Use when the user asks to install swrly, set up swrly, or add swrly to a Flutter project.
---

# swrly-init

Set up `swrly` in a Flutter project without touching existing screens.
This skill is additive — it does NOT refactor existing fetch code (that's
`swrly-refactor-*`).

## Prerequisites (check these first, halt if any fail)

1. Working directory is a Flutter project (`pubspec.yaml` exists and lists
   `flutter:` under `dependencies`).
2. Not already a swrly consumer — if `swrly:` is in `pubspec.yaml`, halt
   and suggest `swrly-upgrade` (or just tell the user it's already set up).

## Steps

### 1. Detect the shape of the project

Read `pubspec.yaml` and note which of these are present:

- `flutter_bloc` / `bloc`
- `provider`
- `flutter_riverpod` / `riverpod`
- `flutter_hooks`
- `hooks_riverpod` (implies both)
- `dio` / `http` / `chopper` / `graphql` / any FirebaseX / `supabase_flutter`
- `get` (GetX — see "GetX" note below)

Also count files under `lib/` to gauge project size:

- **Small** (< 20 files): scaffold `lib/queries/` at root
- **Medium/large** (≥ 20 files): ask whether to use `lib/queries/` OR
  `lib/features/<feature>/queries/` per-feature (default to the latter
  if there's already a `lib/features/` folder)

### 2. Install swrly

Run:

```
flutter pub add swrly
```

This resolves the latest version and runs `pub get` in one step. Do NOT
hand-edit `pubspec.yaml` with a hardcoded version literal — `flutter pub
add` picks the current release from pub.dev, which is the only place a
version literal should live (`doc/CONVENTIONS.md §3`). Do NOT mention any
specific version number in the docs or comments you write.

### 3. Scaffold `lib/queries/` with a first Query

Two sub-cases:

**a. Project has NO obvious HTTP call sites yet** (greenfield or the HTTP
layer is elsewhere). Install a placeholder `lib/queries/example_query.dart`
copied from `templates/query_definition.dart.tmpl` — the `{{FILE_PATH}}`
and `{{HTTP_PACKAGE}}` placeholders should be substituted before writing:
`{{FILE_PATH}}` → `lib/queries/example_query.dart`, `{{HTTP_PACKAGE}}` →
the detected HTTP package name (`dio`, `http`, `chopper`, `graphql`) or
delete the import line if none.

**b. Project already has HTTP calls** (e.g., an `Api` class, a `Repository`,
inline `dio.get(...)` in a notifier). Grep for `dio.get\|http.get\|api\.`
and pick ONE clear call site. Write a **real** Query for that resource
into `lib/queries/<resource>.dart` (per-resource file, not one blob) —
pointing the `fn` at the actual call. Then ALSO scaffold the placeholder
`example_query.dart` so users see the template shape.

Example when the project has an `Api` class with `Api.getPosts()`:

```dart
// lib/queries/posts.dart
import 'package:swrly/swrly.dart';
import '../api.dart';

final postsQuery = Query<List<Post>>(
  key: const ['posts'],
  fn: () => Api.getPosts(),
  staleTime: const Duration(seconds: 30),
);
```

Every generated Query MUST include `staleTime` — never leave it unset
(`doc/CONVENTIONS.md §6`).

### 4. Show one usage snippet in a README fragment

Append a short section to the project's README (or create a
`docs/swrly.md` if the README is untouchable) that includes:

- Where queries live (the folder chosen in step 1)
- The rule from `doc/CONVENTIONS.md §2` (server state vs client state)
- One `QueryBuilder.of(<query>, ...)` example — use the real Query name
  from step 3 (`postsQuery` etc.) not `exampleQuery` when a real one exists
- Link to the state-management-appropriate pattern in the swrly repo,
  pinned to a specific commit or tag rather than `main` (a `main` link
  breaks if the repo restructures — use `github.com/redhotsixbull/swrly/tree/<sha-or-tag>/example/lib/patterns/<mgmt>/`):
  - Detected `flutter_bloc` → link `example/lib/patterns/bloc/`
  - Detected `provider` → link `example/lib/patterns/provider/`
  - Detected `flutter_riverpod` → link `example/lib/patterns/riverpod/`
  - Detected `flutter_hooks` → link `example/lib/patterns/hooks/`
  - None of the above → link `example/lib/patterns/plain/`

### 5. If `flutter_hooks` is present — drop in the canonical hook

Copy `templates/use_swrly.dart.tmpl` to `lib/hooks/use_swrly.dart`.
This is the same snippet documented in the swrly README's "flutter_hooks"
section. Do NOT add `flutter_hooks` as a dep of swrly — it's already in
the user's project.

If `flutter_hooks` is NOT present: skip this step. Do not suggest adding it.

### 6. Do NOT do these things

- Do not refactor any existing fetch code (that's `swrly-refactor-*`).
- Do not add `swrly_hooks` as a "separate package" — the library owner
  explicitly decided against splitting hooks into a companion package
  (see `doc/CONVENTIONS.md §10`).
- Do not add persistence, cancellation, infinite queries — swrly does
  not ship those yet. See `doc/CONVENTIONS.md §12`.
- Do not create multiple `QueryClient` instances — the singleton
  `QueryClient.instance` is the intended usage.

## GetX

If `get` (GetX) is in the pubspec, halt and tell the user:

> GetX is not in the scope of the current swrly skills. `swrly` still works
> alongside GetX (it's just an object), but this skill won't scaffold a
> best-practice example for that combination. Please install swrly manually
> per the README, then reach for `swrly-refactor-spaghetti` if you want to
> gradually pull server fetches out of your GetX controllers.

## Reference

- Conventions the generated code follows: `doc/CONVENTIONS.md`
- The full skill design plan: `doc/CLAUDE_SKILLS_PLAN.md`
- Working patterns to model after: `example/lib/patterns/`
