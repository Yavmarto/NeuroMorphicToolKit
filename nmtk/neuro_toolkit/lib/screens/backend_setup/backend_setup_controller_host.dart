import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/models/backend_deployment.dart';

/// What [QuickConnectController] and [SystemHealthController] need from the
/// owning `_BackendSetupFormState`: rebuild scheduling, the widget's
/// `BuildContext`/`WidgetRef`, the shared connected-host field both read or
/// write, and the three widget-level callbacks quick-connect forwards to.
abstract class BackendSetupControllerHost {
  bool get mounted;
  BuildContext get context;
  WidgetRef get ref;
  void rebuild(VoidCallback fn);

  String? get connectedHealthHost;
  set connectedHealthHost(String? value);

  Future<String?> Function(String input)? get onQuickConnect;
  void Function()? get onQuickConnectSuccess;
  Future<void> Function(DeploymentTarget target)? get onDeploymentReady;
}
