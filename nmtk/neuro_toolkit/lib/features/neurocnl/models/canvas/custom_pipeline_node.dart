import 'package:neuro_toolkit/features/neurocnl/models/canvas/component.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';

/// A palette entry backed either by a built-in DAG type or by a saved custom
/// component that delegates to that type.
class PipelineNodePaletteItem {
  const PipelineNodePaletteItem({required this.type, this.component});

  final PipelineDagNodeType type;
  final ComponentBlock? component;

  String get id => component?.id ?? type.name;
  String get label => component?.name ?? type.label;
  String? get customComponentId => component?.id;
  Map<String, dynamic> get defaultParameters => component == null
      ? type.defaultParameters
      : <String, dynamic>{
          for (final parameter in component!.parameters)
            parameter.name: parameter.defaultValue,
        };
}

List<PipelineNodePaletteItem> pipelinePaletteItems({
  required PipelinePhaseId phase,
  required Set<String> platforms,
  required Iterable<ComponentBlock> components,
}) {
  final builtIns = pipelineNodeTypesFor(
    phase,
    platforms,
  ).map((type) => PipelineNodePaletteItem(type: type)).toList();
  final context = switch (phase) {
    PipelinePhaseId.train => 'training',
    PipelinePhaseId.eval => 'eval',
    PipelinePhaseId.infer => 'inference',
  };
  final allowedTypes = builtIns.map((item) => item.type).toSet();
  for (final component in components) {
    if (!component.isCustom ||
        component.basePipelineType == null ||
        !component.canvasContexts.contains(context)) {
      continue;
    }
    final type = PipelineDagNodeType.values
        .where((candidate) => candidate.name == component.basePipelineType)
        .firstOrNull;
    if (type == null || !allowedTypes.contains(type)) continue;
    builtIns.add(PipelineNodePaletteItem(type: type, component: component));
  }
  return builtIns;
}
