import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';

/// Pre-defined parameter configurations for quick tuning.
const _presets = <String, Map<String, double>>{
  'Fast Reflex': {
    'Threshold': 0.5,
    'Refractory Period': 0.001,
    'Time Constant (\u03c4)': 0.005,
    'Synaptic Weight': 2.0,
  },
  'Slow Integration': {
    'Threshold': 2.0,
    'Refractory Period': 0.01,
    'Time Constant (\u03c4)': 0.05,
    'Synaptic Weight': 0.5,
  },
  'Balanced': {
    'Threshold': 1.0,
    'Refractory Period': 0.002,
    'Time Constant (\u03c4)': 0.02,
    'Synaptic Weight': 1.0,
  },
};

/// Parameter explorer with sliders for tuning numeric values in the spec.
///
/// Implements Epic 6: Parameter Explorer — auto-extracts numeric parameters
/// from the CNL spec and provides sliders to adjust them in real-time.
/// US-21: Parameter presets for common configurations.
class ParameterExplorer extends ConsumerStatefulWidget {
  const ParameterExplorer({super.key});

  @override
  ConsumerState<ParameterExplorer> createState() => _ParameterExplorerState();
}

class _ParameterExplorerState extends ConsumerState<ParameterExplorer> {
  @override
  Widget build(BuildContext context) {
    final spec = ref.watch(specTextProvider);
    final params = _extractParameters(spec);

    if (params.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ZetaIcons.tune,
              size: 48,
              color: Zeta.of(context).colors.mainSubtle.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              'Parameters will appear here\nwhen numeric values are found in the spec.',
              textAlign: TextAlign.center,
              style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                color: Zeta.of(context).colors.mainSubtle,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _Header(onPresetSelected: (preset) => _applyPreset(preset, params)),
        const SizedBox(height: 12),
        ...params.map(
          (p) => _ParameterSlider(
            param: p,
            onChanged: (newValue) => _updateParameter(p, newValue),
          ),
        ),
      ],
    );
  }

  /// Apply a preset to all matching parameters.
  void _applyPreset(String presetName, List<_ExtractedParam> currentParams) {
    final preset = _presets[presetName];
    if (preset == null) return;

    for (final param in currentParams) {
      final presetValue = preset[param.name];
      if (presetValue != null) {
        _updateParameter(param, presetValue.clamp(param.min, param.max));
      }
    }
  }

  /// Extract numeric parameters from CNL spec text.
  List<_ExtractedParam> _extractParameters(String spec) {
    final params = <_ExtractedParam>[];
    final lines = spec.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      // Pattern: "exceeds <number>" → threshold
      final thresholdMatch = RegExp(r'exceeds\s+(\d+\.?\d*)').firstMatch(line);
      if (thresholdMatch != null) {
        params.add(
          _ExtractedParam(
            name: 'Threshold',
            value: double.parse(thresholdMatch.group(1)!),
            min: 0.0,
            max: 5.0,
            unit: '',
            lineIndex: i,
            matchStart: thresholdMatch.start,
            matchEnd: thresholdMatch.end,
            pattern: 'exceeds',
          ),
        );
      }

      // Pattern: "refractory period of <number> seconds"
      final refractoryMatch = RegExp(
        r'refractory period of\s+(\d+\.?\d*)\s+seconds',
      ).firstMatch(line);
      if (refractoryMatch != null) {
        params.add(
          _ExtractedParam(
            name: 'Refractory Period',
            value: double.parse(refractoryMatch.group(1)!),
            min: 0.0001,
            max: 0.05,
            unit: 's',
            lineIndex: i,
            matchStart: refractoryMatch.start,
            matchEnd: refractoryMatch.end,
            pattern: 'refractory period of',
          ),
        );
      }

      // Pattern: "time constant of <number> seconds"
      final tauMatch = RegExp(
        r'time constant of\s+(\d+\.?\d*)\s+seconds',
      ).firstMatch(line);
      if (tauMatch != null) {
        params.add(
          _ExtractedParam(
            name: 'Time Constant (τ)',
            value: double.parse(tauMatch.group(1)!),
            min: 0.001,
            max: 0.1,
            unit: 's',
            lineIndex: i,
            matchStart: tauMatch.start,
            matchEnd: tauMatch.end,
            pattern: 'time constant of',
          ),
        );
      }

      // Pattern: "synaptic weight of <number>"
      final weightMatch = RegExp(
        r'synaptic weight of\s+(\d+\.?\d*)',
      ).firstMatch(line);
      if (weightMatch != null) {
        params.add(
          _ExtractedParam(
            name: 'Synaptic Weight',
            value: double.parse(weightMatch.group(1)!),
            min: 0.0,
            max: 10.0,
            unit: '',
            lineIndex: i,
            matchStart: weightMatch.start,
            matchEnd: weightMatch.end,
            pattern: 'synaptic weight of',
          ),
        );
      }

      // Pattern: "using <number> neurons"
      final popMatch = RegExp(r'using\s+(\d+)\s+neurons').firstMatch(line);
      if (popMatch != null) {
        params.add(
          _ExtractedParam(
            name: 'Population Size',
            value: double.parse(popMatch.group(1)!),
            min: 1,
            max: 1000,
            unit: 'neurons',
            lineIndex: i,
            matchStart: popMatch.start,
            matchEnd: popMatch.end,
            pattern: 'using',
            isInteger: true,
          ),
        );
      }
    }

    return params;
  }

  void _updateParameter(_ExtractedParam param, double newValue) {
    final spec = ref.read(specTextProvider);
    final lines = spec.split('\n');

    if (param.lineIndex >= lines.length) return;

    final line = lines[param.lineIndex];
    final newValueStr = param.isInteger
        ? newValue.round().toString()
        : newValue.toStringAsFixed(
            newValue == newValue.roundToDouble() ? 1 : 4,
          );

    // Replace the numeric value in the line
    String newLine;
    if (param.pattern == 'exceeds') {
      newLine = line.replaceFirst(
        RegExp(r'exceeds\s+\d+\.?\d*'),
        'exceeds $newValueStr',
      );
    } else if (param.pattern == 'refractory period of') {
      newLine = line.replaceFirst(
        RegExp(r'refractory period of\s+\d+\.?\d*'),
        'refractory period of $newValueStr',
      );
    } else if (param.pattern == 'time constant of') {
      newLine = line.replaceFirst(
        RegExp(r'time constant of\s+\d+\.?\d*'),
        'time constant of $newValueStr',
      );
    } else if (param.pattern == 'synaptic weight of') {
      newLine = line.replaceFirst(
        RegExp(r'synaptic weight of\s+\d+\.?\d*'),
        'synaptic weight of $newValueStr',
      );
    } else if (param.pattern == 'using') {
      newLine = line.replaceFirst(
        RegExp(r'using\s+\d+\s+neurons'),
        'using $newValueStr neurons',
      );
    } else {
      return;
    }

    lines[param.lineIndex] = newLine;
    final newSpec = lines.join('\n');

    // Discrete parameter change, not continuous typing — commit immediately
    // rather than debouncing. runParseAndValidate fires automatically once
    // the canonical doc publishes, so no separate callback is needed here.
    ref.read(specTextProvider.notifier).set(newSpec);
  }
}

class _Header extends StatelessWidget {
  final ValueChanged<String> onPresetSelected;

  const _Header({required this.onPresetSelected});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          ZetaIcons.tune,
          size: 16,
          color: Zeta.of(context).colors.mainPrimary,
        ),
        const SizedBox(width: 6),
        Text(
          'Parameter Explorer',
          style: Zeta.of(context).textStyles.bodyMedium.copyWith(
            color: Zeta.of(context).colors.mainDefault,
          ),
        ),
        const Spacer(),
        PopupMenuButton<String>(
          tooltip: 'Presets',
          color: Zeta.of(context).colors.surfaceDefault,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              NmtkShellTokens.of(context).radiusSm,
            ),
            side: BorderSide(color: Zeta.of(context).colors.borderDefault),
          ),
          onSelected: onPresetSelected,
          itemBuilder: (context) => _presets.keys.map((name) {
            return PopupMenuItem<String>(
              value: name,
              child: Text(
                name,
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                  color: Zeta.of(context).colors.mainDefault,
                ),
              ),
            );
          }).toList(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Zeta.of(context).colors.borderDefault),
              borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons
                      .auto_fix_high, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                  size: 12,
                  color: Zeta.of(context).colors.mainPrimary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Presets',
                  style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                    color: Zeta.of(context).colors.mainSubtle,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  ZetaIcons.arrow_down,
                  size: 14,
                  color: Zeta.of(context).colors.mainSubtle,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ParameterSlider extends StatelessWidget {
  final _ExtractedParam param;
  final ValueChanged<double> onChanged;

  const _ParameterSlider({required this.param, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Zeta.of(context).colors.surfaceDefault,
        borderRadius: BorderRadius.circular(
          NmtkShellTokens.of(context).radiusSm,
        ),
        border: Border.all(color: Zeta.of(context).colors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                param.name,
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                  color: Zeta.of(context).colors.mainDefault,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Zeta.of(
                    context,
                  ).colors.mainPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
                ),
                child: Text(
                  param.isInteger
                      ? '${param.value.round()} ${param.unit}'
                      : '${param.value} ${param.unit}',
                  style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                    color: Zeta.of(context).colors.mainPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Zeta.of(context).colors.mainPrimary,
              inactiveTrackColor: Zeta.of(context).colors.surfaceHover,
              thumbColor: Zeta.of(context).colors.mainPrimary,
              overlayColor: Zeta.of(
                context,
              ).colors.mainPrimary.withValues(alpha: 0.1),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: param.value.clamp(param.min, param.max),
              min: param.min,
              max: param.max,
              divisions: param.isInteger
                  ? (param.max - param.min).round()
                  : 100,
              onChanged: onChanged,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                param.isInteger ? '${param.min.round()}' : '${param.min}',
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                  color: Zeta.of(context).colors.mainSubtle,
                ),
              ),
              Text(
                param.isInteger ? '${param.max.round()}' : '${param.max}',
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                  color: Zeta.of(context).colors.mainSubtle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A parameter extracted from the CNL spec text.
class _ExtractedParam {
  final String name;
  final double value;
  final double min;
  final double max;
  final String unit;
  final int lineIndex;
  final int matchStart;
  final int matchEnd;
  final String pattern;
  final bool isInteger;

  const _ExtractedParam({
    required this.name,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.lineIndex,
    required this.matchStart,
    required this.matchEnd,
    required this.pattern,
    this.isInteger = false,
  });
}
