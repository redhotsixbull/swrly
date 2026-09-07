import 'package:flutter_hooks/flutter_hooks.dart';

import 'mutation_state.dart';

/// Fire-and-forget mutation hook. Returns a record of `(state, mutate)`.
///
/// Use this when the mutation is a simple button handler and you want
/// hook-flavoured ergonomics. For anything that needs `onMutate` returning
/// a rollback closure, `onSuccess` / `onSettled` callbacks that fire
/// regardless of mount state, or coordination with other Bloc/Cubit code,
/// use swrly's built-in `MutationBuilder` instead — this hook intentionally
/// stays minimal.
({MutationState<T> state, Future<void> Function(V vars) mutate})
    useSwrlyMutation<T, V>(Future<T> Function(V) fn) {
  final state = useState<MutationState<T>>(const MutationState.idle());
  final disposed = useRef<bool>(false);
  useEffect(() => () => disposed.value = true, const []);

  Future<void> mutate(V vars) async {
    state.value = const MutationState.loading();
    try {
      final result = await fn(vars);
      if (!disposed.value) state.value = MutationState.success(result);
    } catch (e, st) {
      if (!disposed.value) state.value = MutationState.error(e, st);
    }
  }

  return (state: state.value, mutate: mutate);
}
