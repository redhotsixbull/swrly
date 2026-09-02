import 'package:flutter/foundation.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:swrly/swrly.dart';

/// # Canonical `useSwrlyQuery` / `useSwrlyMutation` snippet
///
/// `swrly` intentionally does **not** ship these hooks — see
/// `doc/CONVENTIONS.md §10` for the rationale (in short: Dart has no
/// peer deps, and a self-hosted hook runtime would break composition
/// with `useState` and friends).
///
/// If you use `flutter_hooks` in your project, copy this file into
/// `lib/hooks/` (or run the `swrly-init` skill, which does it for you).
/// This file is the *canonical* snippet — the `swrly-refactor-hooks`
/// skill installs exactly this, and this file is what `readme_snippets_test`
/// in the swrly repo pins to catch drift.

/// Subscribe a hook-based widget to a swrly `Query<T>`. Rebuilds on
/// every state change. The `useEffect` kicks off an initial fetch (which
/// no-ops if the entry is fresh in cache).
QueryState<T> useSwrlyQuery<T>(Query<T> query) {
  useEffect(() {
    query.fetch();
    return null;
  }, [_keyOf(query)]);

  final snapshot = useStream<QueryState<T>>(
    query.stream,
    initialData: query.state,
  );
  return snapshot.data ?? query.state;
}

/// Small imperative surface for mutations from a hook widget. Returns
/// `(state, mutate)` — call `mutate(vars)` to fire the mutation.
///
/// The full-featured `MutationBuilder` (`onMutate` rollback closure,
/// `onSuccess`, `onSettled`) is still available — this hook is for
/// the common case where you just want a button to run a function.
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

/// Stable identity for the `useEffect` dep list — `query.key` is a
/// `QueryKey` value object, so its `toString()` is deterministic.
String _keyOf(Query<Object?> q) => q.key.toString();

// -----------------------------------------------------------------------
// MutationState — small envelope so `useSwrlyMutation` has something to
// return without pulling in `MutationBuilder`'s internals. If you already
// use `MutationBuilder` elsewhere, prefer that; this is purely for the
// "I want a hook" case.
// -----------------------------------------------------------------------

@immutable
class MutationState<T> {
  const MutationState._(
    this.status, {
    this.data,
    this.error,
    this.stackTrace,
  });
  const MutationState.idle() : this._(MutationStatus.idle);
  const MutationState.loading() : this._(MutationStatus.loading);
  const MutationState.success(T value)
      : this._(MutationStatus.success, data: value);
  const MutationState.error(Object err, StackTrace? st)
      : this._(MutationStatus.error, error: err, stackTrace: st);

  final MutationStatus status;
  final T? data;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isLoading => status == MutationStatus.loading;
  bool get isSuccess => status == MutationStatus.success;
  bool get isError => status == MutationStatus.error;
}

enum MutationStatus { idle, loading, success, error }
