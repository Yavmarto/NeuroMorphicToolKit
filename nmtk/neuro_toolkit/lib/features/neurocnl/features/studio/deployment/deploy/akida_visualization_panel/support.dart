/// Which run the visualization panel is replaying. Named rather than a `bool`
/// so the segmented control announces 'Akida replay' instead of 'true' — it
/// excludes its child semantics and exposes `value.toString()`.
enum AkidaVisualizationSource {
  akida,
  source;

  String get label => switch (this) {
    AkidaVisualizationSource.akida => 'Akida replay',
    AkidaVisualizationSource.source => 'Source run',
  };

  String get widgetKey => switch (this) {
    AkidaVisualizationSource.akida => 'akida-data-source',
    AkidaVisualizationSource.source => 'source-run-data-source',
  };

  @override
  String toString() => label;
}
