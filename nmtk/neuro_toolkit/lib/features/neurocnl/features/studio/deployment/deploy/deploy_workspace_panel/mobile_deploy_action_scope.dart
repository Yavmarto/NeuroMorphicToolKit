library;

import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_workspace_panel/mobile_deploy_action.dart';

class MobileDeployActionScope extends InheritedWidget {
  const MobileDeployActionScope({
    super.key,
    required this.report,
    required this.clear,
    required super.child,
  });

  final ValueChanged<MobileDeployAction> report;
  final ValueChanged<String> clear;

  static MobileDeployActionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MobileDeployActionScope>();

  @override
  bool updateShouldNotify(MobileDeployActionScope oldWidget) => false;
}
