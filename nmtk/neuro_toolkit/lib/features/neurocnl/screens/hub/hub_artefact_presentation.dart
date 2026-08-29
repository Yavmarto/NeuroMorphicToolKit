import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/hub_preview.dart';

class HubArtefactPresentation {
  const HubArtefactPresentation._({required this.icon, required this.tone});

  final IconData icon;
  final NmtkTone tone;

  static HubArtefactPresentation forKind(HubArtefactKind kind) =>
      switch (kind) {
        HubArtefactKind.workspace => const HubArtefactPresentation._(
          icon: Icons.account_tree_outlined,
          tone: NmtkTone.info,
        ),
        HubArtefactKind.benchmarkResult => const HubArtefactPresentation._(
          icon: Icons.query_stats_outlined,
          tone: NmtkTone.success,
        ),
        HubArtefactKind.customNode => const HubArtefactPresentation._(
          icon: Icons.hub_outlined,
          tone: NmtkTone.warning,
        ),
      };
}
