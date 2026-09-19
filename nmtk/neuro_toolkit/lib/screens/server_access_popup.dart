import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/server/provision/provision_service.dart';
import 'package:neuro_toolkit/screens/server_access_dialog_surface.dart';
import 'package:neuro_toolkit/screens/server_access_sheet_surface.dart';
import 'package:neuro_toolkit/screens/server_connect_screen.dart';
import 'package:neuro_toolkit/screens/server_setup_screen.dart';

/// Shows the sign-in / set-up-a-new-server flow as an adaptive popup over the
/// still-visible workspace surface: a centered dialog on desktop and wide
/// windows, a bottom sheet on phones (same breakpoint convention as the old
/// server setup popup).
///
/// Returns when the popup is closed (dismissed, cancelled, or resolved by the
/// connection state — the caller decides when to reopen).
Future<void> showServerAccessPopup(
  BuildContext context, {
  String? initialHost,
}) {
  final useMobileSheet =
      MediaQuery.sizeOf(context).width < NmtkShellTokens.compactBreakpoint;
  final flow = _ServerAccessFlow(
    initialHost: initialHost,
    isSheet: useMobileSheet,
  );

  if (useMobileSheet) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      // ZETA-MIGRATION-EXEMPT: transparent (no fill) — Zeta has no transparent token
      backgroundColor: Colors.transparent,
      builder: (_) => ServerAccessSheetSurface(child: flow),
    );
  }

  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (_) => ServerAccessDialogSurface(child: flow),
  );
}

enum _FlowMode { connect, setup }

/// Hosts the sign-in and server-setup forms and lets the user move between
/// them in place — no route pushes, so the whole flow stays inside one popup.
class _ServerAccessFlow extends ConsumerStatefulWidget {
  const _ServerAccessFlow({this.initialHost, required this.isSheet});

  final String? initialHost;
  final bool isSheet;

  @override
  ConsumerState<_ServerAccessFlow> createState() => _ServerAccessFlowState();
}

class _ServerAccessFlowState extends ConsumerState<_ServerAccessFlow> {
  _FlowMode _mode = _FlowMode.connect;
  String? _provisionedHost;

  void _showSetup() => setState(() => _mode = _FlowMode.setup);

  void _backToConnect() => setState(() => _mode = _FlowMode.connect);

  void _close() {
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final screen = switch (_mode) {
      _FlowMode.connect => ServerConnectScreen(
        initialHost: _provisionedHost ?? widget.initialHost,
        embedded: true,
        onNewServer: _showSetup,
      ),
      _FlowMode.setup => ServerSetupScreen(
        initialHost: _provisionedHost ?? widget.initialHost,
        embedded: true,
        onBack: _backToConnect,
        onProvisioned: (ProvisionResult result) {
          setState(() {
            _provisionedHost = result.host;
            _mode = _FlowMode.connect;
          });
        },
      ),
    };

    return Column(
      children: [
        if (widget.isSheet) ...[
          SizedBox(height: tokens.compactGap),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Zeta.of(context).colors.borderSubtle,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
          ),
          SizedBox(height: tokens.compactGap),
        ],
        Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.sectionGap),
          child: Row(
            children: [
              if (_mode == _FlowMode.setup)
                ZetaButton.text(
                  key: const Key('server-setup-back'),
                  onPressed: _backToConnect,
                  label: 'Back',
                  leadingIcon: ZetaIcons.arrow_back,
                )
              else
                const SizedBox(width: 48),
              const Spacer(),
              Tooltip(
                message: 'Close',
                child: ZetaIconButton.text(
                  icon: ZetaIcons.close,
                  semanticLabel: 'Close',
                  onPressed: _close,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: tokens.compactGap),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(tokens.sectionGap * 1.5),
            child: screen,
          ),
        ),
      ],
    );
  }
}
