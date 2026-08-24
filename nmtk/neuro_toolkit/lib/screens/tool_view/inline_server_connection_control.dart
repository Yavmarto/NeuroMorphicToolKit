part of '../tool_view.dart';

class _InlineServerConnectionControl extends ConsumerWidget {
  const _InlineServerConnectionControl({
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
    return Tooltip(
      message: 'Server connection · ${effectiveConnection.label}',
      child: NmtkStatusBadge(
        key: ValueKey<String>(
          iconOnly
              ? 'inline-server-connection-icon'
              : 'inline-server-connection',
        ),
        label: serverLabel,
        semanticsLabel:
            'Server connection: $serverLabel, ${effectiveConnection.label}',
        icon: ZetaIcons.radio_button_checked,
        compact: iconOnly,
        tone: _toneForPhase(effectiveConnection.phase),
        onPressed: onPressed,
      ),
    );
  }

  NmtkTone _toneForPhase(ServerConnectionPhase phase) => switch (phase) {
        ServerConnectionPhase.checking => NmtkTone.info,
        ServerConnectionPhase.connected => NmtkTone.success,
        ServerConnectionPhase.unstable => NmtkTone.warning,
        ServerConnectionPhase.disconnected => NmtkTone.danger,
      };
}
