/// Flutter Hooks bindings for [swrly](https://pub.dev/packages/swrly).
///
/// The `swrly` core package intentionally does not depend on `flutter_hooks`
/// — see the swrly README's "flutter_hooks" section. This companion package
/// provides the canonical `useSwrlyQuery` / `useSwrlyMutation` hooks so
/// projects that already use `flutter_hooks` get correct-by-default
/// subscription lifecycle, key hashing and unhandled-async semantics without
/// hand-rolling them.
///
/// ```dart
/// class PostsPage extends HookWidget {
///   @override
///   Widget build(BuildContext context) {
///     final state = useSwrlyQuery(postsQuery);
///     if (state.isLoading && !state.hasData) return const CircularProgressIndicator();
///     return PostsView(state.data!);
///   }
/// }
/// ```
library;

export 'src/mutation_state.dart';
export 'src/use_swrly_mutation.dart';
export 'src/use_swrly_query.dart';
