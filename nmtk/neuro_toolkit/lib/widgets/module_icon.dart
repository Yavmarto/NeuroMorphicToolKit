import 'package:flutter/material.dart';

import 'package:neuro_toolkit/models/module.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

/// Maps a [Module.icon] string to the appropriate [IconData].
///
/// Pass [selected] = `true` to get the filled/rounded variant used for the
/// active sidebar item.
abstract final class ModuleIcon {
  static IconData forModule(Module module, {bool selected = false}) =>
      switch (module.icon) {
        'code' => selected
            ? Icons.code_rounded
            : Icons.code_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
        'architecture' => selected
            ? Icons.architecture
            : Icons
                .architecture_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
        'memory' => selected ? ZetaIcons.memory : ZetaIcons.memory,
        'speed' => selected
            ? Icons.speed_rounded
            : Icons.speed_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
        'sensors' => selected
            ? Icons.sensors_rounded
            : Icons
                .sensors_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
        'hub' => selected
            ? Icons.hub_rounded
            : Icons.hub_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
        'precision_manufacturing' => selected
            ? Icons
                .precision_manufacturing // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
            : Icons
                .precision_manufacturing_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
        _ => selected
            ? (module.hasFrontend
                ? Icons.web_rounded
                : Icons
                    .api_rounded) // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
            : (module.hasFrontend
                ? Icons.web_outlined
                : Icons
                    .api_outlined), // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
      };
}
