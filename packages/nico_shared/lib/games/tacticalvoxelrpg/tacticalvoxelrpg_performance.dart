part of 'tacticalvoxelrpg_view.dart';

/// Collects low-volume frame timing and tactical widget rebuild summaries.
class _TacticalPerformanceTracker {
  _TacticalPerformanceTracker({
    required this.sink,
    required this.currentView,
    required this.devicePixelRatio,
  });

  final void Function(Map<String, Object?> event)? sink;
  final Map<String, Object?> Function() currentView;
  final double Function() devicePixelRatio;
  final Stopwatch _windowClock = Stopwatch()..start();
  Timer? _timer;
  int _viewBuilds = 0;
  int _frameCount = 0;
  int _slowBuildFrames = 0;
  int _slowRasterFrames = 0;
  int _maxBuildMicros = 0;
  int _maxRasterMicros = 0;
  int _sumBuildMicros = 0;
  int _sumRasterMicros = 0;
  int _boardBuilds = 0;
  int _boardBuildMicros = 0;

  void start() {
    if (sink == null) return;
    WidgetsBinding.instance.addTimingsCallback(_onFrameTimings);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => flush());
  }

  void dispose() {
    if (sink == null) return;
    WidgetsBinding.instance.removeTimingsCallback(_onFrameTimings);
    _timer?.cancel();
    flush();
  }

  void recordViewBuild() {
    if (sink != null) _viewBuilds++;
  }

  void recordBoardBuild(int elapsedMicros) {
    if (sink == null) return;
    _boardBuilds++;
    _boardBuildMicros += elapsedMicros;
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final buildMicros = timing.buildDuration.inMicroseconds;
      final rasterMicros = timing.rasterDuration.inMicroseconds;
      _frameCount++;
      _sumBuildMicros += buildMicros;
      _sumRasterMicros += rasterMicros;
      if (buildMicros > _maxBuildMicros) _maxBuildMicros = buildMicros;
      if (rasterMicros > _maxRasterMicros) _maxRasterMicros = rasterMicros;
      if (buildMicros > 16667) _slowBuildFrames++;
      if (rasterMicros > 16667) _slowRasterFrames++;
    }
  }

  void flush() {
    final log = sink;
    if (log == null) return;
    final view = currentView();
    final units = _objects(view['units']);
    final windowDurationMs = _windowClock.elapsedMilliseconds;
    log({
      'event': 'tactical_perf_summary',
      'phase': view['phase'],
      'windowDurationMs': windowDurationMs,
      'frames': _frameCount,
      'fps': windowDurationMs == 0 ? 0 : _frameCount * 1000 / windowDurationMs,
      'slowBuildFramesOver16_7ms': _slowBuildFrames,
      'slowRasterFramesOver16_7ms': _slowRasterFrames,
      'avgBuildMs': _frameCount == 0 ? 0 : _sumBuildMicros / _frameCount / 1000,
      'maxBuildMs': _maxBuildMicros / 1000,
      'avgRasterMs': _frameCount == 0
          ? 0
          : _sumRasterMicros / _frameCount / 1000,
      'maxRasterMs': _maxRasterMicros / 1000,
      'viewBuilds': _viewBuilds,
      'boardBuilds': _boardBuilds,
      'avgBoardWidgetBuildMs': _boardBuilds == 0
          ? 0
          : _boardBuildMicros / _boardBuilds / 1000,
      'mapWidth': view['width'],
      'mapHeight': view['height'],
      'mapTileCount': _objects(view['tiles']).length,
      'unitCount': units.length,
      'trapCount': _objects(view['traps']).length,
      'devicePixelRatio': devicePixelRatio(),
      'debugMode': kDebugMode,
      'profileMode': kProfileMode,
    });
    _viewBuilds = 0;
    _frameCount = 0;
    _slowBuildFrames = 0;
    _slowRasterFrames = 0;
    _maxBuildMicros = 0;
    _maxRasterMicros = 0;
    _sumBuildMicros = 0;
    _sumRasterMicros = 0;
    _boardBuilds = 0;
    _boardBuildMicros = 0;
    _windowClock
      ..reset()
      ..start();
  }
}
