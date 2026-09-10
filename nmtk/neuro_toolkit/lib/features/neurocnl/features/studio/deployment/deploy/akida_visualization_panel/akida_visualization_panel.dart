import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/services/studio_akida_deploy_service.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_projection_utils.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/workflow_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/akida_visualization_panel/support.dart';

class AkidaVisualizationPanel extends StatefulWidget {
  const AkidaVisualizationPanel({
    super.key,
    required this.sourceBuilder,
    required this.visualization,
    required this.loading,
    required this.physicalHardwareVerified,
    required this.onLayerSelected,
    this.error,
  });

  final Widget Function(StudioResultView view) sourceBuilder;
  final StudioAkidaModelVisualization? visualization;
  final bool loading;
  final String? error;
  final bool physicalHardwareVerified;
  final ValueChanged<int> onLayerSelected;

  @override
  State<AkidaVisualizationPanel> createState() =>
      _AkidaVisualizationPanelState();
}

class _AkidaVisualizationPanelState extends State<AkidaVisualizationPanel> {
  // Local pane-width threshold, not a screen-level breakpoint: this panel is
  // often embedded beside other panes, so it can go narrow well before the
  // window itself crosses NmtkShellTokens.compactBreakpoint.
  static const double _stackedLayoutWidth = 640;
  StudioResultView _view = StudioResultView.architecture;
  late bool _showAkida;

  @override
  void initState() {
    super.initState();
    _showAkida = widget.visualization?.available == true;
  }

  @override
  void didUpdateWidget(covariant AkidaVisualizationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.visualization, widget.visualization) &&
        widget.visualization != null) {
      _showAkida = widget.visualization!.available;
    }
  }

  Widget _sourceSwitch(BuildContext context) {
    return ZetaSegmentedControl<AkidaVisualizationSource>(
      semanticLabel: 'Visualization source',
      selected: _showAkida
          ? AkidaVisualizationSource.akida
          : AkidaVisualizationSource.source,
      onChanged: (value) {
        final akida = value == AkidaVisualizationSource.akida;
        // No Akida replay to show yet: the segment stays inert rather than
        // switching to an empty panel.
        if (akida && widget.visualization == null) return;
        setState(() => _showAkida = akida);
      },
      segments: [
        for (final value in AkidaVisualizationSource.values)
          ZetaButtonSegment<AkidaVisualizationSource>(
            value: value,
            child: Text(value.label, key: Key(value.widgetKey)),
          ),
      ],
    );
  }

  /// One line of metadata, not two stacked banners.
  ///
  /// The page header already states whether the run was on physical hardware;
  /// what this panel adds is where the picture itself comes from.
  Widget _provenanceLine(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final textStyles = Zeta.of(context).textStyles;
    final parts = <String>[
      _showAkida && widget.visualization != null
          ? 'Replayed from the deployed Akida model'
          : 'Rendered from the source run',
      widget.physicalHardwareVerified
          ? 'run on verified hardware'
          : 'runtime reported separately',
    ];
    return SizedBox(
      height: 40,
      child: Align(
        alignment: Alignment.topLeft,
        child: Text(
          parts.join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
        ),
      ),
    );
  }

  Widget _sourceHeader(
    BuildContext context,
    StudioAkidaModelVisualization? visualization,
  ) {
    final layerLabels = visualization == null
        ? const <String>[]
        : _layerLabels(visualization);
    final layerPicker = visualization == null
        ? const SizedBox.shrink()
        : DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              key: const Key('akida-visualization-layer-picker'),
              value: visualization.layerIndex,
              items: [
                for (final (index, layer) in visualization.layers.indexed)
                  DropdownMenuItem<int>(
                    value: layer.index,
                    enabled: layer.visualizable,
                    child: Text('${layer.index}. ${layerLabels[index]}'),
                  ),
              ],
              onChanged: widget.loading
                  ? null
                  : (value) {
                      if (value != null) widget.onLayerSelected(value);
                    },
            ),
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _stackedLayoutWidth) {
          return SizedBox(
            height: 104,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 48, child: _sourceSwitch(context)),
                SizedBox(
                  height: 48,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _showAkida ? layerPicker : null,
                  ),
                ),
              ],
            ),
          );
        }
        return SizedBox(
          height: 48,
          child: Row(
            children: [
              _sourceSwitch(context),
              const Spacer(),
              if (_showAkida) Flexible(child: layerPicker),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final visualization = widget.visualization;
    final sourceChild = widget.sourceBuilder(_view);
    final colors = Zeta.of(context).colors;
    final textStyles = Zeta.of(context).textStyles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sourceHeader(context, visualization),
        const SizedBox(height: 8),
        _provenanceLine(context),
        if (widget.error != null || visualization?.available == false) ...[
          const SizedBox(height: 8),
          Text(
            widget.error ?? visualization!.unavailableReason!,
            key: const Key('akida-visualization-unavailable'),
            style: textStyles.bodySmall.copyWith(color: colors.mainWarning),
          ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: ResultsViewSwitch(
            view: _view,
            onChanged: (view) => setState(() => _view = view),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: !_showAkida
              ? sourceChild
              : widget.loading
              ? const Center(child: CircularProgressIndicator())
              : visualization == null
              ? sourceChild
              : switch (_view) {
                  StudioResultView.architecture => _buildArchitecture(
                    context,
                    visualization,
                  ),
                  StudioResultView.grid => _buildGrid(context, visualization),
                  StudioResultView.raster => _buildRaster(
                    context,
                    visualization,
                  ),
                  StudioResultView.weights => _buildWeights(
                    context,
                    visualization,
                  ),
                  StudioResultView.brainviz => _buildGrid(
                    context,
                    visualization,
                  ),
                },
        ),
      ],
    );
  }

  List<String> _layerLabels(StudioAkidaModelVisualization visualization) {
    return numberLayerLabels(visualization.layers.map((layer) => layer.name));
  }

  Widget _buildArchitecture(
    BuildContext context,
    StudioAkidaModelVisualization visualization,
  ) {
    final colors = Zeta.of(context).colors;
    final styles = Zeta.of(context).textStyles;
    final layerLabels = _layerLabels(visualization);
    return ListView.separated(
      key: const Key('akida-architecture-view'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: visualization.layers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final layer = visualization.layers[index];
        final selected = layer.index == visualization.layerIndex;
        final subtitle = layer.outputShape.isEmpty
            ? 'weights ${layer.weightShape?.join(' × ') ?? 'unavailable'}'
            : 'Output ${layer.outputShape.join(' × ')} · '
                  'weights ${layer.weightShape?.join(' × ') ?? 'unavailable'}';
        return DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? colors.mainPrimary.withValues(alpha: 0.10)
                : colors.surfaceHover,
            border: Border.all(
              color: selected ? colors.mainPrimary : colors.borderDefault,
            ),
            borderRadius: BorderRadius.circular(
              NmtkShellTokens.of(context).radiusMd,
            ),
          ),
          child: ListTile(
            title: Text('${layer.index}. ${layerLabels[index]}'),
            subtitle: Text(
              subtitle,
              style: styles.bodySmall.copyWith(color: colors.mainSubtle),
            ),
            trailing: layer.weightBits == null
                ? null
                : NmtkStatusBadge(
                    label: '${layer.weightBits}-bit',
                    semanticsLabel: '${layer.weightBits}-bit quantized weights',
                  ),
            onTap: layer.visualizable
                ? () => widget.onLayerSelected(layer.index)
                : null,
          ),
        );
      },
    );
  }

  Widget _buildGrid(
    BuildContext context,
    StudioAkidaModelVisualization visualization,
  ) {
    final activity = visualization.activity?.values ?? const <double>[];
    if (activity.isEmpty) {
      return const Center(child: Text('No layer activity.'));
    }
    final maximum = activity.fold<double>(0, math.max);
    final colors = Zeta.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          visualization.mode == StudioAkidaVisualizationMode.sample
              ? 'Direct neuron activation intensity'
              : 'Mean neuron activation across ${visualization.sampleCount} samples',
        ),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.builder(
            key: const Key('akida-activation-grid'),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 34,
              mainAxisSpacing: 3,
              crossAxisSpacing: 3,
            ),
            itemCount: activity.length,
            itemBuilder: (context, index) {
              final normalized = maximum == 0 ? 0.0 : activity[index] / maximum;
              final reading =
                  'Neuron $index: ${formatActivation(activity[index])}';
              return Semantics(
                label: reading,
                child: Tooltip(
                  message: reading,
                  child: ColoredBox(
                    color: Color.lerp(
                      colors.surfaceHover,
                      colors.mainPrimary,
                      normalized.clamp(0.0, 1.0),
                    )!,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        const Text('Neuron index', textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildRaster(
    BuildContext context,
    StudioAkidaModelVisualization visualization,
  ) {
    if (visualization.mode == StudioAkidaVisualizationMode.sample) {
      final activity = visualization.activity?.values ?? const <double>[];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Static neuron versus activation-count plot'),
          const SizedBox(height: 8),
          Expanded(
            child: BarChart(
              key: const Key('akida-sample-activation-plot'),
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                barTouchData: const BarTouchData(enabled: true),
                titlesData: const FlTitlesData(
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    axisNameWidget: Text('Neuron'),
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    axisNameWidget: Text('Activation count'),
                    sideTitles: SideTitles(showTitles: true, reservedSize: 38),
                  ),
                ),
                barGroups: [
                  for (var index = 0; index < activity.length; index++)
                    BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: activity[index],
                          width: activity.length > 128 ? 1 : 3,
                          color: Zeta.of(context).colors.mainPrimary,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    final raster = visualization.raster;
    if (raster == null || raster.shape.length != 2) {
      return const Center(child: Text('No benchmark activity matrix.'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Non-zero Akida activation by evaluation sample'),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            children: [
              const RotatedBox(quarterTurns: 3, child: Text('Neuron')),
              const SizedBox(width: 6),
              Expanded(
                // A painted matrix announces nothing on its own, so the shape
                // and extent go on the node beside it.
                child: Semantics(
                  label:
                      'Activation raster: ${raster.shape[1]} neurons by '
                      '${raster.shape[0]} evaluation samples. Brighter cells '
                      'are more active.',
                  child: CustomPaint(
                    key: const Key('akida-benchmark-raster'),
                    painter: AkidaRasterPainter(
                      values: raster.values,
                      samples: raster.shape[0],
                      neurons: raster.shape[1],
                      color: Zeta.of(context).colors.mainPrimary,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Text('Sample index', textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildWeights(
    BuildContext context,
    StudioAkidaModelVisualization visualization,
  ) {
    final weights = visualization.weights;
    if (weights == null || weights.shape.length < 2) {
      return const Center(child: Text('No quantized weights for this layer.'));
    }
    final inputCount = weights.shape
        .take(weights.shape.length - 1)
        .fold<int>(1, (total, dimension) => total * dimension);
    final neuronCount = weights.shape.last;
    final values = weights.values;
    final maximum = values.fold<double>(
      0,
      (value, next) => math.max(value, next.abs()),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Exact deployed integer weights · ${visualization.weightBits ?? '?'}-bit · '
          '$inputCount inputs × $neuronCount neurons',
          key: const Key('akida-weight-provenance'),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            children: [
              const RotatedBox(quarterTurns: 3, child: Text('Neuron')),
              const SizedBox(width: 6),
              Expanded(
                child: Semantics(
                  label:
                      'Weight matrix: $inputCount inputs by $neuronCount '
                      'neurons, '
                      '${visualization.weightBits ?? 'unknown'}-bit integers '
                      'in the range ±${maximum.toStringAsFixed(0)}. Blue is '
                      'negative, red is positive.',
                  child: CustomPaint(
                    key: const Key('akida-exact-weight-grid'),
                    painter: AkidaWeightMatrixPainter(
                      values: values,
                      inputs: inputCount,
                      neurons: neuronCount,
                      maximum: maximum,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Text('Input', textAlign: TextAlign.center),
      ],
    );
  }
}
