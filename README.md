# swrly

Async data-fetching and server-state cache for Flutter, inspired by [TanStack Query](https://tanstack.com/query) and [SWR](https://swr.vercel.app/).

Riverpod/Bloc are great for client state. `swrly` is for the *other* kind — the state that lives on your server, needs cache invalidation, background refetching, and staleness rules.

> **Status:** v0.0.1 — early alpha. API surfaces may change.

## Features (v0.0.1)

- `QueryClient` with in-memory cache keyed by `QueryKey` (list of any comparable values)
- `QueryBuilder<T>` widget with automatic subscribe/unsubscribe
- Stale-while-revalidate: `staleTime` + `cacheTime` (GC after last subscriber leaves)
- Prefix-based `invalidateQueries`
- Optimistic writes via `setQueryData` / `getQueryData`
- `MutationBuilder<T, V>` with `onSuccess` / `onError` / `onSettled`
- Automatic refetch on app resume

## Not yet

- Infinite queries
- Optimistic-update helpers with rollback
- Persistence adapters
- Devtools
- Suspense-style widgets

## Quick example

```dart
final client = QueryClient.instance;

QueryBuilder<User>(
  queryKey: ['user', userId],
  queryFn: () => api.getUser(userId),
  staleTime: Duration(minutes: 1),
  builder: (context, state, refetch) {
    if (state.isLoading) return CircularProgressIndicator();
    if (state.isError) return Text('Error: ${state.error}');
    return Text(state.data!.name);
  },
);

// Later, after a mutation:
client.invalidateQueries(['user']);
```

Mutations:

```dart
MutationBuilder<User, UpdateUserInput>(
  mutationFn: (input) => api.updateUser(input),
  onSuccess: (_, __) => QueryClient.instance.invalidateQueries(['user']),
  builder: (context, mutate, state) => ElevatedButton(
    onPressed: state.isLoading ? null : () => mutate(input),
    child: Text(state.isLoading ? 'Saving...' : 'Save'),
  ),
);
```

## License

MIT
