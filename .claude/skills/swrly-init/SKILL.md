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

Add to `pubspec.yaml` under `dependencies`:

```yaml
swrly: ^<latest>
```

Then run `flutter pub get`.

Do NOT specify a version literal in any docs or comments you write —
see `doc/CONVENTIONS.md §3`. Only pubspec gets a version.

### 3. Scaffold `lib/queries/` with a first Query

Create `lib/queries/` (or the feature-scoped location) with an example
`Query` that uses the project's existing HTTP client. Use the template
in `templates/query_definition.dart.tmpl` — substitute the HTTP client
call the project actually uses.

Example if the project uses `dio`:

```dart
// lib/queries/example_query.dart
import 'package:swrly/swrly.dart';
// import 'package:dio/dio.dart';   // uncomment when wiring to your dio instance

/// Example Query — replace with a real one from your app.
///
/// See doc/CONVENTIONS.md §5 for the definition placement rules and
/// §6 for staleTime guidance.
final exampleQuery = Query<Map<String, dynamic>>(
  key: const ['example'],
  fn: () async {
    // final dio = /* your existing dio instance */;
    // return (await dio.get<Map<String, dynamic>>('/example')).data!;
    throw UnimplementedError('replace with a real fetcher');
  },
  staleTime: const Duration(seconds: 30),
);
```

### 4. Show one usage snippet in a README fragment

Append a short section to the project's README (or create a
`docs/swrly.md` if the README is untouchable) that includes:

- Where queries live (the folder chosen in step 1)
- The rule from `doc/CONVENTIONS.md §2` (server state vs client state)
- One `QueryBuilder.of(exampleQuery, ...)` example
- Link to the state-management-appropriate pattern in the swrly repo:
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
