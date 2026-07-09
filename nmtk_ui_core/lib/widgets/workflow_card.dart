import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:nmtk_ui_core/widgets/surface_card.dart';

part 'workflow_stage_tile.dart';

enum NmtkWorkflowStageState { upcoming, active, done, error }

class NmtkWorkflowStage {
  const NmtkWorkflowStage({
    required this.title,
    required this.detail,
    required this.state,
  });

  final String title;
  final String detail;
  final NmtkWorkflowStageState state;
}

class NmtkWorkflowCard extends StatelessWidget {
  const NmtkWorkflowCard({
    super.key,
    required this.stages,
    this.title = 'Workflow',
    this.subtitle = 'Each stage stays visible so the next action is obvious.',
  });

  final List<NmtkWorkflowStage> stages;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return NmtkSurfaceCard(
      title: title,
      subtitle: subtitle,
      child: Column(
        children: stages
            .map(
              (stage) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _NmtkWorkflowStageTile(stage: stage),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}
