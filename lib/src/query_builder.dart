import 'dart:async';

import 'package:flutter/widgets.dart';

import 'query.dart';
import 'query_client.dart';
import 'query_key.dart';
import 'query_state.dart';

typedef QueryWidgetBuilder<T> = Widget Function(
  BuildContext context,
  QueryState<T> state,
  Future<void> Function() refetch,
);

class QueryBuilder<T> extends StatefulWidget {
  const QueryBuilder({
    super.key,
    required this.queryKey,
    required this.queryFn,
    required this.builder,
    this.staleTime,
    this.client,
    this.enabled = true,
    this.refetchOnResume = true,
    this.retry,
    this.retryDelay,
    this.keepPreviousData = false,
    this.placeholderData,
    this.initialData,
    this.initialDataUpdatedAt,
    this.refetchInterval,
    this.notifyOn,
  });

  /// Builds from a [Query] definition instead of a loose `queryKey`/`queryFn`
  /// pair, so the key and fetch function are declared once and shared with the
  /// imperative call sites:
  ///
  /// ```dart
  /// final postsQuery = Query<List<Post>>(key: const ['posts'], fn: api.getPosts);
  ///
  /// QueryBuilder.of(postsQuery, builder: (context, state, refetch) => ...);
  /// ```
  ///
  /// [Query.staleTime], `retry`, `retryDelay` and `client` come from the
  /// definition; the widget-only options stay here. To override one of the
  /// definition's options at a single call site, pass
  /// `postsQuery.copyWith(staleTime: ...)`.
  factory QueryBuilder.of(
    Query<T> query, {
    Key? key,
    required QueryWidgetBuilder<T> builder,
    bool enabled = true,
    bool refetchOnResume = true,
    bool keepPreviousData = false,
    T? placeholderData,
    Set<QueryProp>? notifyOn,
  }) {
    return QueryBuilder<T>(
      key: key,
      queryKey: query.key,
      queryFn: query.fn,
      builder: builder,
      staleTime: query.staleTime,
      client: query.client,
      enabled: enabled,
      refetchOnResume: refetchOnResume,
      retry: query.retry,
      retryDelay: query.retryDelay,
      keepPreviousData: keepPreviousData,
      placeholderData: placeholderData,
      initialData: query.initialData,
      initialDataUpdatedAt: query.initialDataUpdatedAt,
      refetchInterval: query.refetchInterval,
      notifyOn: notifyOn,
    );
  }

  final QueryKey queryKey;
  final QueryFn<T> queryFn;
  final QueryWidgetBuilder<T> builder;
  final Duration? staleTime;
  final QueryClient? client;
  final bool enabled;
  final bool refetchOnResume;

  /// Number of retries (attempts after the first) when [queryFn] throws.
  /// Defaults to the client's `defaultRetry` when null.
  final int? retry;

  /// Backoff before each retry. Defaults to the client's `defaultRetryDelay`
  /// when null.
  final RetryDelay? retryDelay;

  /// When true, a **key change** keeps rendering the previous key's data (as
  /// `isPlaceholderData`) until the new key resolves, instead of flashing to a
  /// loading state. See SPEC §9.
  final bool keepPreviousData;

  /// A static stand-in shown (as `isPlaceholderData`) while the current key has
  /// no real data yet. Not cached; does not affect freshness.
  final T? placeholderData;

  /// Seeds the cache with a real value when this key is first observed.
  /// See [Query.initialData] — the definition-object form is the usual entry
  /// point; this widget-level knob exists for `QueryBuilder` used without a
  /// [Query].
  final T Function()? initialData;

  /// See [Query.initialDataUpdatedAt].
  final DateTime? initialDataUpdatedAt;

  /// See [Query.refetchInterval]. `null` (the default) means no polling.
  final Duration? refetchInterval;

  /// When non-null, `setState` only fires when at least one of these fields
  /// actually changes between successive state emissions. Cheap opt-in perf
  /// tuning for widgets that don't care about `isFetching` flicker or
  /// `updatedAt` bumps. Default (null) matches previous behaviour: rebuild on
  /// every state change. See [QueryProp].
  final Set<QueryProp>? notifyOn;

  @override
  State<QueryBuilder<T>> createState() => _QueryBuilderState<T>();
}

class _QueryBuilderState<T> extends State<QueryBuilder<T>>
    with WidgetsBindingObserver {
  late QueryClient _client;
  StreamSubscription<QueryState<T>>? _sub;
  QueryState<T> _state = const QueryState<Never>.idle() as QueryState<T>;

  /// The last *real* (non-placeholder) data seen, kept across a key change so
  /// `keepPreviousData` can show it while the new key loads. Cleared only when a
  /// new real value replaces it.
  T? _keptData;
  bool _hasKeptData = false;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? QueryClient.instance;
    _subscribe();
    if (widget.enabled) {
      _kickOffFetch();
      _syncStateFromClient();
    }
    if (widget.refetchOnResume) {
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void didUpdateWidget(covariant QueryBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final keyChanged = QueryKeyHash.of(widget.queryKey) !=
        QueryKeyHash.of(oldWidget.queryKey);
    final clientChanged = (widget.client ?? QueryClient.instance) != _client;
    if (keyChanged || clientChanged) {
      _cleanupSubscription(oldWidget.queryKey);
      _client = widget.client ?? QueryClient.instance;
      _subscribe();
      if (widget.enabled) _kickOffFetch();
    } else if (widget.enabled) {
      // Same key/client and still enabled: re-capture the current
      // queryFn/staleTime so a later invalidateQueries refetch runs *this*
      // build's closure, not a stale one. We do NOT refetch on a plain queryFn
      // identity change — inline closures change every build (see SPEC §9).
      // Priming is gated on `enabled` so a disabled query never gets a
      // refetcher installed (invalidateQueries must skip it — SPEC §9).
      _client.primeRefetcher<T>(
        key: widget.queryKey,
        fn: widget.queryFn,
        staleTime: widget.staleTime,
        retry: widget.retry,
        retryDelay: widget.retryDelay,
        refetchInterval: widget.refetchInterval,
      );
      if (!oldWidget.enabled) {
        // enabled flipped false → true: kick off the fetch initState skipped.
        _kickOffFetch();
      }
    }
  }

  void _subscribe() {
    _client.onSubscribe<T>(widget.queryKey);
    _sub = _client.observe<T>(widget.queryKey).listen((next) {
      if (!mounted) return;
      final notifyOn = widget.notifyOn;
      // With a filter set, only rebuild when a listed field actually changed.
      // Still refresh _state / _keptData so a later unfiltered rebuild (or
      // consecutive state comparisons) see the latest values.
      if (notifyOn != null && notifyOn.isNotEmpty) {
        final changed = next.differsFrom(_state, notifyOn);
        _state = next;
        _rememberRealData(next);
        if (changed) setState(() {});
        return;
      }
      setState(() {
        _state = next;
        _rememberRealData(next);
      });
    });
    _state = _client.stateOf<T>(widget.queryKey);
    _rememberRealData(_state);
  }

  void _rememberRealData(QueryState<T> s) {
    if (s.hasData) {
      _keptData = s.data;
      _hasKeptData = true;
    }
  }

  /// The state handed to [builder]: real data when present, otherwise the
  /// previous key's data (`keepPreviousData`) or [placeholderData], flagged as
  /// `isPlaceholderData`.
  QueryState<T> _viewState() {
    if (_state.hasData) return _state;
    // Build a fresh QueryState<T> rather than copyWith: an entry's initial state
    // is a QueryState<Never> (cast to <T>), so copyWith's `data as T?` would
    // cast a real value to Never? and throw. Here T is the widget's real type.
    if (widget.keepPreviousData && _hasKeptData) {
      return QueryState<T>(
        status: _state.status,
        data: _keptData,
        hasData: true,
        error: _state.error,
        stackTrace: _state.stackTrace,
        updatedAt: _state.updatedAt,
        isFetching: true,
        isPlaceholderData: true,
      );
    }
    if (widget.placeholderData != null) {
      return QueryState<T>(
        status: _state.status,
        data: widget.placeholderData,
        hasData: true,
        isFetching: true,
        isPlaceholderData: true,
      );
    }
    return _state;
  }

  void _syncStateFromClient() {
    _state = _client.stateOf<T>(widget.queryKey);
  }

  void _cleanupSubscription(QueryKey oldKey) {
    _sub?.cancel();
    _sub = null;
    _client.onUnsubscribe<T>(oldKey);
  }

  Future<void> _kickOffFetch() async {
    try {
      await _client.fetchQuery<T>(
        key: widget.queryKey,
        fn: widget.queryFn,
        staleTime: widget.staleTime,
        retry: widget.retry,
        retryDelay: widget.retryDelay,
        initialData: widget.initialData,
        initialDataUpdatedAt: widget.initialDataUpdatedAt,
        refetchInterval: widget.refetchInterval,
      );
    } catch (_) {
      // Error state already emitted via stream.
    }
  }

  Future<void> _refetch() async {
    // Force refetch: temporarily set staleTime to zero.
    try {
      await _client.fetchQuery<T>(
        key: widget.queryKey,
        fn: widget.queryFn,
        staleTime: Duration.zero,
        retry: widget.retry,
        retryDelay: widget.retryDelay,
      );
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.enabled) {
      _refetch();
    }
  }

  @override
  void dispose() {
    if (widget.refetchOnResume) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _cleanupSubscription(widget.queryKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _viewState(), _refetch);
}
