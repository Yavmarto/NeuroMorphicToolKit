import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/server/connect/connect_notifier.dart';

/// Sign-in form for an already-running server.
///
/// Used both for the very first connection (right after provisioning) and for
/// every additional device (mobile/desktop) logging into the same server.
/// Requires only the server address, the app account, and its password — no
/// terminal, no SSH, no administrator access.
///
/// On app open the caller tries [ConnectNotifier.reconnectOnOpen] first and
/// only shows this form when that fails or there is no saved server.
class ServerConnectScreen extends ConsumerStatefulWidget {
  const ServerConnectScreen({
    super.key,
    this.initialHost,
    this.onNewServer,
    this.onContinueWithoutServer,
    this.showDevBypass = kDebugMode,
    this.embedded = false,
  });

  /// Pre-fill for the server address (overrides the saved host when set, e.g.
  /// right after a fresh provision).
  final String? initialHost;

  /// Called when the user chooses to set up a brand-new server instead.
  final void Function()? onNewServer;

  /// Called when the user chooses to explore/navigate without a server in dev.
  final void Function()? onContinueWithoutServer;

  /// Whether to show the dev-only bypass button. Defaults to [kDebugMode].
  final bool showDevBypass;

  /// Render as dialog/bottom-sheet content (no outer Scaffold) rather than a
  /// full screen. The host popup supplies the surface and scrolling.
  final bool embedded;

  @override
  ConsumerState<ServerConnectScreen> createState() =>
      _ServerConnectScreenState();
}

class _ServerConnectScreenState extends ConsumerState<ServerConnectScreen> {
  final _host = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  String? _hostError;
  String? _usernameError;
  String? _credentialError;

  @override
  void initState() {
    super.initState();
    final state = ref.read(connectNotifierProvider);
    _host.text = widget.initialHost ?? state.savedHost ?? '';
  }

  @override
  void dispose() {
    _host.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final state = ref.watch(connectNotifierProvider);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sign in to your server',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        SizedBox(height: tokens.compactGap),
        const Text(
          'Use the app account created when the server was set up. '
          'No administrator access or terminal needed.',
        ),
        SizedBox(height: tokens.sectionGap * 1.5),
        if (state.phase == ConnectPhase.reconnecting)
          _buildReconnectingPanel(tokens)
        else
          _buildForm(state, tokens),
      ],
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(tokens.sectionGap * 1.5),
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(ConnectState state, NmtkShellTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NmtkSurfaceCard(
          padding: EdgeInsets.all(tokens.sectionGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldLabel('Server address'),
              SizedBox(height: tokens.compactGap),
              NmtkTextInput(
                key: const Key('server-connect-host'),
                controller: _host,
                hintText: 'e.g. 192.168.2.90',
                errorText: _hostError,
                keyboardType: TextInputType.url,
                valueSanitizer: _sanitizeHost,
              ),
              SizedBox(height: tokens.sectionGap),
              _fieldLabel('App account'),
              SizedBox(height: tokens.compactGap),
              NmtkTextInput(
                key: const Key('server-connect-username'),
                controller: _username,
                hintText: 'e.g. alice',
                errorText: _usernameError,
              ),
              SizedBox(height: tokens.sectionGap),
              _fieldLabel('Password'),
              SizedBox(height: tokens.compactGap),
              NmtkTextInput(
                key: const Key('server-connect-password'),
                controller: _password,
                obscureText: _obscurePassword,
                errorText: _credentialError,
                suffix: Tooltip(
                  message: _obscurePassword ? 'Show password' : 'Hide password',
                  child: ZetaIconButton.text(
                    icon: _obscurePassword
                        ? ZetaIcons.visibility_off
                        : ZetaIcons.visibility,
                    semanticLabel: _obscurePassword
                        ? 'Show password'
                        : 'Hide password',
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (state.phase == ConnectPhase.failed &&
            state.failureCause != null) ...[
          SizedBox(height: tokens.sectionGap),
          NmtkStatusBanner(
            key: const Key('server-connect-error'),
            title: 'Could not sign in',
            content: Text(state.failureCause!),
            tone: NmtkTone.danger,
          ),
        ],
        SizedBox(height: tokens.sectionGap),
        _actionArea(
          tokens,
          primary: ZetaButton(
            key: const Key('server-connect-sign-in'),
            onPressed: _connect,
            label: 'Sign in',
          ),
          secondary: widget.onNewServer != null
              ? ZetaButton.text(
                  key: const Key('server-connect-new-server'),
                  onPressed: widget.onNewServer,
                  label: 'Set up a new server',
                )
              : null,
          devAction: widget.showDevBypass
              ? ZetaButton.text(
                  key: const Key('server-connect-continue-offline'),
                  onPressed: _continueWithoutServer,
                  label: 'Continue without server (Dev)',
                )
              : null,
        ),
      ],
    );
  }

  /// Primary action spans the full width with at least a 48dp tap target on
  /// phones; keeps the desktop's compact inline layout (CEL-77).
  Widget _actionArea(
    NmtkShellTokens tokens, {
    required Widget primary,
    Widget? secondary,
    Widget? devAction,
  }) {
    return NmtkAdaptiveLayout(
      breakpoint: NmtkShellTokens.compactBreakpoint,
      desktopBuilder: (context) => Wrap(
        spacing: tokens.compactGap,
        runSpacing: tokens.compactGap,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [primary, ?secondary, ?devAction],
      ),
      mobileBuilder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: primary,
          ),
          if (secondary != null) ...[
            SizedBox(height: tokens.compactGap),
            secondary,
          ],
          if (devAction != null) ...[
            SizedBox(height: tokens.compactGap),
            devAction,
          ],
        ],
      ),
    );
  }

  Widget _buildReconnectingPanel(NmtkShellTokens tokens) {
    return NmtkSurfaceCard(
      key: const Key('server-connect-reconnecting'),
      child: Padding(
        padding: EdgeInsets.all(tokens.sectionGap),
        child: const Row(
          children: [
            ZetaProgressCircle(size: ZetaCircleSizes.s),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Reconnecting to your server…',
                key: Key('server-connect-reconnecting-label'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) =>
      Text(text, style: Theme.of(context).textTheme.titleSmall);

  String _sanitizeHost(String value) {
    final trimmed = value.trim();
    final withoutScheme = trimmed.contains('://')
        ? trimmed.substring(trimmed.indexOf('://') + 3)
        : trimmed;
    return withoutScheme.split('/').first;
  }

  bool _validate() {
    setState(() {
      _hostError = _host.text.trim().isEmpty
          ? 'Enter the server address, for example 192.168.2.90.'
          : null;
      _usernameError = _username.text.trim().isEmpty
          ? 'Enter the app username.'
          : null;
      _credentialError = _password.text.isEmpty ? 'Enter the password.' : null;
    });
    return _hostError == null &&
        _usernameError == null &&
        _credentialError == null;
  }

  Future<void> _connect() async {
    if (!_validate()) return;
    // ServerAccessGate watches connectNotifierProvider and swaps this screen
    // out for the workspace as soon as the phase flips to connected, which
    // can unmount this widget mid-await — so nothing below may touch `ref`.
    await ref
        .read(connectNotifierProvider.notifier)
        .connect(
          ConnectRequest(
            host: _host.text.trim(),
            appUsername: _username.text.trim(),
            credential: _password.text,
          ),
        );
  }

  void _continueWithoutServer() {
    if (widget.onContinueWithoutServer != null) {
      widget.onContinueWithoutServer!();
    } else {
      ref.read(connectNotifierProvider.notifier).continueWithoutServer();
    }
  }
}
