library;

/// Sample vs benchmark on the deploy result surface.
///
/// Carries its own label because the segmented control excludes its child
/// semantics and announces `value.toString()`.
enum StudioResultSurfaceView {
  sample,
  benchmark;

  String get label => switch (this) {
    StudioResultSurfaceView.sample => 'Sample',
    StudioResultSurfaceView.benchmark => 'Benchmark',
  };

  @override
  String toString() => label;
}
