import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/server_config_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/routing/app_router.dart';

/// NeuroStudio's routed product surface inside the root NMTK application.
///
/// This widget deliberately does not create a [MaterialApp] or theme provider.
/// The root executable owns those process-wide concerns and supplies the
/// launcher connection used by every feature surface.
class NeurocnlStudioSurface extends ConsumerStatefulWidget {
  const NeurocnlStudioSurface({
    super.key,
    this.initialLocation = '/',
    this.workspaceHeaderAction,
    required this.onEditServer,
    this.onReportError,
  });

  final String initialLocation;

  /// An optional host-owned control shown beside the Studio workspace name.
  final Widget? workspaceHeaderAction;

  /// Root-owned action that opens the suite server connection popup.
  final Future<void> Function() onEditServer;

  /// Root-owned handling for feature errors that cannot be resolved locally.
  final NmtkFeatureErrorReporter? onReportError;

  @override
  ConsumerState<NeurocnlStudioSurface> createState() =>
      _NeurocnlStudioSurfaceState();
}

class _NeurocnlStudioSurfaceState extends ConsumerState<NeurocnlStudioSurface> {
  late GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = _buildRouter();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(serverConfigProvider.notifier).checkConnection());
      }
    });
  }

  @override
  void didUpdateWidget(covariant NeurocnlStudioSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialLocation != oldWidget.initialLocation) {
      final previousRouter = _router;
      _router = _buildRouter();
      previousRouter.dispose();
    }
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  GoRouter _buildRouter() {
    return createAppRouter(
      initialLocation: widget.initialLocation,
      workspaceHeaderAction: widget.workspaceHeaderAction,
      onEditServer: widget.onEditServer,
      onRouteError: widget.onReportError,
    );
  }

  @override
  Widget build(BuildContext context) => Router.withConfig(config: _router);
}
