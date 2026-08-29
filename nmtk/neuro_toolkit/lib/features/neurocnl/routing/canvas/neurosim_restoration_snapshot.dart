import 'dart:convert';

import 'package:neuro_toolkit/features/neurocnl/routing/canvas/neurosim_route_state.dart';

class NeurosimRestorationSnapshot {
  const NeurosimRestorationSnapshot({
    this.version = 1,
    this.workspaceKey = 'neurosim',
    required this.primaryRoute,
    required this.payload,
  });

  final int version;
  final String workspaceKey;
  final String primaryRoute;
  final Map<String, dynamic> payload;

  factory NeurosimRestorationSnapshot.fromRouteState(NeurosimRouteState state) {
    return NeurosimRestorationSnapshot(
      primaryRoute: _targetId(state.target),
      payload: <String, dynamic>{
        'projectId': state.selectedProjectId,
        'selectedNodeId': state.selectedNodeId,
        'selectedEdgeId': state.selectedEdgeId,
        'showPreview': state.showPreview,
        'previewCurrentTime': state.previewCurrentTime,
        'previewResults': state.previewResults,
      },
    );
  }

  factory NeurosimRestorationSnapshot.fromJson(Map<String, dynamic> json) {
    return NeurosimRestorationSnapshot(
      version: (json['version'] as num?)?.toInt() ?? 1,
      workspaceKey: json['workspaceKey'] as String? ?? 'neurosim',
      primaryRoute: json['primaryRoute'] as String? ?? 'project_canvas',
      payload: Map<String, dynamic>.from(
        json['payload'] as Map? ?? const <String, dynamic>{},
      ),
    );
  }

  factory NeurosimRestorationSnapshot.fromEncoded(String encoded) {
    return NeurosimRestorationSnapshot.fromJson(
      jsonDecode(encoded) as Map<String, dynamic>,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'version': version,
      'workspaceKey': workspaceKey,
      'primaryRoute': primaryRoute,
      'payload': payload,
    };
  }

  String encode() => jsonEncode(toJson());

  NeurosimRouteState toRouteState() {
    return NeurosimRouteState(
      target: _targetFromString(primaryRoute),
      selectedProjectId: payload['projectId'] as String?,
      selectedNodeId: payload['selectedNodeId'] as String?,
      selectedEdgeId: payload['selectedEdgeId'] as String?,
      showPreview: payload['showPreview'] as bool? ?? false,
      previewCurrentTime:
          (payload['previewCurrentTime'] as num?)?.toDouble() ?? 0.0,
      previewResults: payload['previewResults'] is Map
          ? Map<String, dynamic>.from(payload['previewResults'] as Map)
          : null,
    );
  }

  static String _targetId(NeurosimRouteTarget target) {
    switch (target) {
      case NeurosimRouteTarget.canvas:
        return 'project_canvas';
      case NeurosimRouteTarget.projectList:
        return 'project_list';
      case NeurosimRouteTarget.preview:
        return 'preview';
      case NeurosimRouteTarget.sweep:
        return 'sweep';
      case NeurosimRouteTarget.export:
        return 'export';
    }
  }

  static NeurosimRouteTarget _targetFromString(String value) {
    switch (value) {
      case 'project_list':
        return NeurosimRouteTarget.projectList;
      case 'preview':
        return NeurosimRouteTarget.preview;
      case 'sweep':
        return NeurosimRouteTarget.sweep;
      case 'export':
        return NeurosimRouteTarget.export;
      case 'project_canvas':
      default:
        return NeurosimRouteTarget.canvas;
    }
  }
}
