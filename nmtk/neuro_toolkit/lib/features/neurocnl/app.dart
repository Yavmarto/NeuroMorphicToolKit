import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/feature_launch_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/hardware_auto_add_provider.dart';
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
  ProviderSubscription<ConnectionStatus>? _connectionSub;
  ProviderSubscription<Uri>? _backendSub;

  /// Backend host the auto-scan has already run for. Reset is not needed on
  /// reconnect: a failed connection transition forces a fresh scan anyway.
  String _autoScannedHost = '';

  /// One scan at a time: a backend-host switch can race the connection-transition
  /// scan, and both are unawaited, so a latch keeps the two from creating
  /// duplicate targets for the same device.
  bool _scanInFlight = false;

  @override
  void initState() {
    super.initState();
    _router = _buildRouter();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(serverConfigProvider.notifier).checkConnection());
      }
    });
    // Hardware plugged into the connected backend is auto-registered every time
    // that backend connects (CEL-122). Listening for the *transition into*
    // connected — not the value — means a mid-session reconnect after a drop
    // re-scans without a periodic timer, catching devices plugged in between.
    _connectionSub = ref.listenManual<ConnectionStatus>(
      serverConfigProvider.select((state) => state.status),
      (previous, next) {
        if (next != ConnectionStatus.connected) return;
        unawaited(
          _autoScanHardwareOnConnect(
            reconnect: previous == ConnectionStatus.failed,
          ),
        );
      },
    );
    // Connecting to a *different* backend while this surface stays mounted
    // (e.g. "Edit server" then picking another host) never flips status away
    // from connected, so the status listener above would never fire. Watch the
    // backend host itself and scan again once it changes.
    _backendSub = ref.listenManual<Uri>(
      featureLaunchContextProvider.select((context) => context.backendUri),
      (previous, next) {
        final sameHost =
            previous?.host.trim().toLowerCase() ==
            next.host.trim().toLowerCase();
        if (sameHost) return;
        if (ref.read(serverConfigProvider).status !=
            ConnectionStatus.connected) {
          return;
        }
        unawaited(_autoScanHardwareOnConnect(reconnect: true));
      },
    );
  }

  /// Runs the same-host hardware auto-scan against the connected backend.
  ///
  /// Fires on the first connect to a backend and again after a dropped
  /// connection comes back (or the connected backend host changes). A scan
  /// failure must never block or toast the connection flow, so every error is
  /// swallowed here — the manual "Scan for hardware" action in the
  /// manage-targets dialog surfaces failures instead.
  Future<void> _autoScanHardwareOnConnect({required bool reconnect}) async {
    if (_scanInFlight) return;
    final backendUri = ref.read(featureLaunchContextProvider).backendUri;
    final host = backendUri.host.trim().toLowerCase();
    if (host.isEmpty || host == 'invalid-root-context') return;
    if (!reconnect && _autoScannedHost == host) return;
    _scanInFlight = true;
    final scanner = ref.read(hardwareAutoAddScannerProvider);
    try {
      await scanner.run();
      _autoScannedHost = host;
    } catch (_) {
      // Best-effort: the next connect or a manual scan retries.
    } finally {
      _scanInFlight = false;
    }
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
    _connectionSub?.close();
    _backendSub?.close();
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
