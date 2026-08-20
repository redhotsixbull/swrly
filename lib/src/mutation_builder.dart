import 'package:flutter/widgets.dart';

import 'mutation_state.dart';

typedef MutationFn<T, V> = Future<T> Function(V variables);
typedef MutationWidgetBuilder<T, V> = Widget Function(
  BuildContext context,
  Future<T?> Function(V variables) mutate,
  MutationState<T> state,
);

class MutationBuilder<T, V> extends StatefulWidget {
  const MutationBuilder({
    super.key,
    required this.mutationFn,
    required this.builder,
    this.onSuccess,
    this.onError,
    this.onSettled,
  });

  final MutationFn<T, V> mutationFn;
  final MutationWidgetBuilder<T, V> builder;
  final void Function(T data, V variables)? onSuccess;
  final void Function(Object error, StackTrace stackTrace, V variables)? onError;
  final void Function(V variables)? onSettled;

  @override
  State<MutationBuilder<T, V>> createState() => _MutationBuilderState<T, V>();
}

class _MutationBuilderState<T, V> extends State<MutationBuilder<T, V>> {
  MutationState<T> _state = const MutationState<Never>.idle() as MutationState<T>;

  Future<T?> _mutate(V variables) async {
    setState(() => _state = const MutationState<Never>.idle() as MutationState<T>);
    setState(() => _state = MutationState<T>(status: MutationStatus.loading));
    try {
      final result = await widget.mutationFn(variables);
      if (!mounted) return result;
      setState(() => _state = MutationState<T>(
            status: MutationStatus.success,
            data: result,
          ));
      widget.onSuccess?.call(result, variables);
      widget.onSettled?.call(variables);
      return result;
    } catch (e, st) {
      if (!mounted) return null;
      setState(() => _state = MutationState<T>(
            status: MutationStatus.error,
            error: e,
            stackTrace: st,
          ));
      widget.onError?.call(e, st, variables);
      widget.onSettled?.call(variables);
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _mutate, _state);
}
