import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Immutable snapshot of collected frame-timing metrics.
class FrameStats {
  const FrameStats({
    required this.frames,
    required this.elapsed,
    required this.avgFps,
    required this.avgBuildMs,
    required this.avgRasterMs,
    required this.p95BuildMs,
    required this.worstBuildMs,
    required this.worstRasterMs,
    required this.jankFrames,
    required this.jankPercent,
  });

  final int frames;
  final Duration elapsed;
  final double avgFps;
  final double avgBuildMs;
  final double avgRasterMs;
  final double p95BuildMs;
  final double worstBuildMs;
  final double worstRasterMs;
  final int jankFrames;
  final double jankPercent;

  static const empty = FrameStats(
    frames: 0,
    elapsed: Duration.zero,
    avgFps: 0,
    avgBuildMs: 0,
    avgRasterMs: 0,
    p95BuildMs: 0,
    worstBuildMs: 0,
    worstRasterMs: 0,
    jankFrames: 0,
    jankPercent: 0,
  );
}

/// Collects [FrameTiming]s from the engine and computes live perf metrics.
///
/// Call [start] to hook [SchedulerBinding.addTimingsCallback]; it accumulates
/// cheaply in the callback (no per-frame rebuilds). Read [stats] on a timer —
/// see [FrameStatsPanel] — so the readout's own repaints don't pollute the
/// timings being measured.
class FrameStatsController {
  FrameStatsController({this.budgetMs = 16.7, this.rollingWindow = 300});

  /// A frame counts as "janky" when its build or raster phase exceeds this
  /// many milliseconds (16.7ms ≈ the 60fps budget).
  final double budgetMs;

  /// How many recent frames feed the rolling averages / p95.
  final int rollingWindow;

  final Queue<double> _buildMs = Queue<double>();
  final Queue<double> _rasterMs = Queue<double>();
  final Stopwatch _stopwatch = Stopwatch();

  int _frames = 0;
  int _jank = 0;
  double _worstBuild = 0;
  double _worstRaster = 0;
  bool _recording = false;

  bool get recording => _recording;

  void start() {
    if (_recording) return;
    reset();
    _recording = true;
    _stopwatch.start();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void stop() {
    if (!_recording) return;
    _recording = false;
    _stopwatch.stop();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  void reset() {
    _buildMs.clear();
    _rasterMs.clear();
    _stopwatch
      ..stop()
      ..reset();
    _frames = 0;
    _jank = 0;
    _worstBuild = 0;
    _worstRaster = 0;
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final build = t.buildDuration.inMicroseconds / 1000.0;
      final raster = t.rasterDuration.inMicroseconds / 1000.0;
      _frames++;
      if (build > _worstBuild) _worstBuild = build;
      if (raster > _worstRaster) _worstRaster = raster;
      if (build > budgetMs || raster > budgetMs) _jank++;
      _buildMs.addLast(build);
      _rasterMs.addLast(raster);
      if (_buildMs.length > rollingWindow) _buildMs.removeFirst();
      if (_rasterMs.length > rollingWindow) _rasterMs.removeFirst();
    }
  }

  FrameStats get stats {
    final elapsed = _stopwatch.elapsed;
    final secs = elapsed.inMicroseconds / 1e6;
    return FrameStats(
      frames: _frames,
      elapsed: elapsed,
      avgFps: secs > 0 ? _frames / secs : 0.0,
      avgBuildMs: _avg(_buildMs),
      avgRasterMs: _avg(_rasterMs),
      p95BuildMs: _p95(_buildMs),
      worstBuildMs: _worstBuild,
      worstRasterMs: _worstRaster,
      jankFrames: _jank,
      jankPercent: _frames > 0 ? _jank / _frames * 100 : 0,
    );
  }

  static double _avg(Queue<double> q) {
    if (q.isEmpty) return 0;
    var s = 0.0;
    for (final v in q) {
      s += v;
    }
    return s / q.length;
  }

  static double _p95(Queue<double> q) {
    if (q.isEmpty) return 0;
    final sorted = q.toList()..sort();
    final idx = ((sorted.length - 1) * 0.95).round();
    return sorted[idx];
  }
}

/// Live-updating readout of a [FrameStatsController].
///
/// Polls at 4 Hz on a timer so the panel's own rebuilds stay out of the frame
/// timings it reports.
class FrameStatsPanel extends StatefulWidget {
  const FrameStatsPanel({super.key, required this.controller});

  final FrameStatsController controller;

  @override
  State<FrameStatsPanel> createState() => _FrameStatsPanelState();
}

class _FrameStatsPanelState extends State<FrameStatsPanel> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.controller.stats;
    final rec = widget.controller.recording;
    final fpsColor = s.avgFps >= 55
        ? Colors.green
        : s.avgFps >= 40
            ? Colors.orange
            : Colors.red;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(rec ? Icons.fiber_manual_record : Icons.stop_circle_outlined,
                    size: 16, color: rec ? Colors.red : Colors.grey),
                const SizedBox(width: 6),
                Text(rec ? 'Recording' : 'Idle',
                    style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                Text('${s.frames} frames · ${(s.elapsed.inMilliseconds / 1000).toStringAsFixed(1)}s',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Metric('Avg FPS', s.avgFps.toStringAsFixed(1), color: fpsColor),
                _Metric('Build (avg)', '${s.avgBuildMs.toStringAsFixed(1)} ms'),
                _Metric('Raster (avg)', '${s.avgRasterMs.toStringAsFixed(1)} ms'),
                _Metric('Build p95', '${s.p95BuildMs.toStringAsFixed(1)} ms'),
                _Metric('Worst build', '${s.worstBuildMs.toStringAsFixed(1)} ms'),
                _Metric('Worst raster', '${s.worstRasterMs.toStringAsFixed(1)} ms'),
                _Metric('Jank frames', '${s.jankFrames} (${s.jankPercent.toStringAsFixed(1)}%)',
                    color: s.jankPercent > 5 ? Colors.orange : null),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 104,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(value,
              style: theme.textTheme.titleMedium?.copyWith(
                  color: color, fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}
