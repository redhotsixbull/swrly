---
name: swrly-refactor-stateful
description: Refactor a StatefulWidget that manages server fetch state (`_data`, `_isLoading`, `_error` fields + `initState` fetch + `setState`) to swrly's `QueryBuilder`. Common shape in projects without a state-management library. Use when the user asks to remove boilerplate loading state, convert an initState fetch, or clean up a `_isLoading` bool.
---

# swrly-refactor-stateful

Target the specific antipattern of a `StatefulWidget` that owns
`_data` / `_isLoading` / `_error` fields, fetches in `initState`, and
churns via `setState`. Server state impersonating client state — swrly's
whole point.

## Prerequisites

- `swrly` in `pubspec.yaml`.
- A `Query`/`QueryFamily` folder exists.

## Steps

### 1. Find the pattern

Grep for the tell-tale trio:

```
grep -rn "_isLoading" lib/
grep -rn "initState" lib/
```

Cross-reference: files with both are the candidates.

### 2. Read each candidate and confirm the shape

Look for state that matches this template:

```dart
class _FooState extends State<Foo> {
  Foo? _data;
  bool _isLoading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final r = await api.getFoo(widget.id);
      if (mounted) setState(() { _data = r; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return CircularProgressIndicator();
    if (_error != null) return Text('$_error');
    return FooView(_data!);
  }
}
```

If the class doesn't match that shape reasonably closely (e.g., the
StatefulWidget has substantial client state too — animation controllers,
form controllers, subscriptions), do NOT auto-convert. Ask user to
confirm which parts move to swrly.

### 3. Extract the fetch to a `Query` in `lib/queries/`

Add to the appropriate queries file:

```dart
final fooQuery = QueryFamily<Foo, int>(
  prefix: const ['foo'],
  fn: (id) => api.getFoo(id),
  staleTime: const Duration(seconds: 30),
);
```

### 4. Rewrite the widget

If the widget has NO client state after moving the fetch out, downgrade
to `StatelessWidget`:

```dart
class Foo extends StatelessWidget {
  const Foo({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context) {
    return QueryBuilder.of(
      fooQuery(id),
      builder: (context, state, refetch) {
        if (state.isLoading && !state.hasData) return const CircularProgressIndicator();
        if (state.isError && !state.hasData) return Text('${state.error}');
        return FooView(state.data!);
      },
    );
  }
}
```

If the widget still has genuine client state (animation controllers,
form controllers), keep it StatefulWidget and only replace the
`_data`/`_isLoading`/`_error` trio + `initState` fetch.

Model after [`example/lib/patterns/plain/posts_screen.dart`](../../../example/lib/patterns/plain/posts_screen.dart).

### 5. Handle dispose-time cancellation

If the widget's `dispose` cancels the in-flight request (subscription
cancellation, dio CancelToken), tell the user:

> `swrly` does not yet support request cancellation on subscriber
> departure (see roadmap v0.4). Until then, the in-flight fetch runs to
> completion after the widget unmounts — its result lands in the cache
> and is served to whoever mounts next. If your fetches are expensive
> enough that this matters, hold off on converting this specific widget.

### 6. Do NOT

- Do NOT wrap `Query(...)` inline inside the widget — put it in `lib/queries/`.
- Do NOT lose the `if (mounted)` semantics silently — the whole point is that swrly's QueryBuilder handles this for you, but say so.
- Do NOT batch-convert. One widget per diff.

## Reference

- `doc/CONVENTIONS.md` — the ruleset the diff follows.
- `example/lib/patterns/plain/` — target shape.
