import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/backend_setup/backend_setup_screen.dart';

class InAppBackendSetupScreen extends ConsumerWidget {
  const InAppBackendSetupScreen({
    super.key,
    required this.onComplete,
    this.initialHost,
    this.message,
  });

  final VoidCallback onComplete;
  final String? initialHost;
  final String? message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(launcherBootstrapProvider.notifier);
    return BackendSetupScreen(
      initialHost: initialHost,
      message: message,
      onQuickConnect: (input) async {
        final error = await notifier.connectToLauncher(input);
        if (error != null) return error;
        await _refreshServerBackedProviders(ref);
        onComplete();
        return null;
      },
      onDeploymentReady: (target) async {
        await notifier.connectToDeploymentTarget(target);
        await _refreshServerBackedProviders(ref);
        onComplete();
      },
    );
  }

  Future<void> _refreshServerBackedProviders(WidgetRef ref) async {
    ref.invalidate(controlApiServiceProvider);
    await Future.wait([
      ref.refresh(moduleProvider.future),
      ref.refresh(workspaceProvider.future),
    ]);
    ref.invalidate(serverConnectionProvider);
    ref.invalidate(backendVersionProvider);
    ref.invalidate(backendUpdateProvider);
  }
}
