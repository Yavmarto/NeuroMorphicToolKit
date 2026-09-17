enum NeurosimRouteTarget { canvas, projectList, preview, sweep, export }

class NeurosimRouteState {
  const NeurosimRouteState({
    required this.target,
    this.selectedProjectId,
    this.selectedNodeId,
    this.selectedEdgeId,
    this.showPreview = false,
    this.previewCurrentTime = 0.0,
    this.previewResults,
  });

  final NeurosimRouteTarget target;
  final String? selectedProjectId;
  final String? selectedNodeId;
  final String? selectedEdgeId;
  final bool showPreview;
  final double previewCurrentTime;
  final Map<String, dynamic>? previewResults;

  bool get isCanvasSurface =>
      target == NeurosimRouteTarget.canvas ||
      target == NeurosimRouteTarget.preview;

  NeurosimRouteState copyWith({
    NeurosimRouteTarget? target,
    String? selectedProjectId,
    bool clearSelectedProjectId = false,
    String? selectedNodeId,
    bool clearSelectedNodeId = false,
    String? selectedEdgeId,
    bool clearSelectedEdgeId = false,
    bool? showPreview,
    double? previewCurrentTime,
    Map<String, dynamic>? previewResults,
    bool clearPreviewResults = false,
  }) {
    return NeurosimRouteState(
      target: target ?? this.target,
      selectedProjectId: clearSelectedProjectId
          ? null
          : (selectedProjectId ?? this.selectedProjectId),
      selectedNodeId: clearSelectedNodeId
          ? null
          : (selectedNodeId ?? this.selectedNodeId),
      selectedEdgeId: clearSelectedEdgeId
          ? null
          : (selectedEdgeId ?? this.selectedEdgeId),
      showPreview: showPreview ?? this.showPreview,
      previewCurrentTime: previewCurrentTime ?? this.previewCurrentTime,
      previewResults: clearPreviewResults
          ? null
          : (previewResults ?? this.previewResults),
    );
  }
}
