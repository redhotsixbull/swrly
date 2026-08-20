import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:swrly/swrly.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QueryKeyHash', () {
    test('equal keys hash equal, order-independent maps', () {
      expect(QueryKeyHash.of(['a', 1]), QueryKeyHash.of(['a', 1]));
      expect(
        QueryKeyHash.of([
          {'x': 1, 'y': 2}
        ]),
        QueryKeyHash.of([
          {'y': 2, 'x': 1}
        ]),
        reason: 'map key order must not affect the hash',
      );
    });

    test('different keys hash differently', () {
      expect(QueryKeyHash.of(['a', 1]) == QueryKeyHash.of(['a', 2]), isFalse);
      expect(QueryKeyHash.of(['a']) == QueryKeyHash.of(['a', 1]), isFalse);
    });

    test('queryKeyStartsWith matches prefixes only', () {
      expect(queryKeyStartsWith(['user', 1, 'posts'], ['user']), isTrue);
      expect(queryKeyStartsWith(['user', 1], ['user', 1]), isTrue);
      expect(queryKeyStartsWith(['user', 1], ['user', 2]), isFalse);
      expect(queryKeyStartsWith(['user'], ['user', 1]), isFalse,
          reason: 'prefix longer than key never matches');
    });
  });

  group('QueryClient.fetchQuery', () {
    test('returns data and caches it while fresh', () async {
      final client = QueryClient();
      var calls = 0;
      Future<int> fn() async {
        calls += 1;
        return 42;
      }

      final a = await client.fetchQuery<int>(
          key: ['n'], fn: fn, staleTime: const Duration(seconds: 1));
      final b = await client.fetchQuery<int>(
          key: ['n'], fn: fn, staleTime: const Duration(seconds: 1));

      expect(a, 42);
      expect(b, 42);
      expect(calls, 1, reason: 'fresh cache should not refetch');
    });

    test('refetches once data is stale', () async {
      final client = QueryClient();
      var calls = 0;
      Future<int> fn() async => ++calls;

      await client.fetchQuery<int>(key: ['n'], fn: fn, staleTime: Duration.zero);
      await client.fetchQuery<int>(key: ['n'], fn: fn, staleTime: Duration.zero);
      expect(calls, 2, reason: 'staleTime zero always refetches');
    });

    test('deduplicates concurrent in-flight requests', () async {
      final client = QueryClient();
      var calls = 0;
      Future<int> slow() async {
        calls += 1;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return 5;
      }

      final results = await Future.wait([
        client.fetchQuery<int>(key: ['x'], fn: slow),
        client.fetchQuery<int>(key: ['x'], fn: slow),
        client.fetchQuery<int>(key: ['x'], fn: slow),
      ]);

      expect(results, [5, 5, 5]);
      expect(calls, 1, reason: 'concurrent calls share one request');
    });

    test('treats a successful null value as fresh (nullable data)', () async {
      final client = QueryClient();
      var calls = 0;
      Future<int?> fn() async {
        calls += 1;
        return null;
      }

      final a = await client.fetchQuery<int?>(
          key: ['z'], fn: fn, staleTime: const Duration(seconds: 1));
      final b = await client.fetchQuery<int?>(
          key: ['z'], fn: fn, staleTime: const Duration(seconds: 1));

      expect(a, isNull);
      expect(b, isNull);
      expect(calls, 1, reason: 'null is a valid fresh value, must not refetch');
    });

    test('error is surfaced but stale data is retained', () async {
      final client = QueryClient();
      client.setQueryData<int>(['e'], 1);
      await expectLater(
        client.fetchQuery<int>(
          key: ['e'],
          fn: () async => throw StateError('boom'),
          staleTime: Duration.zero,
        ),
        throwsA(isA<StateError>()),
      );
      expect(client.stateOf<int>(['e']).isError, isTrue);
      expect(client.stateOf<int>(['e']).data, 1, reason: 'keep last good data');
    });
  });

  group('QueryClient concurrency', () {
    test('a stale response cannot overwrite fresher setQueryData', () async {
      final client = QueryClient();
      final gate = Completer<int>();
      final f = client.fetchQuery<int>(
        key: ['r'],
        fn: () => gate.future,
        staleTime: Duration.zero,
      );

      // While the fetch is in flight, write newer data imperatively.
      client.setQueryData<int>(['r'], 99);
      // Now let the older request resolve.
      gate.complete(1);
      await f;
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(client.getQueryData<int>(['r']), 99,
          reason: 'generation guard drops the superseded response');
    });
  });

  group('QueryClient.invalidateQueries', () {
    test('without subscribers marks stale so the next fetch refetches',
        () async {
      final client = QueryClient();
      var calls = 0;
      Future<int> fn() async => ++calls;

      await client.fetchQuery<int>(
          key: ['user', 1], fn: fn, staleTime: const Duration(minutes: 5));
      client.invalidateQueries(['user']);
      final result = await client.fetchQuery<int>(
          key: ['user', 1], fn: fn, staleTime: const Duration(minutes: 5));

      expect(result, 2);
      expect(calls, 2);
    });

    test('actively refetches entries that have subscribers', () async {
      final client = QueryClient();
      var calls = 0;
      Future<int> fn() async => ++calls;

      client.onSubscribe<int>(['user', 1]);
      await client.fetchQuery<int>(
          key: ['user', 1], fn: fn, staleTime: const Duration(minutes: 5));
      expect(calls, 1);

      client.invalidateQueries(['user']); // subscriber present → refetch now
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(calls, 2, reason: 'active subscriber is refetched immediately');
      expect(client.getQueryData<int>(['user', 1]), 2);
      client.onUnsubscribe<int>(['user', 1]);
    });

    test('refetch:false only marks stale, never refetches', () async {
      final client = QueryClient();
      var calls = 0;
      Future<int> fn() async => ++calls;
      client.onSubscribe<int>(['k']);
      await client.fetchQuery<int>(
          key: ['k'], fn: fn, staleTime: const Duration(minutes: 5));
      client.invalidateQueries(['k'], refetch: false);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(calls, 1);
      client.onUnsubscribe<int>(['k']);
    });
  });

  group('QueryClient.setQueryData / getQueryData', () {
    test('writes without going through the fn', () {
      final client = QueryClient();
      client.setQueryData<int>(['n'], 99);
      expect(client.getQueryData<int>(['n']), 99);
    });

    test('getQueryData returns null for unknown keys', () {
      final client = QueryClient();
      expect(client.getQueryData<int>(['missing']), isNull);
    });
  });

  group('QueryClient garbage collection', () {
    test('disposes an entry after the last subscriber leaves', () async {
      final client =
          QueryClient(defaultCacheTime: const Duration(milliseconds: 20));
      client.onSubscribe<int>(['g']);
      await client.fetchQuery<int>(key: ['g'], fn: () async => 1);
      expect(client.entryCount, 1);

      client.onUnsubscribe<int>(['g']);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(client.entryCount, 0, reason: 'GC after cacheTime');
    });

    test('imperative reuse cancels a pending GC (no disposal-during-use)',
        () async {
      final client =
          QueryClient(defaultCacheTime: const Duration(milliseconds: 40));
      client.onSubscribe<int>(['g']);
      await client.fetchQuery<int>(key: ['g'], fn: () async => 1);
      client.onUnsubscribe<int>(['g']); // GC armed (~40ms)

      await Future<void>.delayed(const Duration(milliseconds: 15));
      client.setQueryData<int>(['g'], 2); // access cancels + re-arms GC
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(client.getQueryData<int>(['g']), 2,
          reason: 'entry survived the original GC window');

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(client.entryCount, 0, reason: 'eventually GCs after re-arm');
    });

    test('clear and removeQueries dispose entries', () async {
      final client = QueryClient();
      await client.fetchQuery<int>(key: ['a', 1], fn: () async => 1);
      await client.fetchQuery<int>(key: ['a', 2], fn: () async => 2);
      await client.fetchQuery<int>(key: ['b'], fn: () async => 3);
      expect(client.entryCount, 3);

      client.removeQueries(['a']);
      expect(client.entryCount, 1);

      client.clear();
      expect(client.entryCount, 0);
    });
  });

  group('QueryBuilder', () {
    testWidgets('emits loading then success', (tester) async {
      final client = QueryClient();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: QueryBuilder<int>(
            client: client,
            queryKey: const ['n'],
            queryFn: () async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              return 7;
            },
            builder: (context, state, refetch) {
              if (state.isLoading) return const Text('loading');
              if (state.isSuccess) return Text('data=${state.data}');
              return const Text('idle');
            },
          ),
        ),
      );

      expect(find.text('loading'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('data=7'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      client.clear();
    });

    testWidgets('flipping enabled false → true kicks off the fetch',
        (tester) async {
      final client = QueryClient();
      var calls = 0;
      Widget build(bool enabled) => Directionality(
            textDirection: TextDirection.ltr,
            child: QueryBuilder<int>(
              client: client,
              enabled: enabled,
              queryKey: const ['e'],
              queryFn: () async {
                calls += 1;
                return 1;
              },
              builder: (context, state, refetch) =>
                  Text(state.hasData ? 'data' : 'no-data'),
            ),
          );

      await tester.pumpWidget(build(false));
      await tester.pump();
      expect(calls, 0, reason: 'disabled query does not fetch');

      await tester.pumpWidget(build(true));
      await tester.pumpAndSettle();
      expect(calls, 1, reason: 'enabling triggers the fetch');
      expect(find.text('data'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      client.clear();
    });
  });

  group('MutationBuilder', () {
    testWidgets('success path calls onSuccess and exposes data',
        (tester) async {
      int? successData;
      late Future<int?> Function(int) trigger;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MutationBuilder<int, int>(
            mutationFn: (v) async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              return v * 2;
            },
            onSuccess: (data, _) => successData = data,
            builder: (context, mutate, state) {
              trigger = mutate;
              if (state.isLoading) return const Text('saving');
              if (state.isSuccess) return Text('ok=${state.data}');
              return const Text('idle');
            },
          ),
        ),
      );

      expect(find.text('idle'), findsOneWidget);
      final future = trigger(21);
      await tester.pump();
      expect(find.text('saving'), findsOneWidget);
      await tester.pumpAndSettle();
      await future;

      expect(find.text('ok=42'), findsOneWidget);
      expect(successData, 42);
    });

    testWidgets('error path calls onError and exposes the error',
        (tester) async {
      Object? capturedError;
      late Future<int?> Function(int) trigger;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MutationBuilder<int, int>(
            mutationFn: (v) async => throw StateError('nope'),
            onError: (e, _, __) => capturedError = e,
            builder: (context, mutate, state) {
              trigger = mutate;
              if (state.isError) return const Text('failed');
              return const Text('idle');
            },
          ),
        ),
      );

      await trigger(1);
      await tester.pumpAndSettle();
      expect(find.text('failed'), findsOneWidget);
      expect(capturedError, isA<StateError>());
    });
  });
}
