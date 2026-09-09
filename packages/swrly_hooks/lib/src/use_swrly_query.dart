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
///
/// The resolved [QueryClient] is a dependency alongside the key hash. Swapping
/// the client while keeping the same key — a scoped DI client changing, say —
/// otherwise leaves the effect subscribed to the *old* client: the new one
/// never gets `fetch()`, and invalidation and cleanup stay wired to a client
/// the widget no longer reads from.
QueryState<T> useSwrlyQuery<T>(Query<T> query) {
  final client = query.client ?? QueryClient.instance;
  useEffect(() {
    client.onSubscribe<T>(query.key);
    query.fetch().ignore();
    return () => client.onUnsubscribe<T>(query.key);
  }, [QueryKeyHash.of(query.key).value, client]);
  // Polling claims are refcounted on the cache entry (SPEC §11): the interval
  // is torn down when the last claimant lets go. A hook on a polling `Query`
  // arms that interval through `fetch()`, so it must claim it too — otherwise a
  // `QueryBuilder` sharing the key going `enabled: false` drops the count to
  // zero and cancels the timer out from under this still-mounted hook.
  //
  // Kept as its own effect, keyed on the interval as well: changing the rate
  // must re-balance the claim without forcing the unsubscribe/resubscribe (and
  // its extra fetch) that folding it into the effect above would cause.
  final refetchInterval = query.refetchInterval;
  useEffect(() {
    if (refetchInterval == null) return null;
    client.retainInterval(query.key, refetchInterval);
    return () => client.releaseInterval(query.key, refetchInterval);
  }, [QueryKeyHash.of(query.key).value, client, refetchInterval]);
  final snapshot = useStream<QueryState<T>>(
    query.stream,
    initialData: query.state,
  );
  return snapshot.data ?? query.state;
}
