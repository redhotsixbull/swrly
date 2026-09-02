import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:swrly/swrly.dart';

/// Subscribe a [HookWidget] to a swrly [Query] and rebuild on every state
/// change.
///
/// Registers the widget as a real swrly subscriber on mount and unregisters
/// on unmount — so:
///
/// - `query.invalidate()` and `QueryClient.invalidateQueries(prefix)` fire a
///   refetch while this widget is on screen (a plain `useStream` listener
///   would NOT count as a subscriber).
/// - The entry's `cacheTime` GC timer is disarmed until the last hook
///   consumer unmounts.
///
/// The initial fetch is kicked off in `useEffect`; the returned Future is
/// deliberately `.ignore()`d because the error surfaces through the emitted
/// [QueryState] regardless — leaving it unhandled would trip Dart's zone
/// error handler on the terminal retry failure.
///
/// The effect's dependency array uses [QueryKeyHash.of] (not
/// `key.toString()`) so distinct keys with identical stringification —
/// e.g. `['a, b']` vs `['a', 'b']`, both `[a, b]` under `toString` —
/// don't collide.
QueryState<T> useSwrlyQuery<T>(Query<T> query) {
  final client = query.client ?? QueryClient.instance;
  useEffect(() {
    client.onSubscribe<T>(query.key);
    query.fetch().ignore();
    return () => client.onUnsubscribe<T>(query.key);
  }, [QueryKeyHash.of(query.key).value]);
  final snapshot = useStream<QueryState<T>>(
    query.stream,
    initialData: query.state,
  );
  return snapshot.data ?? query.state;
}
