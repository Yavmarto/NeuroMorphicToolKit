import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/server/connect/connect_notifier.dart';
import 'package:neuro_toolkit/screens/server_connect_screen.dart';
import 'package:neuro_toolkit/screens/server_setup_screen.dart';

/// Decides between the workspace and the connect/setup forms at app start.
///
/// On mount it tries [ConnectNotifier.reconnectOnOpen]: when the saved
/// credential still works it resolves to `connected` fast and [child] (the
/// workspace) is shown immediately — the user never sees a form. When there
/// is no saved server, or reconnect fails, the connect form is shown instead;
/// from there the user can either sign in or set up a brand-new server.
///
/// This is the mount point that replaces the old setup popup. It is now
/// mounted above `LauncherAppHost` in `neuro_toolkit_app.dart`.
class ServerAccessGate extends ConsumerStatefulWidget {
  const ServerAccessGate({super.key, required this.child});

  /// The workspace surface shown once a session is connected.
  final Widget child;

  @override
  ConsumerState<ServerAccessGate> createState() => _ServerAccessGateState();
}

class _ServerAccessGateState extends ConsumerState<ServerAccessGate> {
  String? _provisionedHost;
  bool _reconnectTriggered = false;

  @override
  void initState() {
    super.initState();
    _reconnectTriggered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Fire-and-forget; the notifier updates [connectNotifierProvider], which
      // this widget watches to decide what to render.
      ref.read(connectNotifierProvider.notifier).reconnectOnOpen();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(connectNotifierProvider);
    final tokens = NmtkShellTokens.of(context);

    if (!_reconnectTriggered) {
      return _fullPage(
        tokens,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ZetaProgressCircle(size: ZetaCircleSizes.s),
          ],
        ),
      );
    }

    return switch (state.phase) {
      ConnectPhase.connected => widget.child,
      ConnectPhase.reconnecting => _fullPage(
        tokens,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ZetaProgressCircle(size: ZetaCircleSizes.s),
            SizedBox(width: 12),
            Text('Reconnecting to your server…'),
          ],
        ),
      ),
      ConnectPhase.failed || ConnectPhase.idle => _connectSurface(tokens),
    };
  }

  Widget _connectSurface(NmtkShellTokens tokens) {
    return ServerConnectScreen(
      initialHost: _provisionedHost,
      onNewServer: _openSetup,
    );
  }

  void _openSetup() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServerSetupScreen(
          initialHost: _provisionedHost,
          onProvisioned: (result) {
            setState(() => _provisionedHost = result.host);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Widget _fullPage(NmtkShellTokens tokens, {required Widget child}) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: EdgeInsets.all(tokens.sectionGap * 1.5),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
