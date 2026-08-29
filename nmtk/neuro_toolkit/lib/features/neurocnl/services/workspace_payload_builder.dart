import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/simulation_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/workspace_file.dart';

Map<String, dynamic> buildCompleteWorkspacePayload({
  required WorkspaceState workspace,
  required CanvasState canvas,
  required SimulationState simulation,
  Map<String, dynamic>? resultSnapshot,
}) {
  final payload = <String, dynamic>{
    'version': 1,
    'workspace': workspace.toJson(),
    'canvas': <String, dynamic>{
      'pipeline': canvas.pipeline.toJson(),
      'pipelinePhases': canvas.pipelinePhases.toJson(),
      'simulationResults': simulation.results?.toJson(),
      'simulationCurrentTime': simulation.currentTime,
      'nodeLayout': <String, dynamic>{
        for (final node in canvas.graph.nodes)
          node.id: <String, dynamic>{
            'x': node.position[0],
            'y': node.position[1],
            'width': node.width,
            'height': node.height,
            'isVisible': node.isVisible,
          },
      },
    },
  };
  if (resultSnapshot != null) {
    payload['resultSnapshot'] = resultSnapshot;
  }
  return payload;
}
