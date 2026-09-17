import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/component.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

const List<NirNodeType> _nirNodeTypes = <NirNodeType>[
  NirNodeType(
    id: 'nir.Input',
    displayName: 'Input',
    category: 'io',
    icon: Icons.input, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    legacyComponentId: 'input_node',
    ports: <NirPortDef>[
      NirPortDef(id: 'out', direction: 'output', label: 'out'),
    ],
    parameters: <NirParameterDef>[
      NirParameterDef(
        name: 'size',
        label: 'Size',
        type: 'int',
        defaultValue: 1,
        min: 1,
      ),
      NirParameterDef(
        name: 'shape',
        label: 'Shape (leave blank for flat)',
        type: 'text',
        defaultValue: '',
        description:
            'Multi-dimensional input, e.g. channels,height,width for a '
            'Conv2d first layer. When set, Size must equal its product '
            '(the backend prefers Shape only when the two agree). Leave '
            'blank for a plain 1-D input of length Size.',
      ),
    ],
  ),
  NirNodeType(
    id: 'nir.Output',
    displayName: 'Output',
    category: 'io',
    icon: Icons.output, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    legacyComponentId: 'output_node',
    ports: <NirPortDef>[NirPortDef(id: 'in', direction: 'input', label: 'in')],
    parameters: <NirParameterDef>[
      NirParameterDef(
        name: 'size',
        label: 'Size',
        type: 'int',
        defaultValue: 1,
        min: 1,
      ),
    ],
  ),
  NirNodeType(
    id: 'nir.LIF',
    displayName: 'LIF',
    category: 'neuron',
    icon: Icons.hub, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    legacyComponentId: 'lif_population',
    ports: <NirPortDef>[
      NirPortDef(id: 'in', direction: 'input', label: 'in'),
      NirPortDef(id: 'out', direction: 'output', label: 'out'),
    ],
    parameters: <NirParameterDef>[
      NirParameterDef(
        name: 'n_neurons',
        label: 'Neurons',
        type: 'int',
        defaultValue: 1,
        min: 1,
      ),
      NirParameterDef(
        name: 'tau',
        label: 'Tau',
        type: 'float',
        defaultValue: 0.02,
        min: 0.0001,
        unit: 's',
      ),
      NirParameterDef(
        name: 'threshold',
        label: 'Threshold',
        type: 'float',
        defaultValue: 1.0,
      ),
      NirParameterDef(
        name: 'r',
        label: 'Resistance',
        type: 'float',
        defaultValue: 1.0,
      ),
      NirParameterDef(
        name: 'v_leak',
        label: 'Leak',
        type: 'float',
        defaultValue: 0.0,
      ),
      // Per-node 'dt' and 'beta' controls used to live here. Neither was ever
      // read: the backend's _deserialize_node (nir_graph_serializer.py) builds
      // nir.LIF from tau/threshold/r/v_leak only, so editing them changed
      // nothing. The timestep is a property of the network, not of one neuron —
      // set it in Network Settings, which does reach every backend. A per-node
      // override remains available in CNL via
      // `annotated with metadata dt equal to <seconds>`.
    ],
  ),
  NirNodeType(
    id: 'nir.CubaLIF',
    displayName: 'CubaLIF',
    category: 'neuron',
    icon: Icons.bolt, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    legacyComponentId: 'lif_population',
    ports: <NirPortDef>[
      NirPortDef(id: 'in', direction: 'input', label: 'in'),
      NirPortDef(id: 'out', direction: 'output', label: 'out'),
    ],
    parameters: <NirParameterDef>[
      NirParameterDef(
        name: 'n_neurons',
        label: 'Neurons',
        type: 'int',
        defaultValue: 1,
        min: 1,
      ),
      NirParameterDef(
        name: 'tau_mem',
        label: 'Tau Mem',
        type: 'float',
        defaultValue: 0.02,
        min: 0.0001,
        unit: 's',
      ),
      NirParameterDef(
        name: 'tau_syn',
        label: 'Tau Syn',
        type: 'float',
        defaultValue: 0.01,
        min: 0.0001,
        unit: 's',
      ),
      NirParameterDef(
        name: 'threshold',
        label: 'Threshold',
        type: 'float',
        defaultValue: 1.0,
      ),
      NirParameterDef(
        name: 'w_in',
        label: 'Input Weight',
        type: 'float',
        defaultValue: 1.0,
      ),
    ],
  ),
  NirNodeType(
    id: 'nir.IF',
    displayName: 'IF',
    category: 'neuron',
    icon: ZetaIcons.flash_on,
    legacyComponentId: 'lif_population',
    ports: <NirPortDef>[
      NirPortDef(id: 'in', direction: 'input', label: 'in'),
      NirPortDef(id: 'out', direction: 'output', label: 'out'),
    ],
    parameters: <NirParameterDef>[
      NirParameterDef(
        name: 'n_neurons',
        label: 'Neurons',
        type: 'int',
        defaultValue: 1,
        min: 1,
      ),
      NirParameterDef(
        name: 'threshold',
        label: 'Threshold',
        type: 'float',
        defaultValue: 1.0,
      ),
      NirParameterDef(
        name: 'r',
        label: 'Resistance',
        type: 'float',
        defaultValue: 1.0,
      ),
      NirParameterDef(
        name: 'beta',
        label: 'Beta (mem decay)',
        type: 'float',
        defaultValue: 0.9,
        min: 0.0,
        max: 1.0,
        description: 'Membrane decay factor',
      ),
    ],
  ),
  NirNodeType(
    id: 'nir.LI',
    displayName: 'LI',
    category: 'neuron',
    icon: ZetaIcons.chart_bar,
    legacyComponentId: 'lif_population',
    ports: <NirPortDef>[
      NirPortDef(id: 'in', direction: 'input', label: 'in'),
      NirPortDef(id: 'out', direction: 'output', label: 'out'),
    ],
    parameters: <NirParameterDef>[
      NirParameterDef(
        name: 'n_neurons',
        label: 'Neurons',
        type: 'int',
        defaultValue: 1,
        min: 1,
      ),
      NirParameterDef(
        name: 'tau',
        label: 'Tau',
        type: 'float',
        defaultValue: 0.02,
        min: 0.0001,
        unit: 's',
      ),
      NirParameterDef(
        name: 'r',
        label: 'Resistance',
        type: 'float',
        defaultValue: 1.0,
      ),
      NirParameterDef(
        name: 'v_leak',
        label: 'Leak',
        type: 'float',
        defaultValue: 0.0,
      ),
    ],
  ),
  NirNodeType(
    id: 'nir.Linear',
    displayName: 'Linear',
    category: 'transform',
    icon: Icons.linear_scale, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    legacyComponentId: 'nir.Linear',
    ports: <NirPortDef>[
      NirPortDef(id: 'in', direction: 'input', label: 'in'),
      NirPortDef(id: 'out', direction: 'output', label: 'out'),
    ],
    parameters: <NirParameterDef>[
      NirParameterDef(
        name: 'rows',
        label: 'Rows',
        type: 'int',
        defaultValue: 1,
        min: 1,
      ),
      NirParameterDef(
        name: 'cols',
        label: 'Cols',
        type: 'int',
        defaultValue: 1,
        min: 1,
      ),
      NirParameterDef(
        name: 'weight_fill',
        label: 'Fill',
        type: 'float',
        defaultValue: 1.0,
      ),
    ],
  ),
  NirNodeType(
    id: 'nir.Affine',
    displayName: 'Affine',
    category: 'transform',
    icon: ZetaIcons.tune,
    legacyComponentId: 'nir.Affine',
    ports: <NirPortDef>[
      NirPortDef(id: 'in', direction: 'input', label: 'in'),
      NirPortDef(id: 'out', direction: 'output', label: 'out'),
    ],
    parameters: <NirParameterDef>[
      NirParameterDef(
        name: 'rows',
        label: 'Rows',
        type: 'int',
        defaultValue: 1,
        min: 1,
      ),
      NirParameterDef(
        name: 'cols',
        label: 'Cols',
        type: 'int',
        defaultValue: 1,
        min: 1,
      ),
      NirParameterDef(
        name: 'weight_fill',
        label: 'Fill',
        type: 'float',
        defaultValue: 1.0,
      ),
    ],
  ),
  NirNodeType(
    id: 'nir.Conv1d',
    displayName: 'Conv1d',
    category: 'transform',
    icon: ZetaIcons.list,
    legacyComponentId: 'nir.Conv1d',
    ports: <NirPortDef>[
      NirPortDef(id: 'in', direction: 'input', label: 'in'),
      NirPortDef(id: 'out', direction: 'output', label: 'out'),
    ],
    parameters: <NirParameterDef>[
      NirParameterDef(
        name: 'weight_shape',
        label: 'Shape',
        type: 'text',
        defaultValue: '1,1,3',
      ),
      NirParameterDef(
        name: 'weight_fill',
        label: 'Fill',
        type: 'float',
        defaultValue: 0.1,
      ),
      NirParameterDef(
        name: 'stride',
        label: 'Stride',
        type: 'int',
        defaultValue: 1,
        min: 1,
      ),
    ],
  ),
  NirNodeType(
    id: 'nir.Conv2d',
    displayName: 'Conv2d',
    category: 'transform',
    icon: ZetaIcons.grid_view,
    legacyComponentId: 'nir.Conv2d',
    ports: <NirPortDef>[
      NirPortDef(id: 'in', direction: 'input', label: 'in'),
      NirPortDef(id: 'out', direction: 'output', label: 'out'),
    ],
    parameters: <NirParameterDef>[
      NirParameterDef(
        name: 'weight_shape',
        label: 'Shape',
        type: 'text',
        defaultValue: '1,1,3,3',
      ),
      NirParameterDef(
        name: 'weight_fill',
        label: 'Fill',
        type: 'float',
        defaultValue: 0.1,
      ),
      NirParameterDef(
        name: 'stride',
        label: 'Stride (h,w)',
        type: 'text',
        defaultValue: '1,1',
      ),
      NirParameterDef(
        name: 'padding',
        label: 'Padding (h,w)',
        type: 'text',
        defaultValue: '0,0',
      ),
      NirParameterDef(
        name: 'dilation',
        label: 'Dilation (h,w)',
        type: 'text',
        defaultValue: '1,1',
      ),
      NirParameterDef(
        name: 'groups',
        label: 'Groups',
        type: 'int',
        defaultValue: 1,
        min: 1,
      ),
      NirParameterDef(
        name: 'input_shape',
        label: 'Input Height, Width',
        type: 'text',
        defaultValue: '',
        description:
            'Spatial input size (h,w) — only needed if this is the first '
            'layer after Input. Leave blank otherwise.',
      ),
    ],
  ),
  NirNodeType(
    id: 'nir.Flatten',
    displayName: 'Flatten',
    category: 'utility',
    icon: ZetaIcons.unfold_more,
    legacyComponentId: 'nir.Flatten',
    ports: <NirPortDef>[
      NirPortDef(id: 'in', direction: 'input', label: 'in'),
      NirPortDef(id: 'out', direction: 'output', label: 'out'),
    ],
    parameters: <NirParameterDef>[
      NirParameterDef(
        name: 'start_dim',
        label: 'Start Dim',
        type: 'int',
        defaultValue: 1,
      ),
      NirParameterDef(
        name: 'end_dim',
        label: 'End Dim',
        type: 'int',
        defaultValue: -1,
      ),
    ],
  ),
  NirNodeType(
    id: 'nir.AvgPool2d',
    displayName: 'AvgPool2d',
    category: 'pooling',
    icon: ZetaIcons.crop,
    legacyComponentId: 'nir.AvgPool2d',
    ports: <NirPortDef>[
      NirPortDef(id: 'in', direction: 'input', label: 'in'),
      NirPortDef(id: 'out', direction: 'output', label: 'out'),
    ],
    parameters: <NirParameterDef>[
      NirParameterDef(
        name: 'kernel_size',
        label: 'Kernel',
        type: 'text',
        defaultValue: '2,2',
      ),
      NirParameterDef(
        name: 'stride',
        label: 'Stride',
        type: 'text',
        defaultValue: '2,2',
      ),
    ],
  ),
  NirNodeType(
    id: 'nir.SumPool2d',
    displayName: 'SumPool2d',
    category: 'pooling',
    icon:
        Icons.dashboard_customize, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    legacyComponentId: 'nir.SumPool2d',
    ports: <NirPortDef>[
      NirPortDef(id: 'in', direction: 'input', label: 'in'),
      NirPortDef(id: 'out', direction: 'output', label: 'out'),
    ],
    parameters: <NirParameterDef>[
      NirParameterDef(
        name: 'kernel_size',
        label: 'Kernel',
        type: 'text',
        defaultValue: '2,2',
      ),
      NirParameterDef(
        name: 'stride',
        label: 'Stride',
        type: 'text',
        defaultValue: '2,2',
      ),
    ],
  ),
  NirNodeType(
    id: 'nir.Delay',
    displayName: 'Delay',
    category: 'utility',
    icon: ZetaIcons.timer,
    legacyComponentId: 'nir.Delay',
    ports: <NirPortDef>[
      NirPortDef(id: 'in', direction: 'input', label: 'in'),
      NirPortDef(id: 'out', direction: 'output', label: 'out'),
    ],
    parameters: <NirParameterDef>[
      NirParameterDef(
        name: 'delay',
        label: 'Delay',
        type: 'float',
        defaultValue: 0.001,
        min: 0.0,
        unit: 's',
      ),
    ],
  ),
  NirNodeType(
    id: 'nir.Scale',
    displayName: 'Scale',
    category: 'transform',
    icon: ZetaIcons.open_in_full,
    legacyComponentId: 'nir.Scale',
    ports: <NirPortDef>[
      NirPortDef(id: 'in', direction: 'input', label: 'in'),
      NirPortDef(id: 'out', direction: 'output', label: 'out'),
    ],
    parameters: <NirParameterDef>[
      NirParameterDef(
        name: 'scale_fill',
        label: 'Scale',
        type: 'float',
        defaultValue: 1.0,
      ),
    ],
  ),
  NirNodeType(
    id: 'cnl.Synaptic',
    displayName: 'Synaptic',
    category: 'neuron',
    icon: Icons.electric_bolt, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    legacyComponentId: 'cnl.Synaptic',
    ports: <NirPortDef>[
      NirPortDef(id: 'in', direction: 'input', label: 'in'),
      NirPortDef(id: 'out', direction: 'output', label: 'out'),
    ],
    parameters: <NirParameterDef>[
      NirParameterDef(
        name: 'n_neurons',
        label: 'Neurons',
        type: 'int',
        defaultValue: 1,
        min: 1,
      ),
      NirParameterDef(
        name: 'alpha',
        label: 'Alpha (syn decay)',
        type: 'float',
        defaultValue: 0.9,
        min: 0.0,
        max: 1.0,
        description: 'Synaptic current decay factor',
      ),
      NirParameterDef(
        name: 'beta',
        label: 'Beta (mem decay)',
        type: 'float',
        defaultValue: 0.8,
        min: 0.0,
        max: 1.0,
        description: 'Membrane potential decay factor',
      ),
      NirParameterDef(
        name: 'threshold',
        label: 'Threshold',
        type: 'float',
        defaultValue: 1.0,
      ),
      NirParameterDef(
        name: 'reset_mechanism',
        label: 'Reset',
        type: 'enum',
        defaultValue: 'subtract',
        enumValues: <String>['subtract', 'zero'],
        description: 'Membrane reset after spike',
      ),
    ],
  ),
  NirNodeType(
    id: 'cnl.RSynaptic',
    displayName: 'RSynaptic',
    category: 'neuron',
    icon: Icons.loop, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    legacyComponentId: 'cnl.RSynaptic',
    ports: <NirPortDef>[
      NirPortDef(id: 'in', direction: 'input', label: 'in'),
      NirPortDef(id: 'out', direction: 'output', label: 'out'),
    ],
    parameters: <NirParameterDef>[
      NirParameterDef(
        name: 'n_neurons',
        label: 'Neurons',
        type: 'int',
        defaultValue: 1,
        min: 1,
      ),
      NirParameterDef(
        name: 'alpha',
        label: 'Alpha (syn decay)',
        type: 'float',
        defaultValue: 0.9,
        min: 0.0,
        max: 1.0,
        description: 'Synaptic current decay factor',
      ),
      NirParameterDef(
        name: 'beta',
        label: 'Beta (mem decay)',
        type: 'float',
        defaultValue: 0.8,
        min: 0.0,
        max: 1.0,
        description: 'Membrane potential decay factor',
      ),
      NirParameterDef(
        name: 'threshold',
        label: 'Threshold',
        type: 'float',
        defaultValue: 1.0,
      ),
      NirParameterDef(
        name: 'reset_mechanism',
        label: 'Reset',
        type: 'enum',
        defaultValue: 'subtract',
        enumValues: <String>['subtract', 'zero'],
        description: 'Membrane reset after spike',
      ),
      NirParameterDef(
        name: 'use_bias',
        label: 'Use Bias',
        type: 'bool',
        defaultValue: false,
        description: 'Bias term in the internal recurrent Linear layer',
      ),
    ],
  ),
  NirNodeType(
    id: 'cnl.RLeaky',
    displayName: 'RLeaky',
    category: 'neuron',
    icon: Icons.loop, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    legacyComponentId: 'cnl.RLeaky',
    ports: <NirPortDef>[
      NirPortDef(id: 'in', direction: 'input', label: 'in'),
      NirPortDef(id: 'out', direction: 'output', label: 'out'),
    ],
    parameters: <NirParameterDef>[
      NirParameterDef(
        name: 'n_neurons',
        label: 'Neurons',
        type: 'int',
        defaultValue: 1,
        min: 1,
      ),
      NirParameterDef(
        name: 'beta',
        label: 'Beta (mem decay)',
        type: 'float',
        defaultValue: 0.9,
        min: 0.0,
        max: 1.0,
        description: 'Membrane decay factor',
      ),
      NirParameterDef(
        name: 'threshold',
        label: 'Threshold',
        type: 'float',
        defaultValue: 1.0,
      ),
      NirParameterDef(
        name: 'reset_mechanism',
        label: 'Reset',
        type: 'enum',
        defaultValue: 'subtract',
        enumValues: <String>['subtract', 'zero'],
        description: 'Membrane reset after spike',
      ),
    ],
  ),
  NirNodeType(
    id: 'cnl.Leaky',
    displayName: 'Leaky (β)',
    category: 'neuron',
    icon: Icons.hub, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    legacyComponentId: 'cnl.Leaky',
    ports: <NirPortDef>[
      NirPortDef(id: 'in', direction: 'input', label: 'in'),
      NirPortDef(id: 'out', direction: 'output', label: 'out'),
    ],
    parameters: <NirParameterDef>[
      NirParameterDef(
        name: 'n_neurons',
        label: 'Neurons',
        type: 'int',
        defaultValue: 1,
        min: 1,
      ),
      NirParameterDef(
        name: 'beta',
        label: 'Beta (mem decay)',
        type: 'float',
        defaultValue: 0.9,
        min: 0.0,
        max: 1.0,
        description: 'Direct beta parameterisation (snnTorch native)',
      ),
      NirParameterDef(
        name: 'threshold',
        label: 'Threshold',
        type: 'float',
        defaultValue: 1.0,
      ),
      NirParameterDef(
        name: 'reset_mechanism',
        label: 'Reset',
        type: 'enum',
        defaultValue: 'subtract',
        enumValues: <String>['subtract', 'zero'],
        description: 'Membrane reset after spike',
      ),
    ],
  ),
  NirNodeType(
    id: 'cnl.BatchNorm1d',
    displayName: 'BatchNorm1d',
    category: 'transform',
    icon: Icons.auto_fix_normal, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    legacyComponentId: 'cnl.BatchNorm1d',
    ports: <NirPortDef>[
      NirPortDef(id: 'in', direction: 'input', label: 'in'),
      NirPortDef(id: 'out', direction: 'output', label: 'out'),
    ],
    parameters: <NirParameterDef>[
      NirParameterDef(
        name: 'num_features',
        label: 'Features',
        type: 'int',
        defaultValue: 1,
        min: 1,
        description: 'Output size of the preceding layer',
      ),
    ],
  ),
  NirNodeType(
    id: 'cnl.Dropout',
    displayName: 'Dropout',
    category: 'transform',
    icon: Icons.blur_on, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    legacyComponentId: 'cnl.Dropout',
    ports: <NirPortDef>[
      NirPortDef(id: 'in', direction: 'input', label: 'in'),
      NirPortDef(id: 'out', direction: 'output', label: 'out'),
    ],
    parameters: <NirParameterDef>[
      NirParameterDef(
        name: 'p',
        label: 'Drop Probability',
        type: 'float',
        defaultValue: 0.5,
        min: 0.0,
        max: 1.0,
        description: 'Fraction of activations zeroed during training',
      ),
    ],
  ),
];

String _customCategory(String category) {
  return switch (category.trim().toLowerCase()) {
    'neurons' || 'neuron' => 'neuron',
    'encoders' || 'encoder' || 'input' || 'output' => 'io',
    'synapses' || 'synapse' || 'transforms' || 'transform' => 'transform',
    _ => 'utility',
  };
}

NirNodeType _customType(ComponentBlock component) {
  return NirNodeType(
    id: component.id,
    displayName: component.name,
    category: _customCategory(component.category),
    icon: Icons.code,
    legacyComponentId: component.id,
    baseNirType: component.baseNirType,
    isCustom: true,
    ports: component.ports
        .map(
          (PortDef port) => NirPortDef(
            id: port.id,
            direction: port.direction,
            label: port.label,
          ),
        )
        .toList(growable: false),
    parameters: component.parameters
        .map(
          (ParameterDef parameter) => NirParameterDef(
            name: parameter.name,
            label: parameter.label,
            type: parameter.type,
            description: parameter.description,
            defaultValue: parameter.defaultValue,
            min: parameter.min,
            max: parameter.max,
            unit: parameter.unit,
            enumValues: parameter.enumValues,
          ),
        )
        .toList(growable: false),
  );
}

final customNirNodeTypesProvider = FutureProvider<List<NirNodeType>>((
  ref,
) async {
  try {
    final components = await ref.watch(apiClientProvider).fetchComponents();
    return components
        .where((ComponentBlock component) => component.isCustom)
        .map(_customType)
        .toList(growable: false);
  } on Object {
    // The built-in palette must remain available while the backend reconnects.
    // Explicit invalidation after save/reconnect refreshes custom entries.
    return const <NirNodeType>[];
  }
});

final nirNodeTypesProvider = Provider<List<NirNodeType>>((ref) {
  final custom = ref.watch(customNirNodeTypesProvider).value ?? const [];
  return <NirNodeType>[..._nirNodeTypes, ...custom];
});

final nirNodeTypeMapProvider = Provider<Map<String, NirNodeType>>((ref) {
  final types = ref.watch(nirNodeTypesProvider);
  return <String, NirNodeType>{for (final type in types) type.id: type};
});
