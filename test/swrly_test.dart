import 'package:flutter/widgets.dart';
import 'package:swrly/swrly.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QueryClient', () {
    test('fetchQuery returns data and caches it', () async {
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

    test('invalidateQueries marks matching keys as stale', () async {
      final client = QueryClient();
      var calls = 0;
      Future<int> fn() async {
        calls += 1;
        return calls;
      }

      await client.fetchQuery<int>(
          key: ['user', 1], fn: fn, staleTime: const Duration(minutes: 5));
      client.invalidateQueries(['user']);
      final result = await client.fetchQuery<int>(
          key: ['user', 1], fn: fn, staleTime: const Duration(minutes: 5));

      expect(result, 2);
      expect(calls, 2);
    });

    test('setQueryData writes without going through the fn', () {
      final client = QueryClient();
      client.setQueryData<int>(['n'], 99);
      expect(client.getQueryData<int>(['n']), 99);
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
  });
}
