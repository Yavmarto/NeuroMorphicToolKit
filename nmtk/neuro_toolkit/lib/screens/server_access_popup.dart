import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/server/provision/provision_service.dart';
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
  final flow = _ServerAccessFlow(initialHost: initialHost, isSheet: useMobileSheet);

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
      builder: (_) => _ServerAccessSheetSurface(child: flow),
    );
  }

  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (_) => _ServerAccessDialogSurface(child: flow),
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
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Zeta.of(context).colors.borderSubtle,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
          ),
          const SizedBox(height: 8),
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
        const SizedBox(height: 8),
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

/// Desktop/wide dialog surface for the flow. Uses the sanctioned dialog radius
/// and a fixed but scroll-friendly size so the forms never bleed past the
/// viewport on short windows.
class _ServerAccessDialogSurface extends StatelessWidget {
  const _ServerAccessDialogSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    return Dialog(
      backgroundColor: colors.surfaceDefault,
      shape: RoundedRectangleBorder(
        borderRadius: NmtkDesignTokens.dialogShape,
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: SizedBox(width: 680, height: 720, child: child),
      ),
    );
  }
}

/// Phone bottom-sheet surface for the flow, with a drag handle and rounded
/// top corners.
class _ServerAccessSheetSurface extends StatelessWidget {
  const _ServerAccessSheetSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final colors = Zeta.of(context).colors;
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(tokens.radiusLg)),
      child: ColoredBox(
        color: colors.surfaceDefault,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.94,
          child: SafeArea(top: false, child: child),
        ),
      ),
    );
  }
}
