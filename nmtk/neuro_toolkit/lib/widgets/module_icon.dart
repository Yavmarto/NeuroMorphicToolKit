import 'package:flutter/material.dart';

import 'package:neuro_toolkit/models/module.dart';

/// Maps a [Module.icon] string to the appropriate [IconData].
///
/// Pass [selected] = `true` to get the filled/rounded variant used for the
/// active sidebar item.
abstract final class ModuleIcon {
  static IconData forModule(Module module, {bool selected = false}) =>
      switch (module.icon) {
        'code' => selected ? Icons.code_rounded : Icons.code_outlined,
        'architecture' =>
          selected ? Icons.architecture : Icons.architecture_outlined,
        'memory' => selected ? Icons.memory_rounded : Icons.memory_outlined,
        'speed' => selected ? Icons.speed_rounded : Icons.speed_outlined,
        'sensors' => selected ? Icons.sensors_rounded : Icons.sensors_outlined,
        'hub' => selected ? Icons.hub_rounded : Icons.hub_outlined,
        'precision_manufacturing' => selected
            ? Icons.precision_manufacturing
            : Icons.precision_manufacturing_outlined,
        _ => selected
            ? (module.hasFrontend ? Icons.web_rounded : Icons.api_rounded)
            : (module.hasFrontend ? Icons.web_outlined : Icons.api_outlined),
      };
}
