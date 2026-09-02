# Plain (StatefulWidget) × swrly

**Client state**: `String _query` field, mutated via `setState`.
**Server state**: `postsQuery` / `postQuery(id)` via `QueryBuilder.of(...)`.

The one rule from `doc/CONVENTIONS.md` this pattern makes obvious:

> `setState` is fine for local UI state this screen owns. It is not fine
> for shared, cached, invalidatable data — that's server state.

## When to use this

- Prototypes, small apps, or per-screen state that never leaves the screen.
- You don't want another dep and your client state genuinely is trivial.

## When to reach for a state-management library instead

- The same client state (auth user, cart, active filter) is read on many screens.
- You need testing seams that `setState` doesn't give you.

## What swrly does here that `FutureBuilder` wouldn't

- Re-opening the screen doesn't refire the request within `staleTime`.
- Every open of the same post detail id hits the cache once and stays there.
- The FAB's create is optimistic: the row appears instantly and rolls back
  automatically if the server rejects the write.
