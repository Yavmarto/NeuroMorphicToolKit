import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

enum NeurobenchWorkbenchTab { configure, results, compare, reports, robustness }

NeurobenchWorkbenchTab workbenchTabFromQuery(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return NeurobenchWorkbenchTab.configure;
  }
  final normalized = raw.trim().toLowerCase();
  for (final tab in NeurobenchWorkbenchTab.values) {
    if (tab.name == normalized || tab.queryValue == normalized) {
      return tab;
    }
  }
  return switch (normalized) {
    'comparison' => NeurobenchWorkbenchTab.compare,
    'summary' => NeurobenchWorkbenchTab.configure,
    _ => NeurobenchWorkbenchTab.configure,
  };
}

NeurobenchWorkbenchTab workbenchTabFromLegacyPath(String path) {
  return switch (path) {
    '/comparison' => NeurobenchWorkbenchTab.compare,
    '/reports' => NeurobenchWorkbenchTab.reports,
    '/robustness' => NeurobenchWorkbenchTab.robustness,
    _ => NeurobenchWorkbenchTab.configure,
  };
}

extension NeurobenchWorkbenchTabX on NeurobenchWorkbenchTab {
  String get queryValue => name;

  String get label => switch (this) {
        NeurobenchWorkbenchTab.configure => 'Configure & Run',
        NeurobenchWorkbenchTab.results => 'Results & History',
        NeurobenchWorkbenchTab.compare => 'Comparisons',
        NeurobenchWorkbenchTab.reports => 'Reports',
        NeurobenchWorkbenchTab.robustness => 'Robustness',
      };

  IconData get icon => switch (this) {
        NeurobenchWorkbenchTab.configure => ZetaIcons.tune,
        NeurobenchWorkbenchTab.results => ZetaIcons.history,
        NeurobenchWorkbenchTab.compare => Icons
            .compare_arrows_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
        NeurobenchWorkbenchTab.robustness => Icons
            .auto_graph_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
        NeurobenchWorkbenchTab.reports => ZetaIcons.note,
      };
}
