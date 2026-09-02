// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

class _ConceptField {
  final String key;
  final String label;
  final String defaultValue;
  final bool isNumber;

  const _ConceptField({
    required this.key,
    required this.label,
    required this.defaultValue,
    this.isNumber = false,
  });
}

class _ConceptDef {
  final String id;
  final String label;
  final String description;
  final IconData icon;
  final List<_ConceptField> fields;
  final String Function(Map<String, String> v) buildSentence;

  const _ConceptDef({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.fields,
    required this.buildSentence,
  });
}

final _kConcepts = <_ConceptDef>[
  _ConceptDef(
    id: 'threshold_firing',
    label: 'Threshold Firing',
    description: 'Neuron fires when membrane potential crosses a threshold.',
    icon: Icons.bolt, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    fields: [
      const _ConceptField(
        key: 'neuron',
        label: 'Neuron',
        defaultValue: 'sensory neuron',
      ),
      const _ConceptField(
        key: 'threshold',
        label: 'Threshold value',
        defaultValue: '1.0',
        isNumber: true,
      ),
    ],
    buildSentence: (v) =>
        'The ${v['neuron']} MUST fire ONLY IF membrane potential exceeds ${v['threshold']}',
  ),
  _ConceptDef(
    id: 'refractory_period',
    label: 'Refractory Period',
    description: 'Neuron cannot fire again for a set duration after spiking.',
    icon: ZetaIcons.pause_circle,
    fields: [
      const _ConceptField(
        key: 'neuron',
        label: 'Neuron',
        defaultValue: 'sensory neuron',
      ),
      const _ConceptField(
        key: 'duration',
        label: 'Duration (seconds)',
        defaultValue: '0.002',
        isNumber: true,
      ),
    ],
    buildSentence: (v) =>
        'The ${v['neuron']} MUST NOT fire DURING the refractory period of ${v['duration']} seconds',
  ),
  _ConceptDef(
    id: 'membrane_potential_decay',
    label: 'Membrane Potential Decay',
    description: 'Membrane potential decays toward rest with a time constant.',
    icon: ZetaIcons.trending_down,
    fields: [
      const _ConceptField(
        key: 'neuron',
        label: 'Neuron',
        defaultValue: 'sensory neuron',
      ),
      const _ConceptField(
        key: 'tau',
        label: 'Time constant (seconds)',
        defaultValue: '0.02',
        isNumber: true,
      ),
    ],
    buildSentence: (v) =>
        'The ${v['neuron']} membrane potential MUST decay WITH time constant of ${v['tau']} seconds',
  ),
  _ConceptDef(
    id: 'synaptic_weight',
    label: 'Synaptic Weight',
    description: 'Set the connection strength between two neurons.',
    icon: Icons.cable, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    fields: [
      const _ConceptField(
        key: 'source',
        label: 'Source neuron',
        defaultValue: 'sensory neuron',
      ),
      const _ConceptField(
        key: 'target',
        label: 'Target neuron',
        defaultValue: 'motor neuron',
      ),
      const _ConceptField(
        key: 'weight',
        label: 'Synaptic weight',
        defaultValue: '1.0',
        isNumber: true,
      ),
    ],
    buildSentence: (v) =>
        'The connection from ${v['source']} to ${v['target']} MUST have WITH synaptic weight of ${v['weight']}',
  ),
  _ConceptDef(
    id: 'axonal_delay',
    label: 'Axonal Delay',
    description: 'Signal transmission takes a fixed delay along the axon.',
    icon: ZetaIcons.timer,
    fields: [
      const _ConceptField(
        key: 'delay',
        label: 'Delay value',
        defaultValue: '5',
        isNumber: true,
      ),
      const _ConceptField(
        key: 'unit',
        label: 'Unit (ms or seconds)',
        defaultValue: 'ms',
      ),
    ],
    buildSentence: (v) =>
        'A synapse MUST have a transmission delay of ${v['delay']} ${v['unit']}',
  ),
  _ConceptDef(
    id: 'stdp_learning',
    label: 'STDP Learning',
    description: 'Spike-timing dependent plasticity adjusts synaptic weights.',
    icon: ZetaIcons.school,
    fields: [
      const _ConceptField(
        key: 'source',
        label: 'Source neuron',
        defaultValue: 'sensory neuron',
      ),
      const _ConceptField(
        key: 'target',
        label: 'Target neuron',
        defaultValue: 'motor neuron',
      ),
      const _ConceptField(
        key: 'rate',
        label: 'Learning rate',
        defaultValue: '0.01',
        isNumber: true,
      ),
    ],
    buildSentence: (v) =>
        'The connection from ${v['source']} to ${v['target']} MUST adapt WITH STDP learning rate of ${v['rate']}',
  ),
  _ConceptDef(
    id: 'inhibitory_connection',
    label: 'Inhibitory Connection',
    description: 'A connection that suppresses the target neuron.',
    icon: ZetaIcons.block,
    fields: [
      const _ConceptField(
        key: 'source',
        label: 'Source neuron',
        defaultValue: 'interneuron',
      ),
      const _ConceptField(
        key: 'target',
        label: 'Target neuron',
        defaultValue: 'motor neuron',
      ),
    ],
    buildSentence: (v) =>
        'The connection from ${v['source']} to ${v['target']} MUST be inhibitory',
  ),
  _ConceptDef(
    id: 'population_coding',
    label: 'Population Coding',
    description: 'A population of neurons encodes an input signal.',
    icon: ZetaIcons.group,
    fields: [
      const _ConceptField(
        key: 'population',
        label: 'Population name',
        defaultValue: 'sensory population',
      ),
      const _ConceptField(
        key: 'neurons',
        label: 'Number of neurons',
        defaultValue: '100',
        isNumber: true,
      ),
    ],
    buildSentence: (v) =>
        'The ${v['population']} MUST encode input using ${v['neurons']} neurons',
  ),
  _ConceptDef(
    id: 'network_topology',
    label: 'Network Topology',
    description: 'Declare a population type and size in the network.',
    icon: Icons
        .account_tree_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    fields: [
      const _ConceptField(
        key: 'type',
        label: 'Population type (inhibitory / excitatory)',
        defaultValue: 'inhibitory',
      ),
      const _ConceptField(
        key: 'name',
        label: 'Population name',
        defaultValue: 'interneuron',
      ),
      const _ConceptField(
        key: 'neurons',
        label: 'Number of neurons',
        defaultValue: '30',
        isNumber: true,
      ),
    ],
    buildSentence: (v) =>
        'The network MUST contain an ${v['type']} ${v['name']} population of ${v['neurons']} neurons',
  ),
  _ConceptDef(
    id: 'lateral_inhibition',
    label: 'Lateral Inhibition',
    description: 'Neuron inhibits its neighbours within a spatial radius.',
    icon: Icons.blur_on, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    fields: [
      const _ConceptField(
        key: 'neuron',
        label: 'Neuron',
        defaultValue: 'sensory neuron',
      ),
      const _ConceptField(
        key: 'radius',
        label: 'Radius',
        defaultValue: '2',
        isNumber: true,
      ),
    ],
    buildSentence: (v) =>
        'The ${v['neuron']} MUST inhibit neighboring neurons WITHIN radius of ${v['radius']}',
  ),
  _ConceptDef(
    id: 'homeostatic_plasticity',
    label: 'Homeostatic Plasticity',
    description: 'Neuron maintains a target average firing rate.',
    icon: Icons.balance, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    fields: [
      const _ConceptField(
        key: 'neuron',
        label: 'Neuron',
        defaultValue: 'sensory neuron',
      ),
      const _ConceptField(
        key: 'rate',
        label: 'Target firing rate (Hz)',
        defaultValue: '10',
        isNumber: true,
      ),
    ],
    buildSentence: (v) =>
        'The ${v['neuron']} MUST maintain average firing rate of ${v['rate']} Hz',
  ),
  _ConceptDef(
    id: 'neuromodulation',
    label: 'Neuromodulation',
    description: 'A chemical modulator scales synaptic weights.',
    icon: Icons.science_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    fields: [
      const _ConceptField(
        key: 'modulator',
        label: 'Modulator (e.g. Dopamine)',
        defaultValue: 'Dopamine',
      ),
      const _ConceptField(
        key: 'factor',
        label: 'Modulation factor',
        defaultValue: '1.5',
        isNumber: true,
      ),
    ],
    buildSentence: (v) =>
        '${v['modulator']} MUST modulate synaptic weight BY factor of ${v['factor']}',
  ),
  _ConceptDef(
    id: 'population_coding_range',
    label: 'Population Coding Range',
    description: 'Population encodes a stimulus over a degree range.',
    icon: ZetaIcons.image,
    fields: [
      const _ConceptField(
        key: 'population',
        label: 'Population name',
        defaultValue: 'population',
      ),
      const _ConceptField(
        key: 'stimulus',
        label: 'Stimulus name',
        defaultValue: 'orientation',
      ),
      const _ConceptField(
        key: 'range',
        label: 'Degree range',
        defaultValue: '360',
        isNumber: true,
      ),
    ],
    buildSentence: (v) =>
        'The ${v['population']} MUST encode stimulus ${v['stimulus']} WITH ${v['range']} degree range',
  ),
];

/// Dialog for building a valid CNL sentence by selecting a concept and filling
/// in labelled fields. Returns the assembled sentence string via [Navigator.pop].
class CnlSentenceBuilderDialog extends StatefulWidget {
  const CnlSentenceBuilderDialog({super.key});

  @override
  State<CnlSentenceBuilderDialog> createState() =>
      _CnlSentenceBuilderDialogState();
}

class _CnlSentenceBuilderDialogState extends State<CnlSentenceBuilderDialog> {
  _ConceptDef? _selected;
  Map<String, TextEditingController> _fieldControllers = {};

  @override
  void dispose() {
    for (final c in _fieldControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _selectConcept(_ConceptDef concept) {
    for (final c in _fieldControllers.values) {
      c.removeListener(_onFieldChanged);
      c.dispose();
    }
    _fieldControllers = {
      for (final f in concept.fields)
        f.key: TextEditingController(text: f.defaultValue),
    };
    for (final c in _fieldControllers.values) {
      c.addListener(_onFieldChanged);
    }
    setState(() => _selected = concept);
  }

  void _onFieldChanged() => setState(() {});

  String get _preview {
    final concept = _selected;
    if (concept == null) return '';
    final values = {
      for (final f in concept.fields)
        f.key: _fieldControllers[f.key]!.text.isEmpty
            ? f.defaultValue
            : _fieldControllers[f.key]!.text,
    };
    return concept.buildSentence(values);
  }

  void _insert() {
    final sentence = _preview;
    if (sentence.isNotEmpty) Navigator.pop(context, sentence);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Zeta.of(context).colors.surfaceDefault,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          NmtkShellTokens.of(context).radiusSm,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 540),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Divider(height: 1, color: Zeta.of(context).colors.borderDefault),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildConceptList(),
                  VerticalDivider(
                    width: 1,
                    color: Zeta.of(context).colors.borderDefault,
                  ),
                  Expanded(child: _buildFormPanel()),
                ],
              ),
            ),
            Divider(height: 1, color: Zeta.of(context).colors.borderDefault),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      child: Row(
        children: [
          Icon(
            Icons.auto_fix_high, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
            color: Zeta.of(context).colors.mainPrimary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            'Add CNL Sentence',
            style: Zeta.of(context).textStyles.bodyMedium.copyWith(
              color: Zeta.of(context).colors.mainDefault,
            ),
          ),
          const Spacer(),
          Tooltip(
            message: 'Close sentence builder',
            child: ZetaIconButton.text(
              icon: ZetaIcons.close,
              size: ZetaWidgetSize.small,
              semanticLabel: 'Close sentence builder',
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConceptList() {
    return SizedBox(
      width: 230,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: _kConcepts.length,
        itemBuilder: (context, i) {
          final concept = _kConcepts[i];
          final isSelected = _selected?.id == concept.id;
          return InkWell(
            onTap: () => _selectConcept(concept),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? Zeta.of(
                        context,
                      ).colors.mainPrimary.withValues(alpha: 0.12)
                    : const Color(0x00000000),
                border: null,
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? ZetaIcons.check_circle_outline
                        : ZetaIcons.radio_button_unchecked,
                    size: 16,
                    color: isSelected
                        ? Zeta.of(context).colors.mainPrimary
                        : Zeta.of(context).colors.mainSubtle,
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    concept.icon,
                    size: 16,
                    color: isSelected
                        ? Zeta.of(context).colors.mainPrimary
                        : Zeta.of(context).colors.mainSubtle,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      concept.label,
                      style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                        color: isSelected
                            ? Zeta.of(context).colors.mainPrimary
                            : Zeta.of(context).colors.mainDefault,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFormPanel() {
    final concept = _selected;
    if (concept == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ZetaIcons.arrow_back,
              color: Zeta.of(context).colors.mainSubtle,
              size: 24,
            ),
            const SizedBox(height: 10),
            Text(
              'Select a concept to get started',
              style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                color: Zeta.of(context).colors.mainSubtle,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                concept.icon,
                color: Zeta.of(context).colors.mainPrimary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                concept.label,
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                  color: Zeta.of(context).colors.mainDefault,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            concept.description,
            style: Zeta.of(context).textStyles.bodyMedium.copyWith(
              color: Zeta.of(context).colors.mainSubtle,
            ),
          ),
          const SizedBox(height: 18),
          for (final field in concept.fields) ...[
            _buildField(field),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 6),
          _buildPreview(),
        ],
      ),
    );
  }

  Widget _buildField(_ConceptField field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          field.label,
          style: Zeta.of(context).textStyles.bodyMedium.copyWith(
            color: Zeta.of(context).colors.mainSubtle,
          ),
        ),
        const SizedBox(height: 4),
        ZetaTextInput(
          controller: _fieldControllers[field.key],
          keyboardType: field.isNumber
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
        ),
      ],
    );
  }

  Widget _buildPreview() {
    final sentence = _preview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preview',
          style: Zeta.of(context).textStyles.bodyMedium.copyWith(
            color: Zeta.of(context).colors.mainSubtle,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Zeta.of(context).colors.surfaceDefault,
            border: Border.all(color: Zeta.of(context).colors.borderDefault),
            borderRadius: BorderRadius.circular(
              NmtkShellTokens.of(context).radiusSm,
            ),
          ),
          child: Text(
            sentence.isEmpty ? '-' : sentence,
            style: Zeta.of(context).textStyles.bodyMedium.copyWith(
              fontFamily: 'monospace',
              color: Zeta.of(context).colors.mainPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ZetaButton.text(
            onPressed: () => Navigator.pop(context),
            label: 'Cancel',
          ),
          const SizedBox(width: 8),
          ZetaButton(
            onPressed: _selected != null ? _insert : null,
            label: 'Insert',
          ),
        ],
      ),
    );
  }
}
