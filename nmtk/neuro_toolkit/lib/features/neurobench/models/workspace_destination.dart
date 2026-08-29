import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

enum NeurobenchWorkspace { summary, comparison, reports, robustness }

extension NeurobenchWorkspaceX on NeurobenchWorkspace {
  String get routePath => switch (this) {
        NeurobenchWorkspace.summary => '/',
        NeurobenchWorkspace.comparison => '/comparison',
        NeurobenchWorkspace.reports => '/reports',
        NeurobenchWorkspace.robustness => '/robustness',
      };

  String get label => switch (this) {
        NeurobenchWorkspace.summary => 'Summary',
        NeurobenchWorkspace.comparison => 'Comparison',
        NeurobenchWorkspace.reports => 'Reports',
        NeurobenchWorkspace.robustness => 'Robustness',
      };

  IconData get icon => switch (this) {
        NeurobenchWorkspace.summary => Icons
            .dashboard_customize_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
        NeurobenchWorkspace.comparison => Icons
            .compare_arrows_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
        NeurobenchWorkspace.reports => ZetaIcons.note,
        NeurobenchWorkspace.robustness => Icons
            .auto_graph_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
      };
}
