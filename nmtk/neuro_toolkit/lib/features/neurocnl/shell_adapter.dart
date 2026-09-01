import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

import 'package:neuro_toolkit/features/neurocnl/app.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/feature_launch_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

class NeurocnlShellAdapter extends StatefulWidget {
  const NeurocnlShellAdapter({
    super.key,
    required this.launchContext,
    this.initializeFeature,
  });

  /// Root-owned launch inputs for this embedded feature surface.
  final NmtkFeatureLaunchContext launchContext;

  /// Test seam for the feature-owned workspace persistence preparation.
  ///
  /// Production callers leave this null, which uses [ServerConfigService].
  final Future<void> Function()? initializeFeature;

  @override
  State<NeurocnlShellAdapter> createState() => _NeurocnlShellAdapterState();
}

class _NeurocnlShellAdapterState extends State<NeurocnlShellAdapter> {
  late final Future<void> _initialization = _initialize();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _publishLaunchContext();
  }

  @override
  void didUpdateWidget(NeurocnlShellAdapter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.launchContext, widget.launchContext)) {
      _publishLaunchContext();
    }
  }

  /// Publishes [widget.launchContext] onto the app's single root
  /// [featureLaunchContextProvider] instance.
  ///
  /// This mutates the existing (root-scoped) provider in place rather than
  /// overriding it on a nested `ProviderScope`: most Studio Notifiers read
  /// the derived `apiClientProvider` lazily from inside their own methods,
  /// which resolves against the root container regardless of any override
  /// declared on a child scope further down the tree. Mutating the root
  /// value directly is what actually reaches every consumer.
  ///
  /// Deferred to a post-frame callback: Riverpod forbids modifying a
  /// provider synchronously from within a widget lifecycle method
  /// (`didChangeDependencies`/`didUpdateWidget`/etc.) — doing so throws
  /// "Tried to modify a provider while the widget tree was building."
  void _publishLaunchContext() {
    final launchContext = widget.launchContext;
    final container = ProviderScope.containerOf(context, listen: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      container.read(featureLaunchContextProvider.notifier).publish(launchContext);
    });
  }

  Future<void> _initialize() async {
    try {
      await (widget.initializeFeature ?? ServerConfigService.initialize)();
    } on Object catch (_) {
      unawaited(
        widget.launchContext.onReportError(
          NmtkFeatureErrorEvent(
            moduleId: widget.launchContext.moduleId,
            kind: NmtkFeatureErrorKind.unexpected,
            message: 'NeuroStudio workspace storage could not be prepared.',
          ),
        ),
      );
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(
              child: Text('NeuroStudio could not prepare its workspace.'),
            ),
          );
        }
        return ProviderScope(
          overrides: [
            workspaceBootstrapProvider.overrideWithValue(
              WorkspaceBootstrap(
                initialLocation: widget.launchContext.initialLocation,
                initialRestoreState: widget.launchContext.restorationState,
              ),
            ),
          ],
          child: NeurocnlStudioSurface(
            initialLocation: widget.launchContext.initialLocation,
            workspaceHeaderAction: widget.launchContext.workspaceHeaderAction,
            onEditServer: widget.launchContext.onEditServer,
            onReportError: widget.launchContext.onReportError,
          ),
        );
      },
    );
  }
}
