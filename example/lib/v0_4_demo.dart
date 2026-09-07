// Interactive demo of the four 0.4.0-dev.1 features:
//
// - `Query.initialData` / `initialDataUpdatedAt`
// - `Query.refetchInterval`
// - `MutationBuilder.retry` / `retryDelay`
// - `QueryBuilder.notifyOn` + `QueryProp`
//
// Every interactive control carries a `Key('demo-…')` so Playwright can drive
// it by selector without depending on text position.

import 'package:flutter/material.dart';
import 'package:swrly/swrly.dart';

/// Standalone client so the demo's counters are isolated from the rest of
/// the example (which uses `QueryClient.instance`). Fresh state on every
/// screen visit.
final QueryClient _client = QueryClient();

class V04DemoScreen extends StatelessWidget {
  const V04DemoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('0.4.0-dev.1 features')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _InitialDataSection(),
          SizedBox(height: 24),
          _RefetchIntervalSection(),
          SizedBox(height: 24),
          _MutationRetrySection(),
          SizedBox(height: 24),
          _NotifyOnSection(),
        ],
      ),
    );
  }
}

// ── 1. initialData — no loading flash, seeded value renders immediately ─────

class _InitialDataSection extends StatelessWidget {
  const _InitialDataSection();

  @override
  Widget build(BuildContext context) {
    // Query with a slow fn but a seeded value. On mount the UI must show
    // `seeded=42` synchronously without any loading indicator; a background
    // refetch replaces it with `real=99` once the fn resolves.
    final q = Query<int>(
      key: const ['demo', 'initialData'],
      fn: () async {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        return 99;
      },
      staleTime: Duration.zero,
      initialData: () => 42,
      // initialDataUpdatedAt in the past → immediately stale → background
      // refetch fires so we can observe the seeded → real transition.
      initialDataUpdatedAt:
          DateTime.now().subtract(const Duration(seconds: 10)),
      client: _client,
    );

    return _Section(
      title: '1. initialData',
      description:
          'Seeded value renders synchronously — no loading flash. A stale seed '
          'triggers a background fetch to reconcile.',
      child: QueryBuilder.of(
        q,
        builder: (context, state, refetch) {
          final label = state.hasData
              ? (state.data == 42 ? 'seeded' : 'real')
              : 'loading';
          return Row(
            children: [
              Text(
                'value: $label=${state.data ?? '?'}',
                key: const Key('demo-initialData-value'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: 12),
              if (state.isFetching)
                const SizedBox(
                  key: Key('demo-initialData-fetching'),
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── 2. refetchInterval — periodic polling ───────────────────────────────────

class _RefetchIntervalSection extends StatefulWidget {
  const _RefetchIntervalSection();

  @override
  State<_RefetchIntervalSection> createState() =>
      _RefetchIntervalSectionState();
}

class _RefetchIntervalSectionState extends State<_RefetchIntervalSection> {
  bool _enabled = true;
  int _serverTick = 0;

  @override
  Widget build(BuildContext context) {
    // The server increments on every fetch — so if the timer is firing, the
    // number climbs; if disabled, it freezes.
    final q = Query<int>(
      key: const ['demo', 'refetchInterval'],
      fn: () async {
        _serverTick += 1;
        return _serverTick;
      },
      staleTime: const Duration(seconds: 30),
      refetchInterval: const Duration(milliseconds: 600),
      client: _client,
    );

    return _Section(
      title: '2. refetchInterval',
      description:
          'Polls every 600ms while enabled. Toggle stops polling; the '
          'displayed value must freeze.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QueryBuilder.of(
            q,
            enabled: _enabled,
            builder: (context, state, refetch) => Text(
              'tick: ${state.data ?? '?'}',
              key: const Key('demo-refetchInterval-value'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Switch(
                key: const Key('demo-refetchInterval-toggle'),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              Text(_enabled ? 'polling' : 'paused'),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 3. MutationBuilder retry — recover from transient failures ──────────────

class _MutationRetrySection extends StatefulWidget {
  const _MutationRetrySection();

  @override
  State<_MutationRetrySection> createState() => _MutationRetrySectionState();
}

class _MutationRetrySectionState extends State<_MutationRetrySection> {
  int _attempts = 0;
  int? _lastResult;
  String? _lastError;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '3. Mutation retry',
      description:
          'Mutation fails on the first 2 attempts, then succeeds on the 3rd. '
          'With retry=3, the UI sees only the final success.',
      child: MutationBuilder<int, int>(
        mutationFn: (v) async {
          _attempts += 1;
          if (_attempts < 3) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            throw StateError('transient failure attempt=$_attempts');
          }
          return v * 10;
        },
        retry: 3,
        retryDelay: (n) => Duration(milliseconds: 100 * n),
        onSuccess: (data, v) => setState(() {
          _lastResult = data;
          _lastError = null;
        }),
        onError: (e, _, __) => setState(() {
          _lastError = e.toString();
          _lastResult = null;
        }),
        builder: (context, mutate, state) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              key: const Key('demo-mutationRetry-run'),
              onPressed: state.isLoading
                  ? null
                  : () {
                      setState(() {
                        _attempts = 0;
                        _lastResult = null;
                        _lastError = null;
                      });
                      mutate(5);
                    },
              child: Text(state.isLoading ? 'retrying…' : 'Run mutation'),
            ),
            const SizedBox(height: 8),
            Text(
              'attempts: $_attempts',
              key: const Key('demo-mutationRetry-attempts'),
            ),
            Text(
              _lastResult != null
                  ? 'result: $_lastResult'
                  : _lastError != null
                      ? 'error: $_lastError'
                      : 'idle',
              key: const Key('demo-mutationRetry-result'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 4. notifyOnChangeProps — rebuild only when data changes ─────────────────

class _NotifyOnSection extends StatefulWidget {
  const _NotifyOnSection();

  @override
  State<_NotifyOnSection> createState() => _NotifyOnSectionState();
}

class _NotifyOnSectionState extends State<_NotifyOnSection> {
  int _fetchTick = 0;
  int _rebuildsAll = 0;
  int _rebuildsData = 0;

  @override
  Widget build(BuildContext context) {
    // Same key → same cache entry → both QueryBuilders see the same stream.
    // The `all` builder rebuilds on every emission (isFetching flicker).
    // The `data-only` builder skips the isFetching-only rebuilds.
    final q = Query<int>(
      key: const ['demo', 'notifyOn'],
      fn: () async {
        _fetchTick += 1;
        // Give the loading→success cycle multiple stream emissions so the
        // difference in rebuild counts is visible.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        return _fetchTick;
      },
      staleTime: Duration.zero,
      client: _client,
    );

    return _Section(
      title: '4. notifyOn',
      description:
          'Two builders share one cache entry. Pressing refetch triggers the '
          'loading→success flip; the notifyOn={data} builder rebuilds fewer '
          'times because it ignores isFetching flips.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: QueryBuilder.of(
                  q,
                  builder: (context, state, refetch) {
                    _rebuildsAll += 1;
                    return Text(
                      'ALL: builds=$_rebuildsAll data=${state.data ?? '?'} fetching=${state.isFetching}',
                      key: const Key('demo-notifyOn-all-label'),
                    );
                  },
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: QueryBuilder.of(
                  q,
                  notifyOn: const {QueryProp.data},
                  builder: (context, state, refetch) {
                    _rebuildsData += 1;
                    return Text(
                      'DATA-ONLY: builds=$_rebuildsData data=${state.data ?? '?'}',
                      key: const Key('demo-notifyOn-data-label'),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            key: const Key('demo-notifyOn-refetch'),
            onPressed: () {
              _client.invalidateQueriesWhere(
                (k) => QueryKeyHash.of(k) ==
                    QueryKeyHash.of(const ['demo', 'notifyOn']),
              );
            },
            child: const Text('Refetch (invalidate)'),
          ),
        ],
      ),
    );
  }
}

// ── Shared shell ─────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
