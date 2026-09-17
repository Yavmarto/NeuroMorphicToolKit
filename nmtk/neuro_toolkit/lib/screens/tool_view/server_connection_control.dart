import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/providers/riverpod_providers.dart';

class InlineServerConnectionControl extends ConsumerWidget {
  const InlineServerConnectionControl({
    super.key,
    required this.onPressed,
    this.iconOnly = false,
  });

  final VoidCallback onPressed;
  final bool iconOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controlApi = ref.watch(selectedControlApiServiceProvider);
    final connection = ref.watch(serverConnectionProvider);
    final backendVersion = ref.watch(backendVersionProvider).value;
    final moduleBackendDegraded = ref.watch(neurocnlBackendDegradedProvider);
    final moduleState = ref.watch(moduleProvider).value;
    final anyModuleDegraded = moduleState?.modules.any(
          (module) => module.status == ModuleStatus.degraded,
        ) ??
        false;
    final effectiveConnection = controlApi == null
        ? const ServerConnectionState.disconnected()
        : connection.baseUri == controlApi.baseUri
        ? connection
        : ServerConnectionState(
            phase: ServerConnectionPhase.checking,
            baseUri: controlApi.baseUri,
          );
    final hostLabel = controlApi?.baseUri.host ?? 'Connect server';
    final serverLabel = backendVersion != null ? 'v$backendVersion' : hostLabel;
    final unhealthyLabel = moduleBackendDegraded
        ? 'Module backend degraded'
        : anyModuleDegraded
        ? 'A module is degraded'
        : null;
    final tooltipLabel = unhealthyLabel ?? effectiveConnection.label;
    return Tooltip(
      message: 'Server connection · $tooltipLabel',
      child: NmtkStatusBadge(
        key: ValueKey<String>(
          iconOnly
              ? 'inline-server-connection-icon'
              : 'inline-server-connection',
        ),
        label: serverLabel,
        semanticsLabel: 'Server connection: $serverLabel, $tooltipLabel',
        icon: ZetaIcons.radio_button_checked,
        compact: iconOnly,
        tone: _toneFor(
          effectiveConnection.phase,
          moduleBackendDegraded || anyModuleDegraded,
        ),
        onPressed: onPressed,
      ),
    );
  }

  NmtkTone _toneFor(ServerConnectionPhase phase, bool unhealthy) {
    final tone = switch (phase) {
      ServerConnectionPhase.checking => NmtkTone.info,
      ServerConnectionPhase.connected => NmtkTone.success,
      ServerConnectionPhase.unstable => NmtkTone.warning,
      ServerConnectionPhase.disconnected => NmtkTone.danger,
    };
    // The launcher control-API ping, the neurocnl module's own /health probe,
    // and any individual module's degraded status are independent signals;
    // any of them reporting trouble should turn the dot orange, unless the
    // launcher ping already escalated it to red.
    if (unhealthy && tone != NmtkTone.danger) {
      return NmtkTone.warning;
    }
    return tone;
  }
}
