# AGENTS.md — instructions for AI assistants in a swrly project

This file is a **living rulebook** for AI coding assistants (Claude
Code, Cursor, Aider, GitHub Copilot, Windsurf, Continue, ...) working
in a Flutter project that uses [`swrly`](https://pub.dev/packages/swrly).
It defines the conventions the assistant should follow when writing
any code that touches server state — new features as well as
refactors.

**When this applies**: any code that fetches, caches, mutates, or
displays data owned by a remote source (REST/GraphQL API, Firebase,
Supabase, gRPC, WebSocket, database service, etc.). Pure client state
(form inputs, UI toggles, navigation, selection) is out of scope —
use whichever state-management library the project already has
(Provider / Riverpod / Bloc / setState / hooks).

## Default policy

> Server state in this project is owned by `swrly`. Do NOT introduce a
> new `FutureBuilder`, hand-rolled `_isLoading`/`_error` field trio,
> or `ChangeNotifier` / `Cubit` / `Notifier` that stores fetched data.

## How to write new server-state code

### Fetching (GET)

Define one `Query` or `QueryFamily` per resource in
`lib/queries/<resource>.dart` (or `lib/<feature>/queries/<resource>.dart`
if the project is organized by feature):

```dart
// lib/queries/posts.dart
import 'package:swrly/swrly.dart';
import '../api.dart';

// No argument
final postsQuery = Query<List<Post>>(
  key: const ['posts'],
  fn: () => Api.getPosts(),
  staleTime: const Duration(seconds: 30),   // REQUIRED — never leave unset
);

// One argument
final postQuery = QueryFamily<Post, int>(
  prefix: const ['post'],
  fn: (id) => Api.getPost(id),
  staleTime: const Duration(minutes: 1),
);
```

Consume from a widget:

```dart
QueryBuilder.of(
  postsQuery,
  builder: (context, state, refetch) {
    if (state.isLoading && !state.hasData) return const CircularProgressIndicator();
    if (state.isError && !state.hasData) return Text('${state.error}');
    return PostsView(state.data!);
  },
)
```

If the project has `flutter_hooks` in its pubspec, prefer
[`swrly_hooks`](https://pub.dev/packages/swrly_hooks)'s
`useSwrlyQuery(postsQuery)` inside `HookWidget`s (install with
`flutter pub add swrly_hooks`).

### Mutating (POST / PUT / PATCH / DELETE)

Use `MutationBuilder`. For optimistic writes, return a rollback closure
from `onMutate` — swrly runs it for you on failure:

```dart
MutationBuilder<Post, String>(
  mutationFn: (title) => Api.createPost(title),
  onMutate: (title) {
    final prev = QueryClient.instance.getQueryData<List<Post>>(['posts']) ?? [];
    QueryClient.instance.setQueryData<List<Post>>(
      ['posts'], [Post.draft(title), ...prev],
    );
    return () => QueryClient.instance.setQueryData<List<Post>>(['posts'], prev);
  },
  onSettled: (_) => QueryClient.instance.invalidateQueries(['posts']),
  builder: (context, mutate, state) => ...,
)
```

### Invalidation

- Single key: `postsQuery.invalidate()` (from the `Query` object)
- Prefix: `QueryClient.instance.invalidateQueries(['post'])`
- All entries of a family: `postQuery.invalidateAll()`

Do NOT call `invalidateQueries(const [])` or otherwise nuke the whole
cache — that defeats the point.

## Never do this in a swrly project

- Add a `_data` / `_isLoading` / `_error` field trio to a StatefulWidget for fetch state.
- Put `List<X>` / `Future<X>` / `AsyncValue<X>` for fetched data inside a `ChangeNotifier`, `Cubit`, `Notifier`, `AsyncNotifier`, or similar.
- Introduce a NEW `FutureBuilder` for a fetch. (Existing ones can stay until converted — see the refactor skill below.)
- Write `Query(...)` / `QueryFamily(...)` inline inside a widget file — always live in `lib/queries/`.
- Hardcode a `queryKey` list literal at the call site — always via a `Query` / `QueryFamily` definition (typos become silent cache misses).
- Wrap `Query.fetch()` inside a `FutureProvider` (Riverpod) or a `ChangeNotifier` field — that's a double cache, both sides go out of sync.
- Omit `staleTime` on a Query definition.
- Use a custom (non-primitive) object as a `QueryFamily` argument without `argKey`.

## Named tasks — fetch the deep skill

For substantial operations, fetch the matching skill from raw GitHub
and follow its steps in order. Do not batch multiple files in a single
diff — one file per pass, wait for user approval.

| Task | Skill URL |
|---|---|
| Install swrly in a Flutter project | https://raw.githubusercontent.com/redhotsixbull/swrly/main/.claude/skills/swrly-init/SKILL.md |
| Convert existing `FutureBuilder`s → `QueryBuilder` | https://raw.githubusercontent.com/redhotsixbull/swrly/main/.claude/skills/swrly-refactor-futurebuilder/SKILL.md |
| Kill `_isLoading` / `_error` / `_data` trio in a `StatefulWidget` | https://raw.githubusercontent.com/redhotsixbull/swrly/main/.claude/skills/swrly-refactor-stateful/SKILL.md |
| Strip server state out of a `ChangeNotifier` (Provider project) | https://raw.githubusercontent.com/redhotsixbull/swrly/main/.claude/skills/swrly-refactor-provider/SKILL.md |
| Migrate `FutureProvider` / `AsyncNotifier` (Riverpod project) | https://raw.githubusercontent.com/redhotsixbull/swrly/main/.claude/skills/swrly-refactor-riverpod/SKILL.md |
| Refactor a Cubit/Bloc that fetches (keep state machines, swap the cache) | https://raw.githubusercontent.com/redhotsixbull/swrly/main/.claude/skills/swrly-refactor-bloc/SKILL.md |
| Convert `HookWidget` useState+useEffect fetch → `useSwrlyQuery` | https://raw.githubusercontent.com/redhotsixbull/swrly/main/.claude/skills/swrly-refactor-hooks/SKILL.md |
| Legacy no-state-mgmt project (map first, migrate one screen at a time) | https://raw.githubusercontent.com/redhotsixbull/swrly/main/.claude/skills/swrly-refactor-spaghetti/SKILL.md |
| Audit a swrly project for antipatterns (read-only report) | https://raw.githubusercontent.com/redhotsixbull/swrly/main/.claude/skills/swrly-audit/SKILL.md |

## Explicit non-goals — refuse if asked

Do NOT invent or auto-apply any of these — cite the roadmap and stop:

- Persistence adapters (`hive`, `shared_preferences`, `drift`) — swrly is in-memory only right now (v0.4 roadmap).
- Request cancellation on subscriber departure — v0.4 roadmap.
- Infinite / paginated query helper — v0.4 roadmap.
- A `swrly` DevTools panel — v0.5 roadmap.

If a user asks for these, tell them the current state, link the
roadmap, and stop; don't build a workaround inside their code.

## Reference

- **Full ruleset** (cited by every skill): https://raw.githubusercontent.com/redhotsixbull/swrly/main/doc/CONVENTIONS.md
- **Pattern implementations** for plain / Provider / Riverpod / Bloc / Hooks: https://github.com/redhotsixbull/swrly/tree/main/example/lib/patterns
- **README**: https://github.com/redhotsixbull/swrly
