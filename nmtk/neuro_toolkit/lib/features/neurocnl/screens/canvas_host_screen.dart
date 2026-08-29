import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/routing/canvas/canvas_shell_adapter.dart';

class CanvasHostScreen extends StatelessWidget {
  const CanvasHostScreen.canvas({super.key, this.projectId})
    : _target = NeurosimRouteTarget.canvas;

  const CanvasHostScreen.projects({super.key, this.projectId})
    : _target = NeurosimRouteTarget.projectList;

  const CanvasHostScreen.sweep({super.key, this.projectId})
    : _target = NeurosimRouteTarget.sweep;

  const CanvasHostScreen.export({super.key, this.projectId})
    : _target = NeurosimRouteTarget.export;

  final String? projectId;
  final NeurosimRouteTarget _target;

  @override
  Widget build(BuildContext context) {
    return NeuroSimShellAdapter(
      initialSnapshot: NeurosimRestorationSnapshot.fromRouteState(
        NeurosimRouteState(target: _target, selectedProjectId: projectId),
      ).encode(),
    );
  }
}
