import 'dart:async';

import 'package:flutter/widgets.dart';

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
  });

  final QueryKey queryKey;
  final QueryFn<T> queryFn;
  final QueryWidgetBuilder<T> builder;
  final Duration? staleTime;
  final QueryClient? client;
  final bool enabled;
  final bool refetchOnResume;

  @override
  State<QueryBuilder<T>> createState() => _QueryBuilderState<T>();
}

class _QueryBuilderState<T> extends State<QueryBuilder<T>>
    with WidgetsBindingObserver {
  late QueryClient _client;
  StreamSubscription<QueryState<T>>? _sub;
  QueryState<T> _state = const QueryState<Never>.idle() as QueryState<T>;

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
    }
  }

  void _subscribe() {
    _client.onSubscribe<T>(widget.queryKey);
    _sub = _client.observe<T>(widget.queryKey).listen((next) {
      if (!mounted) return;
      setState(() => _state = next);
    });
    _state = _client.stateOf<T>(widget.queryKey);
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
  Widget build(BuildContext context) => widget.builder(context, _state, _refetch);
}
