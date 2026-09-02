import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swrly_hooks/swrly_hooks.dart';

class _MutCapture<T, V> {
  MutationState<T>? state;
  late Future<void> Function(V) mutate;
}

Widget _mutHost<T, V>(
  Future<T> Function(V) fn,
  _MutCapture<T, V> capture,
) {
  return MaterialApp(
    home: HookBuilder(
      builder: (context) {
        final m = useSwrlyMutation<T, V>(fn);
        capture.state = m.state;
        capture.mutate = m.mutate;
        return const SizedBox.shrink();
      },
    ),
  );
}

void main() {
  group('useSwrlyMutation', () {
    testWidgets('completes with success state and data', (tester) async {
      final capture = _MutCapture<int, int>();
      await tester.pumpWidget(_mutHost<int, int>(
        (v) async => v * 2,
        capture,
      ));

      expect(capture.state!.status, MutationStatus.idle);

      final fut = capture.mutate(21);
      await fut;
      await tester.pumpAndSettle();

      expect(capture.state!.isSuccess, isTrue);
      expect(capture.state!.data, 42);
    });

    testWidgets('exposes loading state while the future is pending',
        (tester) async {
      // Use a Completer to hold the mutation open long enough that we can
      // observe the loading transition — an inline `async` future resolves
      // in the same pump and racemasks the loading state.
      final gate = Completer<int>();
      final capture = _MutCapture<int, int>();
      await tester.pumpWidget(_mutHost<int, int>(
        (_) => gate.future,
        capture,
      ));

      final fut = capture.mutate(1);
      await tester.pump(); // let the state.value = loading rebuild fire
      expect(capture.state!.isLoading, isTrue);

      gate.complete(99);
      await fut;
      await tester.pumpAndSettle();
      expect(capture.state!.isSuccess, isTrue);
      expect(capture.state!.data, 99);
    });

    testWidgets('surfaces errors as state.error', (tester) async {
      final capture = _MutCapture<int, int>();
      await tester.pumpWidget(_mutHost<int, int>(
        (_) async => throw StateError('boom'),
        capture,
      ));

      final fut = capture.mutate(1);
      await fut;
      await tester.pumpAndSettle();

      expect(capture.state!.isError, isTrue);
      expect(capture.state!.error, isStateError);
    });

    testWidgets('does not setState after unmount', (tester) async {
      final gate = Completer<int>();
      final capture = _MutCapture<int, int>();
      await tester.pumpWidget(_mutHost<int, int>(
        (_) => gate.future,
        capture,
      ));

      final fut = capture.mutate(7);

      // Unmount mid-flight.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      // Complete the future — the disposed-guard should swallow the
      // state.value write.
      gate.complete(7);
      await fut;
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
