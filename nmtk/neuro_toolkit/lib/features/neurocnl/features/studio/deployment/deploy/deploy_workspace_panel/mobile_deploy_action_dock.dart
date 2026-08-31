library;

import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_workspace_panel/mobile_deploy_action.dart';

class MobileDeployActionDock extends StatelessWidget {
  const MobileDeployActionDock({super.key, required this.action});

  final MobileDeployAction action;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    return DecoratedBox(
      key: const Key('mobile-deploy-action-dock'),
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: SizedBox(
          height: 48,
          child: ZetaButton(
            key: Key('mobile-deploy-action-${action.id}'),
            onPressed: action.onPressed,
            label: action.label,
            leadingIcon: action.icon,
          ),
        ),
      ),
    );
  }
}
