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
  });
}
