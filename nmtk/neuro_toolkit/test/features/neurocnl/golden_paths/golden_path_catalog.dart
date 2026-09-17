/// Mirrors `neurocli/neurocli/ci.py` `_GOLDEN_PATHS` — one row per
/// framework+target combo the CLI golden-path runner exercises.
class StudioGoldenPathCombo {
  const StudioGoldenPathCombo({
    required this.id,
    required this.platformId,
    required this.workspaceFile,
    this.expectTrainable = false,
  });

  final String id;
  final String platformId;
  final String workspaceFile;
  final bool expectTrainable;
}

const kStudioGoldenPathCombos = <StudioGoldenPathCombo>[
  StudioGoldenPathCombo(
    id: 'nir+snntorch',
    platformId: 'snntorch_sim',
    workspaceFile: 'nir_snntorch.nmtk',
    expectTrainable: true,
  ),
  StudioGoldenPathCombo(
    id: 'nir+lava_sim',
    platformId: 'lava_sim',
    workspaceFile: 'nir_lava_sim.nmtk',
  ),
  StudioGoldenPathCombo(
    id: 'neurocnl+pynq',
    platformId: 'pynq',
    workspaceFile: 'neurocnl_pynq.nmtk',
  ),
  StudioGoldenPathCombo(
    id: 'akida+brainchip',
    platformId: 'akida',
    workspaceFile: 'akida_brainchip.nmtk',
  ),
  StudioGoldenPathCombo(
    id: 'neurocnl+neurosim',
    platformId: 'neurosim',
    workspaceFile: 'neurocnl_neurosim.nmtk',
  ),
];

/// Committed `.nmtk` fixtures live next to the CLI runner (CEL-126).
String goldenPathWorkspaceFile(StudioGoldenPathCombo combo) {
  return '../../neurocli/neurocli/golden_paths/${combo.workspaceFile}';
}
