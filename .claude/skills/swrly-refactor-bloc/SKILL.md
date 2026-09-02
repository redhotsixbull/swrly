---
name: swrly-refactor-bloc
description: In a Bloc/Cubit project, identify Blocs whose only job is fetch-loading-error-state and replace them with swrly directly; for Blocs that DO have real state machines, move the fetch cache to swrly via the repository layer. Use when the user asks to remove Bloc fetch boilerplate, replace a Loading/Loaded/Error state trio, or refactor Bloc data caching.
---

# swrly-refactor-bloc

Split Blocs into two buckets:

- **Data Blocs** — `Loading` / `Loaded` / `Error` states, nothing more.
  Replace with `swrly` directly.
- **State machine Blocs** — real transitions, guards, substates. Keep
  the Bloc, but move the fetch cache into the repository the Bloc calls
  (so `postsQuery.fetch()` replaces hand-rolled `_cachedPosts`).

## Prerequisites

- `flutter_bloc` / `bloc` in `pubspec.yaml`.
- `swrly` installed.
- `lib/queries/` exists.

## Steps

### 1. List candidate Blocs

```
grep -rn "extends Bloc\|extends Cubit" lib/
```

For each, read the states file. A "data Bloc" typically has ~3 states
(Initial, Loading, Loaded, Error) and one main event (Load / Refresh).

### 2. Classify

For each Bloc, decide:

- **Data Bloc → full replacement.** Confirm with user before deleting
  the Bloc + states + events.
- **State machine → repository-layer swap.** The Bloc stays; only its
  data source changes.

If uncertain, ask the user. Do not guess.

### 3. Data Bloc: full replacement

Extract the fetch to `lib/queries/`:

```dart
final postsQuery = Query<List<Post>>(
  key: const ['posts'],
  fn: () => api.getPosts(),
  staleTime: const Duration(seconds: 30),
);
```

Replace `BlocBuilder<PostsBloc, PostsState>` with `QueryBuilder.of(postsQuery)`:

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

Then delete:
- The Bloc class
- The state classes (Loading/Loaded/Error)
- The event classes (Load/Refresh)
- The `BlocProvider` wrapping the screen (if it wrapped only this Bloc)

### 4. State machine Bloc: repository-layer swap

Do NOT delete the Bloc. Instead, inside the repository the Bloc calls:

Before:
```dart
class PostsRepository {
  List<Post>? _cached;
  Future<List<Post>> getPosts() async {
    if (_cached != null) return _cached!;
    _cached = await api.getPosts();
    return _cached!;
  }
}
```

After:
```dart
class PostsRepository {
  Future<List<Post>> getPosts() => postsQuery.fetch();  // through swrly cache
}
```

The Bloc's state machine stays. It now gets dedupe, `staleTime`, and
future features (persistence, cancellation) for free.

Model after [`example/lib/patterns/bloc/`](../../../example/lib/patterns/bloc/).

### 5. Mutations

For write events (`CreatePostRequested`), the handler can do:

```dart
on<CreatePostRequested>((event, emit) async {
  emit(state.copyWith(isSaving: true));
  try {
    final post = await api.createPost(event.title);
    QueryClient.instance.invalidateQueries(['posts']);
    emit(state.copyWith(isSaving: false));
  } catch (e) {
    emit(state.copyWith(isSaving: false, error: e));
  }
});
```

Or, for optimistic writes, prefer `MutationBuilder` at the widget level
and keep the Bloc out of it entirely.

### 6. Do NOT

- Do NOT delete a Bloc without confirming it's a data Bloc.
- Do NOT introduce a swrly-holding "PostsBloc" (Bloc wrapping swrly).
- Do NOT batch-convert Blocs. One at a time.

## Reference

- `example/lib/patterns/bloc/README.md` — where the boundary sits.
- `doc/CONVENTIONS.md`.
