import 'dart:async';

import 'package:flutter/material.dart';
import 'package:swrly/swrly.dart';

import 'stress/frame_stats.dart';

/// A "harsh" performance harness for swrly that end users can run themselves.
///
/// Two independent stressors:
///  1. **Cache-ops micro-benchmark** — inserts N entries, reads them back, then
///     fans out a single [QueryClient.invalidateQueries] across all of them,
///     reporting set/get ops/sec and invalidation time.
///  2. **Live subscription stress** — mounts M real [QueryBuilder]s on their own
///     [QueryClient], then churns them with periodic invalidation so every
///     subscriber refetches + rebuilds each round while [FrameStatsPanel]
///     reports FPS / build / raster / jank.
class StressTestScreen extends StatefulWidget {
  const StressTestScreen({super.key});

  @override
  State<StressTestScreen> createState() => _StressTestScreenState();
}

class _StressTestScreenState extends State<StressTestScreen> {
  final FrameStatsController _stats = FrameStatsController();

  /// Dedicated client so the harness never pollutes the demo's singleton cache.
  final QueryClient _client = QueryClient(
    defaultStaleTime: Duration.zero,
    defaultCacheTime: const Duration(minutes: 10),
  );

  double _liveQueries = 50;
  bool _autoInvalidate = true;
  Timer? _churn;
  int _round = 0;

  int _benchN = 50000;
  String? _benchResult;
  bool _benchRunning = false;

  @override
  void initState() {
    super.initState();
    _stats.start();
    _startChurn();
  }

  @override
  void dispose() {
    _stats.stop();
    _churn?.cancel();
    _client.clear();
    super.dispose();
  }

  void _startChurn() {
    _churn?.cancel();
    if (!_autoInvalidate) return;
    _churn = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _round++;
      // Refetch every mounted ['live', i] subscriber → state churn → rebuilds.
      _client.invalidateQueries(const ['live']);
    });
  }

  Future<int> _fetch(int i) async {
    // Trivial async so the refetch path (loading → success) is exercised.
    return _round * 1000 + i;
  }

  Future<void> _runBenchmark() async {
    setState(() {
      _benchRunning = true;
      _benchResult = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 16));

    final n = _benchN;
    final bench = QueryClient(
      defaultStaleTime: Duration.zero,
      defaultCacheTime: const Duration(minutes: 30),
    );
    try {
      final insertSw = Stopwatch()..start();
      for (var i = 0; i < n; i++) {
        bench.setQueryData(['bench', i], i);
      }
      insertSw.stop();

      var sink = 0;
      final readSw = Stopwatch()..start();
      for (var i = 0; i < n; i++) {
        sink += bench.getQueryData<int>(['bench', i]) ?? 0;
      }
      readSw.stop();

      final invSw = Stopwatch()..start();
      bench.invalidateQueries(const ['bench'], refetch: false);
      invSw.stop();

      final setOps = n / (insertSw.elapsedMicroseconds / 1e6);
      final getOps = n / (readSw.elapsedMicroseconds / 1e6);
      setState(() {
        _benchResult = '$n entries  (sink=$sink)\n'
            'setQueryData: ${_fmtOps(setOps)} ops/sec '
            '(${insertSw.elapsedMilliseconds} ms)\n'
            'getQueryData: ${_fmtOps(getOps)} ops/sec '
            '(${readSw.elapsedMilliseconds} ms)\n'
            'invalidate fan-out over $n: '
            '${(invSw.elapsedMicroseconds / 1000).toStringAsFixed(2)} ms';
      });
    } finally {
      bench.clear();
      setState(() => _benchRunning = false);
    }
  }

  static String _fmtOps(double ops) {
    if (ops >= 1e6) return '${(ops / 1e6).toStringAsFixed(2)}M';
    if (ops >= 1e3) return '${(ops / 1e3).toStringAsFixed(1)}K';
    return ops.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final n = _liveQueries.round();
    return Scaffold(
      appBar: AppBar(title: const Text('Stress test')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: FrameStatsPanel(controller: _stats),
          ),
          _controls(context, n),
          const Divider(height: 1),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 56,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: n,
              itemBuilder: (context, i) => _LiveCell(client: _client, index: i, fetch: _fetch),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(BuildContext context, int n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Live queries'),
              Expanded(
                child: Slider(
                  value: _liveQueries,
                  min: 0,
                  max: 300,
                  divisions: 30,
                  label: '$n',
                  onChanged: (v) => setState(() => _liveQueries = v),
                ),
              ),
              SizedBox(width: 44, child: Text('$n', textAlign: TextAlign.end)),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Auto-invalidate (2 Hz)'),
            subtitle: const Text('refetch every subscriber each round'),
            value: _autoInvalidate,
            onChanged: (v) => setState(() {
              _autoInvalidate = v;
              _startChurn();
            }),
          ),
          const Divider(height: 8),
          Row(
            children: [
              const Text('Cache benchmark'),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: _benchN,
                items: const [
                  DropdownMenuItem(value: 10000, child: Text('10K')),
                  DropdownMenuItem(value: 50000, child: Text('50K')),
                  DropdownMenuItem(value: 100000, child: Text('100K')),
                ],
                onChanged: _benchRunning
                    ? null
                    : (v) => setState(() => _benchN = v ?? 50000),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: _benchRunning ? null : _runBenchmark,
                child: _benchRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Run'),
              ),
            ],
          ),
          if (_benchResult != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_benchResult!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
            ),
        ],
      ),
    );
  }
}

/// One live query cell — a real [QueryBuilder] subscribed to `['live', index]`.
class _LiveCell extends StatelessWidget {
  const _LiveCell({required this.client, required this.index, required this.fetch});

  final QueryClient client;
  final int index;
  final Future<int> Function(int) fetch;

  @override
  Widget build(BuildContext context) {
    return QueryBuilder<int>(
      client: client,
      queryKey: ['live', index],
      staleTime: Duration.zero,
      queryFn: () => fetch(index),
      builder: (context, state, refetch) {
        final scheme = Theme.of(context).colorScheme;
        final bg = state.isFetching
            ? scheme.tertiaryContainer
            : state.hasData
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest;
        return Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            state.hasData ? '${state.data! % 1000}' : '·',
            style: const TextStyle(fontSize: 10),
          ),
        );
      },
    );
  }
}
