# Provider × swrly

**Client state**: `SearchNotifier extends ChangeNotifier`.
**Server state**: `postsQuery` / `postQuery(id)` via `QueryBuilder.of(...)`.

The `SearchNotifier` has **no** `List<Post>`, **no** `isLoading`, **no** `error`
field. If you find yourself adding those to a ChangeNotifier, that's the
signal to move that state to a `Query` instead — server state doesn't belong
in a client-state notifier.

## Refactoring an existing Provider app

Typical anti-pattern this pattern replaces:

```dart
class PostsNotifier extends ChangeNotifier {
  List<Post> posts = [];
  bool isLoading = false;
  Object? error;

  Future<void> load() async {
    isLoading = true; notifyListeners();
    try { posts = await api.getPosts(); }
    catch (e) { error = e; }
    finally { isLoading = false; notifyListeners(); }
  }
}
```

You get:
- No caching (every screen mount refetches).
- No dedupe (two `load()` calls in flight → two requests).
- No stale/fresh distinction.
- Duplicated `isLoading`/`error` fields across notifiers.

Replace with a `Query` for the posts, and keep the notifier for whatever
*client* state actually needed it — often nothing.

## What swrly does that Provider alone can't

- Multiple screens mounting the same `QueryBuilder.of(postsQuery)` share
  one cache entry and one in-flight request.
- `staleTime` gives you "instant on re-open, background refetch when stale".
- Optimistic create with automatic rollback (`MutationBuilder.onMutate`)
  is a one-function pattern — hand-rolling this in a ChangeNotifier is
  the classic source of "the UI showed it but the server said no" bugs.
