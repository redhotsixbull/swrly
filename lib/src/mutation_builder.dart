import 'dart:async';

import 'package:flutter/widgets.dart';

import 'mutation_state.dart';

typedef MutationFn<T, V> = Future<T> Function(V variables);
typedef MutationWidgetBuilder<T, V> = Widget Function(
  BuildContext context,
  Future<T?> Function(V variables) mutate,
  MutationState<T> state,
);

/// Runs before [MutationBuilder.mutationFn]. Apply an optimistic write here and
/// return a **rollback** closure; swrly runs it automatically if the mutation
/// throws (before `onError`). Return `null` for no rollback. May be async (e.g.
/// to snapshot state or cancel in-flight queries first).
typedef MutationOnMutate<V> = FutureOr<void Function()?> Function(V variables);

class MutationBuilder<T, V> extends StatefulWidget {
  const MutationBuilder({
    super.key,
    required this.mutationFn,
    required this.builder,
    this.onMutate,
    this.onSuccess,
    this.onError,
    this.onSettled,
  });

  final MutationFn<T, V> mutationFn;
  final MutationWidgetBuilder<T, V> builder;

  /// Optimistic-update hook: apply the optimistic change and return a rollback
  /// closure that swrly runs automatically on error. See [MutationOnMutate].
  final MutationOnMutate<V>? onMutate;

  final void Function(T data, V variables)? onSuccess;
  final void Function(Object error, StackTrace stackTrace, V variables)? onError;
  final void Function(V variables)? onSettled;

  @override
  State<MutationBuilder<T, V>> createState() => _MutationBuilderState<T, V>();
}

class _MutationBuilderState<T, V> extends State<MutationBuilder<T, V>> {
  MutationState<T> _state = const MutationState<Never>.idle() as MutationState<T>;

  Future<T?> _mutate(V variables) async {
    // Only `setState` is guarded by `mounted`; the app-level callbacks
    // (onMutate/onSuccess/onError/onSettled) and the automatic rollback MUST
    // run even if the widget disposes mid-flight, otherwise a cache
    // invalidation or optimistic rollback would silently be skipped.
    if (mounted) {
      setState(() => _state = MutationState<T>(status: MutationStatus.loading));
    }
    // Apply the optimistic update (if any) and capture its rollback. If
    // onMutate itself throws, rollback stays null and we fall through to the
    // error path.
    void Function()? rollback;
    try {
      rollback = await widget.onMutate?.call(variables);
      final result = await widget.mutationFn(variables);
      if (mounted) {
        setState(() => _state = MutationState<T>(
              status: MutationStatus.success,
              data: result,
            ));
      }
      widget.onSuccess?.call(result, variables);
      widget.onSettled?.call(variables);
      return result;
    } catch (e, st) {
      // Roll back the optimistic write before surfacing the error.
      rollback?.call();
      if (mounted) {
        setState(() => _state = MutationState<T>(
              status: MutationStatus.error,
              error: e,
              stackTrace: st,
            ));
      }
      widget.onError?.call(e, st, variables);
      widget.onSettled?.call(variables);
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _mutate, _state);
}
