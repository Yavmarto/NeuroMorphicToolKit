# Deploy to board rejected with OVERLAY_REGISTER_MAP_MISMATCH

**Symptom.** With the board `ready`/`ok`/`hardware` and the network exportable, Deploy to board
returned:

```
HTTP 422 - {"detail":{"detail":"register_map does not match the installed overlay contract",
            "error_code":"OVERLAY_REGISTER_MAP_MISMATCH"}}
```

Both real maps were identical. The app rewrote the one in transit.

## Cause

`PynqRegisterMap` in [nmtk_ui_core/lib/models/pynq_deployment_model.dart](../../nmtk_ui_core/lib/models/pynq_deployment_model.dart)
modelled the map as typed **overlay-v1** registers. The v2 map the backend resolves from the `.hwh`
has 13 keys, only two of which (`base_address`, `control_reg_offset`, plus `dma_channel`,
`timestep_us`, `timestep_count_offset`) the class knew. Round-tripping it:

- kept the 8 unknown v2 keys as passengers in `additionalFields` — fine, and the reason nothing was
  visibly *lost*;
- **invented 9 v1 keys from constructor defaults** that the backend never sent:
  `status_reg_offset`, `population_count_offset`, `input_neuron_count_offset`,
  `output_neuron_count_offset`, `threshold_base_offset`, `neuron_base_offset`, `weight_base_offset`,
  `input_buffer_addr`, `output_buffer_addr`.

The board compares for **equality** against its installed `overlay_manifest.json`
([Neurochip/neurochip/app/routers/pynq.py:365](../../Neurochip/neurochip/app/routers/pynq.py)), so a
21-key map could never match a 13-key one — no matter how correct every shared value was.

`PynqDeployConfig` had the same shape of defect, quietly: it dropped `timestep_us` because it has no
field for it. Nothing on the board reads `config.timestep_us` today, so this was latent.

## Fix

The register map is a contract token between the backend that resolves it and the board that
validates it — no screen reads a field of it. It is now carried verbatim:

```dart
class PynqRegisterMap {
  final Map<String, dynamic> values;
  const PynqRegisterMap(this.values);
  factory PynqRegisterMap.fromJson(Map<String, dynamic> json) =>
      PynqRegisterMap(Map<String, dynamic>.from(json));
  Map<String, dynamic> toJson() => Map<String, dynamic>.from(values);
  String get dmaChannel => values['dma_channel'] as String? ?? '';
}
```

`PynqDeployConfig` keeps unknown keys in `additionalFields` and sends them back.

## Proof on the real board

Two probes against `192.168.2.103` through the launcher proxy, both with a deliberately absent
bitstream path so validation is the only thing exercised and the FPGA is never programmed:

| register map posted | board |
| --- | --- |
| verbatim (fixed app) | `500 OVERLAY_NOT_FOUND` — passed the register-map gate, failed on the fake bitstream |
| v1 round-trip (old app) | `422 OVERLAY_REGISTER_MAP_MISMATCH` — the user's exact error |

## Tests

- [nmtk_ui_core/test/models_test.dart](../../nmtk_ui_core/test/models_test.dart) — the fixture is now
  the real v2 map, and the assertion is `roundTrip['register_map'] == source` (and the same for
  `config`), which is the property the board actually requires.
- Two frontend fixtures dropped their v1 register-map literals.
- Green: `nmtk_ui_core` 198, `neurocnl/frontend` 1810 (1 skipped), `flutter analyze` clean in both.

## Notes

- No backend change, so no `make dev-update`. The user restarts the Flutter app.
- Related: the same "two sides of one contract derived independently" family as
  `2026-08-15/pynq-overlay-manifest-dma-channel.md`. Here the *third* party — the UI model — was the
  one that diverged.
