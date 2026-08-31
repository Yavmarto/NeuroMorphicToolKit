import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/workflow_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/results_step/neuron_detail_sheet.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/results_step/support.dart' show rdbuColor;

class WeightsViewTab extends ConsumerStatefulWidget {
  const WeightsViewTab({
    super.key,
    required this.jobId,
    this.unavailableMessage,
  });

  final String? jobId;
  final String? unavailableMessage;

  @override
  ConsumerState<WeightsViewTab> createState() => _WeightsViewTabState();
}

class _WeightsViewTabState extends ConsumerState<WeightsViewTab> {
  WeightData? _data;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant WeightsViewTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jobId != widget.jobId ||
        oldWidget.unavailableMessage != widget.unavailableMessage) {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    if (widget.jobId == null) {
      setState(() {
        _data = null;
        _isLoading = false;
        _error = widget.unavailableMessage;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final raw = await client.getVisualizationImage(
        widget.jobId!,
        'weight_data',
      );
      if (!mounted) return;
      if (raw == null) {
        setState(() {
          _isLoading = false;
          _error =
              'No weight data captured — regenerate the notebook and re-run.';
        });
        return;
      }
      final data = WeightData.tryParse(raw);
      setState(() {
        _isLoading = false;
        _data = data;
        _error = data == null ? 'Weight data format unrecognised.' : null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error =
              'This weight artifact is no longer available. Run again to '
              'regenerate details.';
        });
      }
    }
  }

  void _openDetail(BuildContext context, int neuronIndex) {
    final data = _data!;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NeuronDetailSheet(
        neuronIndex: neuronIndex,
        weights: data.neuronWeights(neuronIndex),
        side: data.side,
        vmax: data.vmax,
        nInputs: data.nInputs,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null || _data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                ZetaIcons.grid_view,
                size: 40,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                _error ?? 'No weight data available.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final data = _data!;
    // Aim for tiles of ~52 px logical pixels in the grid.
    const tileTarget = 52.0;
    const padding = 24.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - padding * 2;
        final nCols = (availableWidth / tileTarget).floor().clamp(4, 32);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                  Text(
                    '${data.nNeurons} neurons · ${data.side}×${data.side} receptive fields',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Tap a tile to inspect',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            // Colour scale strip
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Row(
                children: [
                  Text(
                    '−${data.vmax.toStringAsFixed(2)}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontSize: 9),
                  ),
                  Expanded(
                    child: Container(
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            rdbuColor(-data.vmax, data.vmax),
                            rdbuColor(0, data.vmax),
                            rdbuColor(data.vmax, data.vmax),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(
                          NmtkShellTokens.of(context).radiusChip,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    '+${data.vmax.toStringAsFixed(2)}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontSize: 9),
                  ),
                ],
              ),
            ),
            // Tile grid
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: nCols,
                  mainAxisSpacing: 3,
                  crossAxisSpacing: 3,
                  childAspectRatio: 1,
                ),
                itemCount: data.nNeurons,
                itemBuilder: (context, i) => GestureDetector(
                  onTap: () => _openDetail(context, i),
                  child: Tooltip(
                    message: 'Neuron $i',
                    waitDuration: const Duration(milliseconds: 600),
                    child: CustomPaint(
                      painter: WeightTilePainter(
                        weights: data.neuronWeights(i),
                        side: data.side,
                        vmax: data.vmax,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
