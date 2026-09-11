import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swrly/swrly.dart';
import 'package:swrly_hooks/swrly_hooks.dart';

class _StateCapture<T> {
  QueryState<T>? last;
}

Widget _hookHost<T>(Query<T> query, _StateCapture<T> capture) {
  return MaterialApp(
    home: HookBuilder(
      builder: (context) {
        capture.last = useSwrlyQuery(query);
        return const SizedBox.shrink();
      },
    ),
  );
}

/// Short cacheTime so GC fires and drains within pump() cycles rather than
/// leaving a 5-minute timer pending across the invariant check.
const _shortGc = Duration(milliseconds: 5);
QueryClient _testClient() => QueryClient(defaultCacheTime: _shortGc);

/// Unmount + advance beyond the GC window so no cacheTime timer leaks.
Future<void> _cleanup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  group('useSwrlyQuery', () {
    testWidgets('kicks off the initial fetch and emits success', (tester) async {
      final client = _testClient();
      var calls = 0;
      final query = Query<int>(
        key: const ['n'],
        fn: () async {
          calls += 1;
          return 42;
        },
        client: client,
      );
      final capture = _StateCapture<int>();

      await tester.pumpWidget(_hookHost(query, capture));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(capture.last!.data, 42);
      expect(capture.last!.isSuccess, isTrue);

      await _cleanup(tester);
    });

    testWidgets('registers a subscriber so invalidate() refetches',
        (tester) async {
      // Codex P1 case: without onSubscribe/onUnsubscribe hookup, invalidate()
      // would have no active subscriber and the hook would sit on stale data.
      final client = _testClient();
      var calls = 0;
      final query = Query<int>(
        key: const ['n'],
        fn: () async => ++calls,
        client: client,
        staleTime: const Duration(minutes: 5),
      );
      final capture = _StateCapture<int>();

      await tester.pumpWidget(_hookHost(query, capture));
      await tester.pumpAndSettle();
      expect(calls, 1);

      client.invalidateQueries(const ['n']);
      await tester.pumpAndSettle();

      expect(calls, 2, reason: 'invalidate must refetch active hook consumers');
      expect(capture.last!.data, 2);

      await _cleanup(tester);
    });

    testWidgets('unregisters the subscriber on unmount', (tester) async {
      final client = _testClient();
      var calls = 0;
      final query = Query<int>(
        key: const ['n'],
        fn: () async => ++calls,
        client: client,
        staleTime: const Duration(minutes: 5),
      );
      final capture = _StateCapture<int>();

      await tester.pumpWidget(_hookHost(query, capture));
      await tester.pumpAndSettle();
      expect(calls, 1);

      await _cleanup(tester);

      client.invalidateQueries(const ['n']);
      await tester.pump(const Duration(milliseconds: 20));
      expect(calls, 1, reason: 'unmounted hook must not keep refetching');
    });

    testWidgets('canonical key hashing — colliding toString still distinct',
        (tester) async {
      // Codex P2 case: `['a, b']` and `['a', 'b']` both stringify as `[a, b]`.
      // QueryKeyHash serializes with quoting, keeping them distinct.
      final client = _testClient();
      var joinedCalls = 0;
      var splitCalls = 0;

      final joined = Query<int>(
        key: const ['a, b'],
        fn: () async => ++joinedCalls,
        client: client,
      );
      final split = Query<int>(
        key: const ['a', 'b'],
        fn: () async => ++splitCalls,
        client: client,
      );

      final which = ValueNotifier<Query<int>>(joined);
      addTearDown(which.dispose);
      final capture = _StateCapture<int>();

      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              useListenable(which);
              capture.last = useSwrlyQuery(which.value);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(joinedCalls, 1);
      expect(splitCalls, 0);

      which.value = split;
      await tester.pumpAndSettle();

      expect(splitCalls, 1,
          reason: 'canonical key hash must not collide with `[a, b]` peer');

      await _cleanup(tester);
    });
    testWidgets('re-subscribes when the client changes under the same key',
        (tester) async {
      // Regression (2026-09 Codex review on swrly PR #22): the effect's
      // dependency array held only the key hash, so swapping the QueryClient
      // while keeping the key — a scoped DI client changing — left the hook
      // subscribed to the old client. The new client never got fetch(), and
      // invalidation/cleanup stayed wired to a client the widget no longer
      // reads from.
      final clientA = _testClient();
      final clientB = _testClient();
      var callsA = 0;
      var callsB = 0;

      Query<int> queryOn(QueryClient c, void Function() tick) => Query<int>(
            key: const ['same-key'],
            fn: () async {
              tick();
              return 1;
            },
            client: c,
          );

      final capture = _StateCapture<int>();
      await tester.pumpWidget(
        _hookHost(queryOn(clientA, () => callsA += 1), capture),
      );
      await tester.pumpAndSettle();
      expect(callsA, 1, reason: 'initial fetch on client A');
      expect(callsB, 0);

      // Same key, different client.
      await tester.pumpWidget(
        _hookHost(queryOn(clientB, () => callsB += 1), capture),
      );
      await tester.pumpAndSettle();

      expect(callsB, 1, reason: 'the new client must receive its own fetch');

      // The old client must have been released — invalidating it should not
      // drive any further work on behalf of this widget.
      final callsAAtSwap = callsA;
      clientA.invalidateQueries(const ['same-key']);
      await tester.pumpAndSettle();
      expect(callsA, callsAAtSwap,
          reason: 'unsubscribed from client A, so its invalidate is inert');

      await _cleanup(tester);
      clientA.clear();
      clientB.clear();
    });

    testWidgets('holds a polling claim a sibling release cannot cancel',
        (tester) async {
      // Regression (Codex review on PR #24): polling claims are refcounted on
      // the cache entry, but the hook did not participate — it armed the
      // interval via query.fetch() while only QueryBuilders ever called
      // retainInterval. A builder sharing the key going disabled/disposed
      // therefore dropped the count to zero and cancelled the timer out from
      // under this still-mounted hook. See SPEC §11.
      final client = _testClient();
      var calls = 0;
      final query = Query<int>(
        key: const ['hook-poll'],
        fn: () async {
          calls += 1;
          return 1;
        },
        client: client,
        refetchInterval: const Duration(milliseconds: 40),
      );

      final capture = _StateCapture<int>();
      await tester.pumpWidget(_hookHost(query, capture));
      await tester.pump();
      await tester.pump();
      expect(calls, 1, reason: 'initial fetch');

      // A QueryBuilder on the same key claims polling, then goes away
      // (enabled:false or disposed).
      client.retainInterval(const ['hook-poll'], const Duration(milliseconds: 40));
      client.releaseInterval(const ['hook-poll'], const Duration(milliseconds: 40));

      final before = calls;
      // Advance past two tick windows; each tick's async fn needs a pump to
      // deliver, so pump in small steps rather than one long jump.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(calls, greaterThan(before),
          reason: 'the mounted hook still wants polling');

      await _cleanup(tester);
      client.clear();
    });

    testWidgets('re-arms polling when the interval changes', (tester) async {
      // Regression (Codex review on PR #25): the claim effect's cleanup
      // released the last claim — clearing the timer *and* the stored interval
      // — while the re-run only incremented the count. Nothing re-armed, so
      // changing the rate stopped polling at either rate.
      final client = _testClient();
      var calls = 0;
      Query<int> q(Duration? interval) => Query<int>(
            key: const ['rate'],
            fn: () async {
              calls += 1;
              return 1;
            },
            client: client,
            refetchInterval: interval,
          );

      final capture = _StateCapture<int>();
      await tester.pumpWidget(_hookHost(q(const Duration(milliseconds: 40)), capture));
      await tester.pump();
      await tester.pump();
      expect(calls, 1, reason: 'initial fetch');

      // Same key and client, much slower rate. Asserting the *new* rate took
      // effect — not merely that something still polls — is what makes this
      // sensitive: if the old 40ms timer simply kept running, the window below
      // would see several ticks.
      await tester.pumpWidget(
          _hookHost(q(const Duration(seconds: 10)), capture));
      await tester.pump();

      final before = calls;
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(calls, before,
          reason: 'the 10s rate must replace the 40ms one, so no tick lands '
              'in a 320ms window');

      await _cleanup(tester);
      client.clear();
    });

    testWidgets('arms polling when the interval goes null → non-null',
        (tester) async {
      // Same defect, other direction: the subscription effect does not re-run
      // on an interval change, so nothing called fetch() to arm the timer and
      // the new claim only bumped a counter.
      final client = _testClient();
      var calls = 0;
      Query<int> q(Duration? interval) => Query<int>(
            key: const ['rate2'],
            fn: () async {
              calls += 1;
              return 1;
            },
            client: client,
            refetchInterval: interval,
          );

      final capture = _StateCapture<int>();
      await tester.pumpWidget(_hookHost(q(null), capture));
      await tester.pump();
      await tester.pump();
      expect(calls, 1);

      await tester.pumpWidget(_hookHost(q(const Duration(milliseconds: 40)), capture));
      await tester.pump();

      final before = calls;
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(calls, greaterThan(before),
          reason: 'turning polling on must arm the timer');

      await _cleanup(tester);
      client.clear();
    });

  });
}
