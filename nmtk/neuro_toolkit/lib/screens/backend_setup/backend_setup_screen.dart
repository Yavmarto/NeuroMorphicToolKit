import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/screens/backend_setup.dart';

class BackendSetupScreen extends StatelessWidget {
  const BackendSetupScreen({
    super.key,
    required this.onDeploymentReady,
    this.onQuickConnect,
    this.onQuickConnectSuccess,
    this.initialHost,
    this.message,
    this.localDeploymentAvailable,
  });

  final Future<void> Function(DeploymentTarget target) onDeploymentReady;
  final Future<String?> Function(String input)? onQuickConnect;
  final void Function()? onQuickConnectSuccess;
  final String? initialHost;
  final String? message;
  final bool? localDeploymentAvailable;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(context.nmtkTokens.sectionGap * 1.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Set up your backend',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                SizedBox(height: context.nmtkTokens.compactGap),
                Text(
                  message ??
                      'Choose where the backend should run. NeuroToolkit '
                          'will install it and connect automatically.',
                ),
                SizedBox(height: context.nmtkTokens.sectionGap * 1.5),
                BackendSetupForm(
                  initialHost: initialHost,
                  localDeploymentAvailable: localDeploymentAvailable,
                  onQuickConnect: onQuickConnect,
                  onQuickConnectSuccess: onQuickConnectSuccess,
                  onDeploymentReady: onDeploymentReady,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
