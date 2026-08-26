import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/backend_setup.dart';

const double _mobileSetupBreakpoint = 840;

final startupServerSetupPromptProvider =
    NotifierProvider<StartupServerSetupPromptNotifier, bool>(
      StartupServerSetupPromptNotifier.new,
    );

class StartupServerSetupPromptNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void markHandled() => state = true;
}

Future<void> showAdaptiveServerSetupPopup(
  BuildContext context, {
  String? initialHost,
  String? message,
}) async {
  final useMobileSheet =
      MediaQuery.sizeOf(context).width < _mobileSetupBreakpoint;
  var routeOpen = true;

  Widget buildSurface(BuildContext modalContext, bool isSheet) {
    void close() {
      if (!routeOpen) return;
      final route = ModalRoute.of(modalContext);
      if (route?.isCurrent != true) return;
      routeOpen = false;
      Navigator.of(modalContext).pop();
    }

    return ServerSetupPopupSurface(
      initialHost: initialHost,
      message: message,
      isSheet: isSheet,
      onClose: close,
    );
  }

  if (useMobileSheet) {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => SizedBox(
        height: MediaQuery.sizeOf(modalContext).height * 0.94,
        child: buildSurface(modalContext, true),
      ),
    );
  } else {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (modalContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: NmtkDesignTokens.dialogShape,
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
          child: SizedBox(
            width: 900,
            height: 700,
            child: buildSurface(modalContext, false),
          ),
        ),
      ),
    );
  }
  routeOpen = false;
}

class ServerSetupPopupSurface extends ConsumerWidget {
  const ServerSetupPopupSurface({
    super.key,
    required this.isSheet,
    required this.onClose,
    this.initialHost,
    this.message,
  });

  final bool isSheet;
  final VoidCallback onClose;
  final String? initialHost;
  final String? message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controlApi = ref.watch(selectedControlApiServiceProvider);
    final connection = ref.watch(serverConnectionProvider);
    final version = ref.watch(backendVersionProvider).value;
    final effectiveConnection = controlApi == null
        ? const ServerConnectionState.disconnected()
        : connection.baseUri == controlApi.baseUri
        ? connection
        : ServerConnectionState(
            phase: ServerConnectionPhase.checking,
            baseUri: controlApi.baseUri,
          );
    final tokens = NmtkShellTokens.of(context);
    final hostLabel =
        controlApi?.baseUri.host ??
        _displayHost(initialHost) ??
        'No server selected';
    final versionLabel = switch (version) {
      'dev' => 'Development build',
      final String value => 'v$value',
      null => null,
    };
    final headerLabel = [
      hostLabel,
      ?versionLabel,
      effectiveConnection.label,
    ].join(' · ');

    final borderRadius = isSheet
        ? BorderRadius.vertical(top: Radius.circular(tokens.radiusLg))
        : BorderRadius.zero;
    return ClipRRect(
      borderRadius: borderRadius,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.circle, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                      color: _connectionColor(
                        effectiveConnection.phase,
                        tokens,
                      ),
                      size: 14,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        headerLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Tooltip(
                      message: 'Close',
                      child: ZetaIconButton.text(
                        icon: ZetaIcons.close,
                        semanticLabel: 'Close',
                        onPressed: onClose,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: InAppBackendSetupScreen(
                  initialHost: _displayHost(initialHost),
                  message: message,
                  onComplete: onClose,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String? _displayHost(String? input) {
  final value = input?.trim() ?? '';
  if (value.isEmpty) return null;
  final uri = Uri.tryParse(value.contains('://') ? value : 'http://$value');
  return uri?.host.isNotEmpty == true ? uri!.host : value;
}

Color _connectionColor(ServerConnectionPhase phase, NmtkShellTokens tokens) {
  return switch (phase) {
    ServerConnectionPhase.checking => tokens.runningColor,
    ServerConnectionPhase.connected => tokens.healthyColor,
    ServerConnectionPhase.unstable => tokens.warningColor,
    ServerConnectionPhase.disconnected => tokens.errorColor,
  };
}
