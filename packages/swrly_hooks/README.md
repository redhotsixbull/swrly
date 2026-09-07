# swrly_hooks

<p align="center">
  <a href="https://pub.dev/packages/swrly_hooks"><img src="https://img.shields.io/pub/v/swrly_hooks.svg" alt="pub package"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="license: MIT"></a>
</p>

**Flutter Hooks bindings for [swrly](https://pub.dev/packages/swrly).**
`useSwrlyQuery` + `useSwrlyMutation` for consuming a swrly cache from
`HookWidget`-based screens — with correct subscriber lifecycle, canonical
key hashing and proper unhandled-async handling out of the box.

## Why is this a separate package?

The core `swrly` package intentionally does not depend on `flutter_hooks`
— users who don't reach for hooks shouldn't pay for the dep. This
companion package (mirroring the `flutter_riverpod` / `hooks_riverpod`
split) is the officially supported path when you do use hooks.

Rolling your own `useSwrlyQuery` off `Query.stream` looks like a
one-liner but has three subtleties that regularly bite:

- `useStream(query.stream)` does NOT register a swrly subscriber — so
  `invalidate()` will not refetch and the entry may `cacheTime`-GC while
  your widget is still mounted.
- `query.fetch()` returns a Future — discarding it makes the terminal
  retry failure an unhandled async error, even though the emitted
  `QueryState.error` renders fine.
- `query.key.toString()` collides across distinct keys (`['a, b']` vs
  `['a', 'b']` both stringify as `[a, b]`), so an effect keyed on that
  string can silently stop refetching on key changes.

`swrly_hooks` handles all three.

## Install

```bash
flutter pub add swrly swrly_hooks
```

## Use

```dart
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:swrly/swrly.dart';
import 'package:swrly_hooks/swrly_hooks.dart';

final postsQuery = Query<List<Post>>(
  key: const ['posts'],
  fn: () => api.getPosts(),
  staleTime: const Duration(seconds: 30),
);

class PostsPage extends HookWidget {
  const PostsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = useSwrlyQuery(postsQuery);
    if (state.isLoading && !state.hasData) {
      return const CircularProgressIndicator();
    }
    if (state.isError && !state.hasData) {
      return Text('${state.error}');
    }
    return PostsView(state.data!);
  }
}
```

For mutations:

```dart
class CreatePostButton extends HookWidget {
  const CreatePostButton({super.key});

  @override
  Widget build(BuildContext context) {
    final mut = useSwrlyMutation<Post, String>(api.createPost);
    return FilledButton(
      onPressed: mut.state.isLoading
          ? null
          : () async {
              await mut.mutate('Hello');
              postsQuery.invalidate();
            },
      child: Text(mut.state.isLoading ? 'Saving…' : 'Save'),
    );
  }
}
```

For optimistic writes with automatic rollback (`onMutate` returning a
rollback closure, `onSuccess`/`onSettled` callbacks that fire regardless
of mount state), prefer swrly's built-in `MutationBuilder` — this hook
is intentionally minimal.

## License

MIT
