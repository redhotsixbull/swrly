# Bloc / Cubit × swrly

**Client state**: `SearchCubit extends Cubit<String>`.
**Server state**: `postsQuery` / `postQuery(id)` via `QueryBuilder.of(...)`.

## Where the boundary sits

Bloc encourages you to model the whole screen as a state machine —
including fetch loading/success/error. That works, but it means every
Bloc that fetches has its own copy of `staleTime`, dedupe, invalidation,
and rollback logic. Multiplied across features, that's the class of bug
this pattern removes.

The rule: **Bloc for state machines, swrly for the cache**.

- Feature has a real state machine (a wizard, an upload pipeline, an
  interactive checkout)? Keep the Bloc. Its state is genuinely client
  state — orchestration, not data.
- Feature is "load a list, show it, refetch on invalidation"? That's not
  a state machine — it's a cache. Use swrly directly.

## Refactoring an existing Bloc app

Look for a Bloc whose states are `Loading` / `Loaded` / `Error` and
nothing more interesting. That Bloc is a `QueryBuilder` waiting to happen:

```dart
// Before:
class PostsBloc extends Bloc<PostsEvent, PostsState> {
  PostsBloc(this.repo) : super(PostsInitial()) {
    on<LoadPosts>((e, emit) async {
      emit(PostsLoading());
      try { emit(PostsLoaded(await repo.getPosts())); }
      catch (e) { emit(PostsError(e)); }
    });
  }
}
```

```dart
// After — no bloc, no events, no states:
QueryBuilder.of(postsQuery, builder: (context, state, refetch) => ...)
```

Blocs that DO have interesting state machines (transitions, guards,
substates) stay put — but call `postsQuery.fetch()` from the repository
layer instead of hand-rolling a cache inside the Bloc.
