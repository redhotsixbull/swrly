import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:swrly/swrly.dart';
import 'package:flutter_test/flutter_test.dart';

class _Custom {
  _Custom(this.n);
  final int n;
  @override
  String toString() => 'Custom($n)';
}

Future<int> _identityFetch(int id) async => id;

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

    test('observe() on an unsubscribed key does not disarm GC', () async {
      final client =
          QueryClient(defaultCacheTime: const Duration(milliseconds: 20));
      client.onSubscribe<int>(['g']);
      await client.fetchQuery<int>(key: ['g'], fn: () async => 1);
      client.onUnsubscribe<int>(['g']);

      // Touching the entry cancels the pending GC; observe must re-arm it or
      // the entry stays resident forever.
      client.observe<int>(['g']).listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(client.entryCount, 0, reason: 'observe re-arms GC');
    });

    test('stateOf() on an unknown key does not leak the entry it creates',
        () async {
      final client =
          QueryClient(defaultCacheTime: const Duration(milliseconds: 20));
      expect(client.stateOf<int>(['nope']).isIdle, isTrue);
      expect(client.entryCount, 1, reason: 'the read created an idle entry');

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(client.entryCount, 0, reason: 'stateOf re-arms GC');
    });

    test('observe/stateOf never GC an entry that has subscribers', () async {
      final client =
          QueryClient(defaultCacheTime: const Duration(milliseconds: 20));
      client.onSubscribe<int>(['g']);
      await client.fetchQuery<int>(key: ['g'], fn: () async => 1);

      client.observe<int>(['g']).listen((_) {});
      client.stateOf<int>(['g']);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(client.entryCount, 1, reason: 'a live subscriber holds the entry');
      client.onUnsubscribe<int>(['g']);
      client.clear();
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

    testWidgets('runs onSuccess/onSettled even if unmounted mid-flight',
        (tester) async {
      var onSuccessCalls = 0;
      var onSettledCalls = 0;
      late Future<int?> Function(int) trigger;
      final gate = Completer<int>();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MutationBuilder<int, int>(
            mutationFn: (v) => gate.future,
            onSuccess: (_, __) => onSuccessCalls += 1,
            onSettled: (_) => onSettledCalls += 1,
            builder: (context, mutate, state) {
              trigger = mutate;
              return const Text('idle');
            },
          ),
        ),
      );

      final future = trigger(1);
      await tester.pump(); // loading setState while still mounted
      await tester.pumpWidget(const SizedBox()); // unmount mid-flight
      gate.complete(42); // now let the mutation resolve
      await future;

      expect(onSuccessCalls, 1,
          reason: 'onSuccess must fire even though the widget disposed');
      expect(onSettledCalls, 1,
          reason: 'onSettled must always fire');
    });
  });

  group('0.1.1 correctness fixes', () {
    testWidgets('QueryBuilder<int?> with a null value reports hasData',
        (tester) async {
      final client = QueryClient();
      late QueryState<int?> observed;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: QueryBuilder<int?>(
            client: client,
            queryKey: const ['maybe'],
            queryFn: () async => null,
            builder: (context, state, refetch) {
              observed = state;
              return Text('has=${state.hasData}');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(observed.isSuccess, isTrue);
      expect(observed.hasData, isTrue,
          reason: 'a successful null value still has data (SPEC §2)');
      expect(observed.data, isNull);

      await tester.pumpWidget(const SizedBox());
      client.clear();
    });

    test('a successful refetch after an error clears error/stackTrace',
        () async {
      final client = QueryClient();
      var calls = 0;
      Future<int> fn() async {
        calls += 1;
        if (calls == 1) throw StateError('boom');
        return 7;
      }

      await expectLater(
        client.fetchQuery<int>(key: ['q'], fn: fn, staleTime: Duration.zero),
        throwsA(isA<StateError>()),
      );
      expect(client.stateOf<int>(['q']).isError, isTrue);
      expect(client.stateOf<int>(['q']).error, isA<StateError>());

      final result =
          await client.fetchQuery<int>(key: ['q'], fn: fn, staleTime: Duration.zero);
      expect(result, 7);
      final state = client.stateOf<int>(['q']);
      expect(state.isSuccess, isTrue);
      expect(state.error, isNull, reason: 'stale error must be cleared');
      expect(state.stackTrace, isNull, reason: 'stale stackTrace must be cleared');
    });

    test('invalidation refetch uses the most recently captured queryFn',
        () async {
      final client = QueryClient();
      client.onSubscribe<int>(['shared']);

      await client.fetchQuery<int>(
          key: ['shared'], fn: () async => 1, staleTime: const Duration(minutes: 5));
      // Second subscriber captures a different fn on the same key while data is
      // still fresh (no refetch happens here, but the refetcher is updated).
      await client.fetchQuery<int>(
          key: ['shared'], fn: () async => 2, staleTime: const Duration(minutes: 5));
      expect(client.getQueryData<int>(['shared']), 1);

      client.invalidateQueries(['shared']);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(client.getQueryData<int>(['shared']), 2,
          reason: 'last-writer-wins: invalidation runs the latest queryFn');
      client.onUnsubscribe<int>(['shared']);
    });

    testWidgets(
        'rebuild with a new queryFn re-primes invalidation without refetching',
        (tester) async {
      final client = QueryClient();
      var fn1Calls = 0;
      var fn2Calls = 0;
      Widget build(int which) => Directionality(
            textDirection: TextDirection.ltr,
            child: QueryBuilder<int>(
              client: client,
              queryKey: const ['p'],
              staleTime: const Duration(minutes: 5),
              queryFn: which == 1
                  ? () async {
                      fn1Calls += 1;
                      return 1;
                    }
                  : () async {
                      fn2Calls += 1;
                      return 2;
                    },
              builder: (context, state, refetch) => Text('data=${state.data}'),
            ),
          );

      await tester.pumpWidget(build(1));
      await tester.pumpAndSettle();
      expect(fn1Calls, 1);
      expect(find.text('data=1'), findsOneWidget);

      // Rebuild with a different fn on the same fresh key: must NOT refetch.
      await tester.pumpWidget(build(2));
      await tester.pumpAndSettle();
      expect(fn2Calls, 0, reason: 'a plain rebuild must not refetch');
      expect(find.text('data=1'), findsOneWidget);

      // Invalidation now runs the re-primed (latest) queryFn.
      client.invalidateQueries(['p']);
      await tester.pumpAndSettle();
      expect(fn2Calls, 1, reason: 'invalidate refetches with the current fn');
      expect(find.text('data=2'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      client.clear();
    });

    test('invalidateQueriesWhere invalidates only entries matching the predicate',
        () async {
      final client = QueryClient();
      var post1Calls = 0;
      var post2Calls = 0;
      Future<int> post1() async => ++post1Calls;
      Future<int> post2() async => ++post2Calls;
      const stale = Duration(minutes: 5);

      await client.fetchQuery<int>(key: ['post', 1], fn: post1, staleTime: stale);
      await client.fetchQuery<int>(key: ['post', 2], fn: post2, staleTime: stale);
      expect(post1Calls, 1);
      expect(post2Calls, 1);

      client.invalidateQueriesWhere(
          (key) => key.length == 2 && key[0] == 'post' && key[1] == 1);

      await client.fetchQuery<int>(key: ['post', 1], fn: post1, staleTime: stale);
      await client.fetchQuery<int>(key: ['post', 2], fn: post2, staleTime: stale);

      expect(post1Calls, 2, reason: 'matched entry was invalidated → refetched');
      expect(post2Calls, 1, reason: 'unmatched entry stayed fresh');
    });

    testWidgets(
        'a disabled query is never fetched by invalidateQueries, even after a rebuild',
        (tester) async {
      final client = QueryClient();
      var calls = 0;
      Widget build(String label) => Directionality(
            textDirection: TextDirection.ltr,
            child: QueryBuilder<int>(
              client: client,
              enabled: false,
              queryKey: const ['d'],
              queryFn: () async {
                calls += 1;
                return 1;
              },
              builder: (context, state, refetch) => Text('label=$label'),
            ),
          );

      await tester.pumpWidget(build('a'));
      await tester.pump();
      expect(calls, 0, reason: 'disabled query does not fetch on mount');

      // A parent-driven rebuild while still disabled must not install a
      // refetcher (regression guard for SPEC §9).
      await tester.pumpWidget(build('b'));
      await tester.pump();

      client.invalidateQueries(['d']);
      await tester.pumpAndSettle();
      expect(calls, 0,
          reason: 'invalidateQueries must not fetch a disabled query');

      await tester.pumpWidget(const SizedBox());
      client.clear();
    });

    testWidgets('MutationBuilder runs onError/onSettled even if unmounted',
        (tester) async {
      var onErrorCalls = 0;
      var onSettledCalls = 0;
      late Future<int?> Function(int) trigger;
      final gate = Completer<int>();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MutationBuilder<int, int>(
            mutationFn: (v) => gate.future,
            onError: (_, __, ___) => onErrorCalls += 1,
            onSettled: (_) => onSettledCalls += 1,
            builder: (context, mutate, state) {
              trigger = mutate;
              return const Text('idle');
            },
          ),
        ),
      );

      final future = trigger(1);
      await tester.pump();
      await tester.pumpWidget(const SizedBox()); // unmount mid-flight
      gate.completeError(StateError('boom')); // resolve as error
      await future;

      expect(onErrorCalls, 1,
          reason: 'onError must fire on the error path even when disposed');
      expect(onSettledCalls, 1, reason: 'onSettled must always fire');
    });

    test('hasData is retained across an error transition', () async {
      final client = QueryClient();
      client.setQueryData<int>(['h'], 5); // success → hasData true
      await expectLater(
        client.fetchQuery<int>(
            key: ['h'],
            fn: () async => throw StateError('x'),
            staleTime: Duration.zero),
        throwsA(isA<StateError>()),
      );
      final s = client.stateOf<int>(['h']);
      expect(s.isError, isTrue);
      expect(s.hasData, isTrue, reason: 'last-good data survives an error');
      expect(s.data, 5);
    });

    test('copyWith clears data/error/stackTrace when passed null', () {
      const start = QueryState<int>(
        status: QueryStatus.error,
        data: 7,
        hasData: true,
        error: 'boom',
      );
      final cleared = start.copyWith(
        status: QueryStatus.success,
        data: null,
        hasData: false,
        error: null,
        stackTrace: null,
      );
      expect(cleared.data, isNull, reason: 'explicit null clears data');
      expect(cleared.error, isNull, reason: 'explicit null clears error');
      expect(cleared.stackTrace, isNull);
      expect(cleared.hasData, isFalse);

      // Omitting a field must preserve it (sentinel, not null).
      final kept = start.copyWith(isFetching: true);
      expect(kept.data, 7, reason: 'omitted data is preserved');
      expect(kept.error, 'boom', reason: 'omitted error is preserved');
    });
  });

  group('retry + backoff (0.2.0)', () {
    test('retries N times then surfaces the error', () async {
      final client = QueryClient();
      var calls = 0;
      await expectLater(
        client.fetchQuery<int>(
          key: ['r'],
          fn: () async {
            calls += 1;
            throw StateError('boom');
          },
          retry: 2,
          retryDelay: (_) => Duration.zero,
        ),
        throwsA(isA<StateError>()),
      );
      expect(calls, 3, reason: '1 initial attempt + 2 retries');
      expect(client.stateOf<int>(['r']).isError, isTrue);
    });

    test('succeeds on a later attempt without surfacing an error', () async {
      final client = QueryClient();
      var calls = 0;
      final result = await client.fetchQuery<int>(
        key: ['r'],
        fn: () async {
          calls += 1;
          if (calls < 3) throw StateError('transient');
          return 42;
        },
        retry: 5,
        retryDelay: (_) => Duration.zero,
      );
      expect(result, 42);
      expect(calls, 3);
      final s = client.stateOf<int>(['r']);
      expect(s.isSuccess, isTrue);
      expect(s.error, isNull, reason: 'a recovered retry surfaces no error');
      expect(s.data, 42);
    });

    test('retryDelay receives 1-based attempt numbers', () async {
      final client = QueryClient();
      final attempts = <int>[];
      await expectLater(
        client.fetchQuery<int>(
          key: ['r'],
          fn: () async => throw StateError('x'),
          retry: 3,
          retryDelay: (n) {
            attempts.add(n);
            return Duration.zero;
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(attempts, [1, 2, 3]);
    });

    test('defaultRetryDelayFn is exponential, capped at 30s', () {
      expect(defaultRetryDelayFn(1), const Duration(seconds: 1));
      expect(defaultRetryDelayFn(2), const Duration(seconds: 2));
      expect(defaultRetryDelayFn(3), const Duration(seconds: 4));
      expect(defaultRetryDelayFn(20), const Duration(seconds: 30));
    });

    test('client defaultRetry applies when per-query retry is omitted',
        () async {
      final client = QueryClient(
        defaultRetry: 2,
        defaultRetryDelay: (_) => Duration.zero,
      );
      var calls = 0;
      await expectLater(
        client.fetchQuery<int>(
          key: ['r'],
          fn: () async {
            calls += 1;
            throw StateError('x');
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(calls, 3, reason: 'client default of 2 retries → 3 attempts');
    });

    test('a supersede during the retry backoff stops further attempts',
        () async {
      final client = QueryClient();
      var calls = 0;
      final f = client.fetchQuery<int>(
        key: ['r'],
        fn: () async {
          calls += 1;
          throw StateError('x');
        },
        retry: 5,
        retryDelay: (_) => const Duration(milliseconds: 30),
      );
      // Let the first attempt fail and enter the 30ms backoff…
      await Future<void>.delayed(const Duration(milliseconds: 5));
      // …then supersede with an optimistic write.
      client.setQueryData<int>(['r'], 99);
      await f.catchError((_) => 0); // superseded fetch rethrows its last error
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(calls, 1, reason: 'no further attempts after supersede');
      expect(client.stateOf<int>(['r']).isSuccess, isTrue);
      expect(client.getQueryData<int>(['r']), 99,
          reason: 'the optimistic value survives, no error clobbers it');
    });
  });

  group('optimistic + rollback (0.2.0)', () {
    testWidgets('onMutate optimistic write is rolled back on error',
        (tester) async {
      final client = QueryClient();
      client.setQueryData<int>(['count'], 10);
      late Future<int?> Function(int) trigger;
      Object? capturedError;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MutationBuilder<int, int>(
            mutationFn: (delta) async {
              await Future<void>.delayed(const Duration(milliseconds: 5));
              throw StateError('server rejected');
            },
            onMutate: (delta) {
              final prev = client.getQueryData<int>(['count']);
              client.setQueryData<int>(['count'], (prev ?? 0) + delta);
              return () => client.setQueryData<int>(['count'], prev as int);
            },
            onError: (e, _, __) => capturedError = e,
            builder: (context, mutate, state) {
              trigger = mutate;
              return const Text('x');
            },
          ),
        ),
      );

      expect(client.getQueryData<int>(['count']), 10);
      final future = trigger(5);
      await tester.pump();
      expect(client.getQueryData<int>(['count']), 15,
          reason: 'optimistic update applied before the mutationFn resolves');

      await tester.pumpAndSettle();
      await future;
      expect(client.getQueryData<int>(['count']), 10,
          reason: 'rollback restores the previous value on error');
      expect(capturedError, isA<StateError>());
      client.clear();
    });

    testWidgets('onMutate optimistic write is kept on success (no rollback)',
        (tester) async {
      final client = QueryClient();
      client.setQueryData<int>(['count'], 10);
      late Future<int?> Function(int) trigger;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MutationBuilder<int, int>(
            mutationFn: (delta) async => delta,
            onMutate: (delta) {
              final prev = client.getQueryData<int>(['count']);
              client.setQueryData<int>(['count'], (prev ?? 0) + delta);
              return () => client.setQueryData<int>(['count'], prev as int);
            },
            builder: (context, mutate, state) {
              trigger = mutate;
              return const Text('x');
            },
          ),
        ),
      );

      await trigger(5);
      await tester.pumpAndSettle();
      expect(client.getQueryData<int>(['count']), 15,
          reason: 'a successful mutation keeps the optimistic value');
      client.clear();
    });
  });

  group('keepPreviousData / placeholderData (0.2.0)', () {
    testWidgets('keepPreviousData shows the previous key while the new loads',
        (tester) async {
      final client = QueryClient();
      final gateB = Completer<String>();
      Widget build(QueryKey key, Future<String> Function() fn) => Directionality(
            textDirection: TextDirection.ltr,
            child: QueryBuilder<String>(
              client: client,
              queryKey: key,
              queryFn: fn,
              keepPreviousData: true,
              staleTime: const Duration(minutes: 5),
              builder: (context, state, refetch) =>
                  Text('${state.data}|${state.isPlaceholderData}'),
            ),
          );

      await tester.pumpWidget(build(const ['k', 'a'], () async => 'A'));
      await tester.pumpAndSettle();
      expect(find.text('A|false'), findsOneWidget);

      // Switch to a slow key B: the previous data stays, flagged placeholder.
      await tester.pumpWidget(build(const ['k', 'b'], () => gateB.future));
      await tester.pump();
      expect(find.text('A|true'), findsOneWidget,
          reason: 'previous key data shown as placeholder while B loads');

      gateB.complete('B');
      await tester.pumpAndSettle();
      expect(find.text('B|false'), findsOneWidget,
          reason: 'real data replaces the placeholder');

      await tester.pumpWidget(const SizedBox());
      client.clear();
    });

    testWidgets('without keepPreviousData, a key change drops the data',
        (tester) async {
      final client = QueryClient();
      final gateB = Completer<String>();
      Widget build(QueryKey key, Future<String> Function() fn) => Directionality(
            textDirection: TextDirection.ltr,
            child: QueryBuilder<String>(
              client: client,
              queryKey: key,
              queryFn: fn,
              staleTime: const Duration(minutes: 5),
              builder: (context, state, refetch) =>
                  Text('${state.data}|${state.isPlaceholderData}'),
            ),
          );

      await tester.pumpWidget(build(const ['k', 'a'], () async => 'A'));
      await tester.pumpAndSettle();
      expect(find.text('A|false'), findsOneWidget);

      await tester.pumpWidget(build(const ['k', 'b'], () => gateB.future));
      await tester.pump();
      expect(find.text('null|false'), findsOneWidget,
          reason: 'no previous data retained without keepPreviousData');

      gateB.complete('B');
      await tester.pumpAndSettle();
      expect(find.text('B|false'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      client.clear();
    });

    testWidgets('placeholderData is shown until real data arrives',
        (tester) async {
      final client = QueryClient();
      final gate = Completer<String>();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: QueryBuilder<String>(
            client: client,
            queryKey: const ['p'],
            queryFn: () => gate.future,
            placeholderData: 'placeholder',
            builder: (context, state, refetch) =>
                Text('${state.data}|${state.isPlaceholderData}'),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('placeholder|true'), findsOneWidget);

      gate.complete('real');
      await tester.pumpAndSettle();
      expect(find.text('real|false'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      client.clear();
    });
  });

  group('QueryBuilder refetch / lifecycle', () {
    testWidgets('the builder refetch() callback forces a fetch past staleTime',
        (tester) async {
      final client = QueryClient();
      var calls = 0;
      late Future<void> Function() doRefetch;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: QueryBuilder<int>(
            client: client,
            queryKey: const ['rf'],
            staleTime: const Duration(minutes: 5),
            queryFn: () async => ++calls,
            builder: (c, s, refetch) {
              doRefetch = refetch;
              return Text('n=${s.data}');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);

      await doRefetch();
      await tester.pumpAndSettle();
      expect(calls, 2, reason: 'refetch() ignores staleTime');

      await tester.pumpWidget(const SizedBox());
      client.clear();
    });

    testWidgets('refetchOnResume refetches on AppLifecycleState.resumed',
        (tester) async {
      final client = QueryClient();
      var calls = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: QueryBuilder<int>(
            client: client,
            queryKey: const ['rs'],
            staleTime: const Duration(minutes: 5),
            queryFn: () async => ++calls,
            builder: (c, s, refetch) => Text('n=${s.data}'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls, 2, reason: 'app resume forces a refetch');

      await tester.pumpWidget(const SizedBox());
      client.clear();
    });
  });

  group('misc coverage', () {
    test('QueryKeyHash: custom object falls back to toString, hash/== stable',
        () {
      final a = QueryKeyHash.of([_Custom(1)]);
      final b = QueryKeyHash.of([_Custom(1)]);
      expect(a, b, reason: 'equal toString → same hash key');
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), contains('Custom(1)'));
      expect(QueryKeyHash.of([_Custom(1)]) == QueryKeyHash.of([_Custom(2)]),
          isFalse);
    });

    test('idle-state getters', () {
      const q = QueryState<int>.idle();
      expect(q.isIdle, isTrue);
      expect(q.isLoading, isFalse);
      const m = MutationState<int>.idle();
      expect(m.isIdle, isTrue);
      expect(m.isLoading, isFalse);
    });

    test('QueryClient.instance is a lazily-created shared singleton', () {
      expect(identical(QueryClient.instance, QueryClient.instance), isTrue);
    });
  });

  group('Query / QueryFamily (0.3.0)', () {
    test('fetch() goes through the cache, refetch() bypasses staleTime', () async {
      final client = QueryClient();
      var calls = 0;
      final q = Query<int>(
        key: const ['n'],
        fn: () async {
          calls += 1;
          return calls;
        },
        staleTime: const Duration(seconds: 10),
        client: client,
      );

      expect(await q.fetch(), 1);
      expect(await q.fetch(), 1, reason: 'fresh cache should not refetch');
      expect(calls, 1);

      expect(await q.refetch(), 2, reason: 'refetch ignores staleTime');
      expect(calls, 2);
      client.clear();
    });

    test('fetch() shares the cache with client.fetchQuery on the same key',
        () async {
      final client = QueryClient();
      var calls = 0;
      final q = Query<int>(
        key: const ['n'],
        fn: () async {
          calls += 1;
          return 7;
        },
        staleTime: const Duration(seconds: 10),
        client: client,
      );

      expect(await q.fetch(), 7);
      final direct = await client.fetchQuery<int>(
        key: const ['n'],
        fn: () async => 99,
        staleTime: const Duration(seconds: 10),
      );
      expect(direct, 7, reason: 'same key, still fresh — one shared entry');
      expect(calls, 1);
      client.clear();
    });

    test('data / state read synchronously; setData writes without fn',
        () async {
      final client = QueryClient();
      var calls = 0;
      final q = Query<int>(
        key: const ['n'],
        fn: () async {
          calls += 1;
          return 1;
        },
        client: client,
      );

      expect(q.data, isNull);
      expect(q.state.isIdle, isTrue);

      q.setData(42);
      expect(q.data, 42);
      expect(q.state.isSuccess, isTrue);
      expect(calls, 0, reason: 'setData must not call fn');
      client.clear();
    });

    test('stream emits state changes for the key', () async {
      final client = QueryClient();
      final q = Query<int>(
        key: const ['n'],
        fn: () async => 5,
        client: client,
      );

      final seen = <QueryStatus>[];
      final sub = q.stream.listen((s) => seen.add(s.status));
      await q.fetch();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(seen, contains(QueryStatus.success));
      client.clear();
    });

    test('invalidate() marks only this key stale, not keys nested under it',
        () async {
      final client = QueryClient();
      var listCalls = 0;
      var pageCalls = 0;
      const stale = Duration(seconds: 10);

      final list = Query<int>(
        key: const ['posts'],
        fn: () async => ++listCalls,
        staleTime: stale,
        client: client,
      );
      final page = Query<int>(
        key: const ['posts', 'page', 2],
        fn: () async => ++pageCalls,
        staleTime: stale,
        client: client,
      );

      await list.fetch();
      await page.fetch();
      expect([listCalls, pageCalls], [1, 1]);

      list.invalidate();
      await list.fetch();
      await page.fetch();

      expect(listCalls, 2, reason: 'the invalidated key refetches');
      expect(pageCalls, 1,
          reason: 'a nested key is untouched — Query.invalidate is exact');
      client.clear();
    });

    test('invalidate() refetches an entry that has subscribers', () async {
      final client = QueryClient();
      var calls = 0;
      final q = Query<int>(
        key: const ['n'],
        fn: () async => ++calls,
        staleTime: const Duration(seconds: 10),
        client: client,
      );
      client.onSubscribe<int>(q.key);
      await q.fetch();
      expect(calls, 1);

      q.invalidate();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2, reason: 'entries with subscribers refetch immediately');

      client.onUnsubscribe<int>(q.key);
      client.clear();
    });

    test('remove() drops only this key, not keys nested under it', () async {
      final client = QueryClient();
      final list = Query<int>(
          key: const ['posts'], fn: () async => 1, client: client);
      final page = Query<int>(
          key: const ['posts', 'page', 2], fn: () async => 2, client: client);

      await list.fetch();
      await page.fetch();

      list.remove();
      expect(list.data, isNull);
      expect(page.data, 2, reason: 'Query.remove is exact');

      client.removeQueries(const ['posts']);
      expect(page.data, isNull, reason: 'removeQueries is still prefix-wide');
      client.clear();
    });

    test('copyWith overrides individual options', () async {
      final client = QueryClient();
      var calls = 0;
      final base = Query<int>(
        key: const ['n'],
        fn: () async => ++calls,
        staleTime: const Duration(seconds: 10),
        client: client,
      );

      await base.fetch();
      await base.copyWith(staleTime: Duration.zero).fetch();
      expect(calls, 2, reason: 'the copy fetches with its own staleTime');
      expect(base.staleTime, const Duration(seconds: 10),
          reason: 'the original is untouched');
      expect(base.copyWith(key: const ['m']).key, const ['m']);
      client.clear();
    });

    test('a Query with no client targets the shared singleton', () async {
      final q = Query<int>(key: const ['singleton-probe'], fn: () async => 3);
      await q.fetch();
      expect(QueryClient.instance.getQueryData<int>(const ['singleton-probe']), 3);
      q.remove();
    });

    test('toString names the type and the key', () {
      final q = Query<int>(key: const ['n', 1], fn: () async => 1);
      expect(q.toString(), 'Query<int>(["n",1])');
      const f = QueryFamily<int, int>(prefix: ['post'], fn: _identityFetch);
      expect(f.toString(), 'QueryFamily<int, int>(["post"])');
    });

    test('QueryFamily gives each argument its own cache entry', () async {
      final client = QueryClient();
      final calls = <int, int>{};
      final family = QueryFamily<int, int>(
        prefix: const ['post'],
        fn: (id) async {
          calls[id] = (calls[id] ?? 0) + 1;
          return id * 10;
        },
        staleTime: const Duration(seconds: 10),
        client: client,
      );

      expect(family.keyFor(3), ['post', 3]);
      expect(await family(3).fetch(), 30);
      expect(await family(4).fetch(), 40);
      expect(await family(3).fetch(), 30);

      expect(calls, {3: 1, 4: 1}, reason: 'one entry per argument');
      client.clear();
    });

    test('QueryFamily.argKey builds keys from primitives', () async {
      final client = QueryClient();
      final family = QueryFamily<String, (int, String)>(
        prefix: const ['posts'],
        argKey: (a) => [a.$1, a.$2],
        fn: (a) async => 'page ${a.$1} of ${a.$2}',
        client: client,
      );

      expect(family.keyFor((2, 'flutter')), ['posts', 2, 'flutter']);
      expect(await family((2, 'flutter')).fetch(), 'page 2 of flutter');
      expect(client.getQueryData<String>(['posts', 2, 'flutter']),
          'page 2 of flutter');
      client.clear();
    });

    test('invalidateAll / removeAll cover every member of the family',
        () async {
      final client = QueryClient();
      final calls = <int, int>{};
      final family = QueryFamily<int, int>(
        prefix: const ['post'],
        fn: (id) async {
          calls[id] = (calls[id] ?? 0) + 1;
          return id;
        },
        staleTime: const Duration(seconds: 10),
        client: client,
      );
      final other = Query<int>(
        key: const ['posts'],
        fn: () async => 0,
        staleTime: const Duration(seconds: 10),
        client: client,
      );

      await family(1).fetch();
      await family(2).fetch();
      await other.fetch();

      family.invalidateAll();
      await family(1).fetch();
      await family(2).fetch();
      expect(calls, {1: 2, 2: 2});

      family.removeAll();
      expect(family(1).data, isNull);
      expect(family(2).data, isNull);
      expect(other.data, 0, reason: 'a sibling prefix is untouched');
      client.clear();
    });

    testWidgets('QueryBuilder.of renders a definition and shares its cache',
        (tester) async {
      final client = QueryClient();
      var calls = 0;
      final q = Query<int>(
        key: const ['n'],
        fn: () async {
          calls += 1;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return 7;
        },
        staleTime: const Duration(seconds: 10),
        client: client,
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: QueryBuilder.of(
            q,
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

      expect(await q.fetch(), 7);
      expect(calls, 1, reason: 'the imperative call hits the widget\'s entry');

      // An imperative write reaches the mounted builder.
      q.setData(9);
      await tester.pumpAndSettle();
      expect(find.text('data=9'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      client.clear();
    });

    testWidgets('QueryBuilder.of passes the definition\'s options through',
        (tester) async {
      final client = QueryClient();
      var calls = 0;
      final q = Query<int>(
        key: const ['n'],
        fn: () async {
          calls += 1;
          throw StateError('boom');
        },
        retry: 2,
        retryDelay: (_) => Duration.zero,
        client: client,
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: QueryBuilder.of(
            q,
            builder: (context, state, refetch) =>
                Text(state.isError ? 'error' : 'pending'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('error'), findsOneWidget);
      expect(calls, 3, reason: 'retry: 2 came from the Query definition');

      await tester.pumpWidget(const SizedBox());
      client.clear();
    });
  });

  group('v0.4.0-dev.1 additions', () {
    group('initialData', () {
      test('seeds an empty entry, no fetch fires while fresh', () async {
        final client = QueryClient();
        var calls = 0;
        final q = Query<int>(
          key: const ['seed'],
          fn: () async {
            calls += 1;
            return 99;
          },
          staleTime: const Duration(seconds: 30),
          initialData: () => 42,
          client: client,
        );

        final v = await q.fetch();
        expect(v, 42, reason: 'initialData seeds the cache directly');
        expect(calls, 0, reason: 'fresh seed short-circuits the fetch');
        expect(q.data, 42);
      });

      test('does not overwrite existing data', () async {
        final client = QueryClient();
        var calls = 0;
        Future<int> real() async {
          calls += 1;
          return 7;
        }

        await client.fetchQuery<int>(
          key: const ['x'],
          fn: real,
          staleTime: Duration.zero,
        );
        expect(calls, 1);

        // Second call with initialData set — entry already has data, seed
        // must be ignored so the cached 7 is preserved.
        var seedCalls = 0;
        await client.fetchQuery<int>(
          key: const ['x'],
          fn: real,
          staleTime: const Duration(seconds: 30),
          initialData: () {
            seedCalls += 1;
            return 999;
          },
        );
        expect(seedCalls, 0, reason: 'seed skipped when entry has data');
        expect(client.getQueryData<int>(const ['x']), 7);
      });

      test('initialDataUpdatedAt in the past triggers a refetch when stale',
          () async {
        final client = QueryClient();
        var calls = 0;
        final q = Query<int>(
          key: const ['staleSeed'],
          fn: () async {
            calls += 1;
            return 100;
          },
          staleTime: const Duration(milliseconds: 10),
          initialData: () => 1,
          initialDataUpdatedAt:
              DateTime.now().subtract(const Duration(seconds: 5)),
          client: client,
        );

        final v = await q.fetch();
        expect(v, 100, reason: 'stale seed should force a real fetch');
        expect(calls, 1);
      });

      test('QueryFamily seed receives its argument', () async {
        final client = QueryClient();
        var calls = 0;
        final fam = QueryFamily<int, int>(
          prefix: const ['n'],
          fn: (id) async {
            calls += 1;
            return id * 10;
          },
          staleTime: const Duration(seconds: 30),
          initialData: (id) => id * 100,
          client: client,
        );

        expect(await fam(3).fetch(), 300);
        expect(await fam(7).fetch(), 700);
        expect(calls, 0, reason: 'both members seeded, neither fetched');
      });
    });

    group('MutationBuilder retry', () {
      testWidgets('succeeds on a later attempt without surfacing an error',
          (tester) async {
        var calls = 0;
        late Future<int?> Function(int) doMutate;

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MutationBuilder<int, int>(
              mutationFn: (v) async {
                calls += 1;
                if (calls < 3) throw StateError('boom');
                return v * 2;
              },
              retry: 3,
              retryDelay: (_) => Duration.zero,
              builder: (context, mutate, state) {
                doMutate = mutate;
                return const SizedBox();
              },
            ),
          ),
        );

        // runAsync lets the retry loop's Future.delayed(Duration.zero) fire
        // against real time — a plain await deadlocks against the widget
        // tester's fake clock.
        final result = await tester.runAsync(() => doMutate(5));
        await tester.pumpAndSettle();
        expect(result, 10);
        expect(calls, 3, reason: '2 failures + 1 success');
      });

      testWidgets('rollback fires only after all retries exhaust',
          (tester) async {
        final client = QueryClient();
        client.setQueryData<int>(const ['n'], 0);
        var rollbackCalls = 0;
        late Future<int?> Function(int) doMutate;

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MutationBuilder<int, int>(
              mutationFn: (_) async => throw StateError('always fails'),
              retry: 2,
              retryDelay: (_) => Duration.zero,
              onMutate: (v) {
                client.setQueryData<int>(const ['n'], v);
                return () {
                  rollbackCalls += 1;
                  client.setQueryData<int>(const ['n'], 0);
                };
              },
              builder: (context, mutate, state) {
                doMutate = mutate;
                return const SizedBox();
              },
            ),
          ),
        );

        final result = await tester.runAsync(() => doMutate(42));
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(rollbackCalls, 1,
            reason: 'rollback fires once, after all retries exhaust');
        expect(client.getQueryData<int>(const ['n']), 0,
            reason: 'rollback restored the pre-mutation value');
        client.clear();
      });
    });

    group('notifyOnChangeProps', () {
      testWidgets('skips rebuild when only unwatched fields change',
          (tester) async {
        final client = QueryClient();
        var buildCount = 0;

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: QueryBuilder<int>(
              queryKey: const ['n'],
              queryFn: () async => 1,
              staleTime: Duration.zero,
              refetchOnResume: false,
              notifyOn: const {QueryProp.data, QueryProp.error},
              client: client,
              builder: (context, state, _) {
                buildCount += 1;
                return Text('${state.data ?? '?'}');
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final buildsAfterFirstFetch = buildCount;

        // Set the same data again — data is identity-compared, so this counts
        // as a change (a new int is a new object). Use setQueryData with the
        // SAME int constant (Dart interns small ints) to avoid a change.
        // Actually int literals ARE identical for small values, so this won't
        // trigger a rebuild. Meanwhile, a background refetch will flip
        // isFetching but notifyOn ignores it.
        client.invalidateQueriesWhere(
          (k) => QueryKeyHash.of(k) == QueryKeyHash.of(const ['n']),
        );
        await tester.pumpAndSettle();

        // A rebuild count that grew by more than 1 (the initial invalidate
        // → loading → same-data-success cycle) means notifyOn didn't
        // suppress the isFetching flicker.
        final rebuildsForBackgroundCycle = buildCount - buildsAfterFirstFetch;
        expect(rebuildsForBackgroundCycle, lessThanOrEqualTo(1),
            reason: 'notifyOn:{data,error} must ignore isFetching/updatedAt');
        await tester.pumpWidget(const SizedBox());
        client.clear();
      });

      testWidgets('rebuilds normally when null (default)', (tester) async {
        final client = QueryClient();
        var buildCount = 0;

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: QueryBuilder<int>(
              queryKey: const ['m'],
              queryFn: () async => 1,
              staleTime: Duration.zero,
              refetchOnResume: false,
              client: client,
              builder: (context, state, _) {
                buildCount += 1;
                return Text('${state.data ?? '?'}');
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final before = buildCount;

        client.invalidateQueriesWhere(
          (k) => QueryKeyHash.of(k) == QueryKeyHash.of(const ['m']),
        );
        await tester.pumpAndSettle();
        expect(buildCount, greaterThan(before),
            reason: 'no notifyOn → invalidate cycle rebuilds normally');
        await tester.pumpWidget(const SizedBox());
        client.clear();
      });
    });

    group('refetchInterval', () {
      // Exercise the QueryClient timer directly rather than through
      // testWidgets: the widget-tester's fake clock does not naturally
      // interleave with Timer.periodic + queryFn's async chain, and using
      // real-time delays inside `pumpWidget` deadlocks. The subscriber
      // lifecycle is what we're verifying, and it lives on QueryClient.
      test('polls while subscribed, pauses on last unsubscribe', () async {
        final client = QueryClient();
        var calls = 0;
        Future<int> fn() async => ++calls;

        // Warm the entry + capture refetchInterval by simulating a
        // subscribed QueryBuilder: kick off + register subscriber.
        await client.fetchQuery<int>(
          key: const ['poll'],
          fn: fn,
          staleTime: const Duration(seconds: 30),
          refetchInterval: const Duration(milliseconds: 40),
        );
        expect(calls, 1);
        client.onSubscribe<int>(const ['poll']);

        // Let two periodic ticks fire (real time).
        await Future<void>.delayed(const Duration(milliseconds: 110));
        expect(calls, greaterThanOrEqualTo(3),
            reason: 'at least two ticks fired while subscribed');

        // Last-subscriber-leaves → timer must cancel.
        client.onUnsubscribe<int>(const ['poll']);
        final callsAtUnsub = calls;
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(calls, callsAtUnsub,
            reason: 'no polling once the last subscriber leaves');

        client.clear();
      });

      test('re-arms when a subscriber returns', () async {
        final client = QueryClient();
        var calls = 0;
        Future<int> fn() async => ++calls;

        await client.fetchQuery<int>(
          key: const ['poll2'],
          fn: fn,
          staleTime: const Duration(seconds: 30),
          refetchInterval: const Duration(milliseconds: 40),
        );
        client.onSubscribe<int>(const ['poll2']);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        final callsBefore = calls;

        client.onUnsubscribe<int>(const ['poll2']);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final callsQuiet = calls;

        client.onSubscribe<int>(const ['poll2']);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(calls, greaterThan(callsQuiet),
            reason: 're-subscribe re-arms the polling timer');
        expect(callsBefore, greaterThan(0));

        client.onUnsubscribe<int>(const ['poll2']);
        client.clear();
      });
    });
  });
}
