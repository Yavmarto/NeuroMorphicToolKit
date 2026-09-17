library;

import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_workspace_panel/mobile_deploy_action.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_workspace_panel/mobile_deploy_action_scope.dart';

class MobileDeployActionReporter extends StatefulWidget {
  const MobileDeployActionReporter({super.key, required this.action});

  final MobileDeployAction action;

  @override
  State<MobileDeployActionReporter> createState() =>
      _MobileDeployActionReporterState();
}

class _MobileDeployActionReporterState
    extends State<MobileDeployActionReporter> {
  MobileDeployActionScope? _scope;

  void _scheduleReport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scope?.report(widget.action);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = MobileDeployActionScope.maybeOf(context);
    _scheduleReport();
  }

  @override
  void didUpdateWidget(covariant MobileDeployActionReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleReport();
  }

  @override
  void dispose() {
    _scope?.clear(widget.action.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
