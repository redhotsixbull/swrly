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
grep -rnE "extends .*Cubit|extends .*Bloc" lib/
```

The wildcard is intentional — `HydratedCubit`, `HydratedBloc`,
`ReplayBloc`, custom `BaseBloc` subclasses all inherit the Cubit/Bloc
surface and need the same treatment. A naked `extends Cubit` grep misses
them.

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

### 4. State machine Bloc: swap where the cache SHOULD live

The right location for the swap depends on whether the repository already
has hand-rolled caching.

**Case A — repository has a `_cached` field or in-memory memoization:**
swap happens IN the repository. The Bloc's call site stays the same.

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

**Case B — repository is a thin API wrapper with no cache** (very common
when following clean-architecture patterns): swap happens at the CALL
SITE (the Bloc), not in the repo. The repo stays untouched.

**Instance-based repo caveat**: if the `Query` fn needs the repo
instance (as opposed to a static or singleton), a top-level `Query`
definition can't reference the repo directly. Three options:

1. **Factory function** (simplest, small overhead):
   ```dart
   // lib/<feature>/queries/weather.dart
   QueryFamily<Weather, String> weatherQuery(WeatherRepository repo) =>
       QueryFamily<Weather, String>(
         prefix: const ['weather'],
         fn: (city) => repo.getWeather(city),
         staleTime: const Duration(minutes: 15),
       );
   ```
   Callers do `weatherQuery(_repo)(city).fetch()`. Cache is per-key
   so multiple factory invocations still hit the same entry —
   swrly's last-writer-wins for shared keys applies to the captured
   `fn`, which is fine as long as all callers use the same repo
   instance.

2. **Singleton repo**: refactor `WeatherRepository` to expose
   `WeatherRepository.instance`, then define `weatherQuery` at top
   level referencing the singleton. Cleaner but a wider refactor.

3. **DI container**: pass the repo via a service locator (get_it,
   riverpod, provider). Bigger commitment.

Recommend (1) unless the project already has DI infrastructure.

Before (inside a Cubit):
```dart
final data = await _repository.getWeather(city);
```

After (option 1):
```dart
final data = await weatherQuery(_repository)(city).fetch();
```

Either way, the Bloc's state machine stays. It now gets dedupe,
`staleTime`, and future features for free.

Model after [`example/lib/patterns/bloc/`](../../../example/lib/patterns/bloc/).

### 4a. HydratedBloc / HydratedCubit specifically

`hydrated_bloc` persists Bloc state to disk. swrly caches in memory.
They solve **different** problems and should coexist:

- `hydrated_bloc`: "on app relaunch, restore the last-seen state so the
  user doesn't stare at a blank screen while the first fetch runs."
- `swrly`: "within a session, dedupe requests + serve fresh entries
  instantly without hitting the network."

Do NOT tell the user swrly makes `hydrated_bloc` redundant — it doesn't.
swrly is in-memory only (persistence is a v0.4 roadmap item). If the
Bloc is a `HydratedBloc`/`HydratedCubit`:

- Keep `hydrated_bloc` as-is.
- Route the fetch call through `weatherQuery(city).fetch()` (Case B above).
- On refetch (user pulled to refresh), the Cubit emits new state, which
  hydrated_bloc persists — normal flow.

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
