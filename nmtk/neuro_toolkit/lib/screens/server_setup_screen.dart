import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/server/provision/provision_notifier.dart';
import 'package:neuro_toolkit/features/server/provision/provision_service.dart';

/// One-time server setup (provision) form.
///
/// The end user never opens a terminal, never types an SSH/sudo/docker
/// command. They enter a server address, the administrator account that has
/// permission to install software, a password or key for that account, and
/// which engine to use (Docker or Podman). Everything else — installing the
/// engine if missing, running the install, minting the app credential — is
/// handled automatically and reported here in plain English.
class ServerSetupScreen extends ConsumerStatefulWidget {
  const ServerSetupScreen({super.key, this.initialHost, this.onProvisioned});

  /// Pre-fill for the server address (e.g. from a prior attempt).
  final String? initialHost;

  /// Called once provisioning succeeds with the provisioned host + app user.
  final void Function(ProvisionResult result)? onProvisioned;

  @override
  ConsumerState<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends ConsumerState<ServerSetupScreen> {
  final _host = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _privateKey = TextEditingController();
  String _authMethod = 'password';
  String _engine = 'docker';
  bool _obscurePassword = true;
  String? _hostError;
  String? _usernameError;
  String? _credentialError;

  @override
  void initState() {
    super.initState();
    _host.text = widget.initialHost ?? '';
  }

  @override
  void dispose() {
    _host.dispose();
    _username.dispose();
    _password.dispose();
    _privateKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final state = ref.watch(provisionNotifierProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(tokens.sectionGap * 1.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Set up your server',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  SizedBox(height: tokens.compactGap),
                  const Text(
                    'This happens once per server. Tell us where it lives and '
                    'the administrator account that can install software, and '
                    'NeuroToolkit does the rest automatically — no terminal '
                    'needed.',
                  ),
                  SizedBox(height: tokens.sectionGap * 1.5),
                  if (state.failure != null)
                    _buildFailurePanel(state.failure!, tokens)
                  else if (state.result != null)
                    _buildSuccessPanel(state.result!, tokens)
                  else if (state.isRunning)
                    _buildRunningPanel(state, tokens)
                  else
                    _buildForm(tokens),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(NmtkShellTokens tokens) {
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
                key: const Key('server-setup-host'),
                controller: _host,
                hintText: 'e.g. 192.168.2.90',
                errorText: _hostError,
                keyboardType: TextInputType.url,
                valueSanitizer: _sanitizeHost,
              ),
              SizedBox(height: tokens.sectionGap),
              _fieldLabel('Administrator account'),
              SizedBox(height: tokens.compactGap),
              NmtkTextInput(
                key: const Key('server-setup-username'),
                controller: _username,
                hintText: 'e.g. moosebun2',
                errorText: _usernameError,
              ),
              SizedBox(height: tokens.compactGap),
              const Text(
                'This account must be allowed to install software. Do not '
                'use the root account.',
              ),
              SizedBox(height: tokens.sectionGap),
              const Text('How does this account sign in?'),
              SizedBox(height: tokens.compactGap),
              _choiceRow(
                tokens,
                children: [
                  _authChoice('Use a password', 'password'),
                  _authChoice('Use a key', 'key'),
                ],
              ),
              SizedBox(height: tokens.compactGap),
              if (_authMethod == 'password') ...[
                _fieldLabel('Password'),
                SizedBox(height: tokens.compactGap),
                NmtkTextInput(
                  key: const Key('server-setup-password'),
                  controller: _password,
                  obscureText: _obscurePassword,
                  errorText: _credentialError,
                  suffix: Tooltip(
                    message: _obscurePassword
                        ? 'Show password'
                        : 'Hide password',
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
              ] else ...[
                _fieldLabel('Private key'),
                SizedBox(height: tokens.compactGap),
                NmtkCodeTextArea(
                  key: const Key('server-setup-private-key'),
                  controller: _privateKey,
                  minLines: 4,
                  maxLines: 8,
                  errorText: _credentialError,
                ),
              ],
              SizedBox(height: tokens.sectionGap),
              const Text('Which container engine?'),
              SizedBox(height: tokens.compactGap),
              const Text(
                'If the one you pick is not installed yet, NeuroToolkit '
                'installs it automatically.',
              ),
              SizedBox(height: tokens.compactGap),
              _choiceRow(
                tokens,
                children: [
                  _engineChoice('Docker', 'docker'),
                  _engineChoice('Podman', 'podman'),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: tokens.sectionGap),
        const Text(
          'The administrator credential is used once to set up the server and '
          'is never saved. After setup you will sign in with a separate app '
          'account.',
        ),
        SizedBox(height: tokens.compactGap),
        _actionArea(
          tokens,
          primary: ZetaButton(
            key: const Key('server-setup-provision'),
            onPressed: _provision,
            label: 'Set up server',
          ),
        ),
      ],
    );
  }

  /// Lays out mutually-exclusive choices side by side on wide screens and
  /// stacked on phones — no side-by-side field pairs below the compact
  /// breakpoint (CEL-77).
  Widget _choiceRow(NmtkShellTokens tokens, {required List<Widget> children}) {
    return NmtkAdaptiveLayout(
      breakpoint: NmtkShellTokens.compactBreakpoint,
      desktopBuilder: (context) => Wrap(
        spacing: tokens.compactGap,
        runSpacing: tokens.compactGap,
        children: children,
      ),
      mobileBuilder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: tokens.compactGap),
            children[i],
          ],
        ],
      ),
    );
  }

  /// Primary action spans the full width with at least a 48dp tap target on
  /// phones; keeps the desktop's compact inline layout (CEL-77).
  Widget _actionArea(
    NmtkShellTokens tokens, {
    required Widget primary,
    Widget? secondary,
  }) {
    return NmtkAdaptiveLayout(
      breakpoint: NmtkShellTokens.compactBreakpoint,
      desktopBuilder: (context) => Wrap(
        spacing: tokens.compactGap,
        runSpacing: tokens.compactGap,
        children: [primary, ?secondary],
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
        ],
      ),
    );
  }

  Widget _buildRunningPanel(ProvisionState state, NmtkShellTokens tokens) {
    final phaseLabel = state.phaseLabel ?? 'Setting up your server…';

    return NmtkSurfaceCard(
      key: const Key('server-setup-progress'),
      child: Padding(
        padding: EdgeInsets.all(tokens.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(ZetaIcons.sync, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _phaseLabel(phaseLabel),
                    key: const Key('server-setup-phase-label'),
                  ),
                ),
              ],
            ),
            SizedBox(height: tokens.compactGap),
            ZetaProgressBar.standard(
              progress: (state.progress ?? 0).clamp(0.0, 1.0),
              isThin: true,
            ),
            SizedBox(height: tokens.compactGap),
            const Text(
              'This can take a few minutes. You can close the app and check '
              'back — setup continues in the background.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailurePanel(ProvisionFailure failure, NmtkShellTokens tokens) {
    final cause = _plainEnglishCause(failure.cause);
    return NmtkSurfaceCard(
      key: const Key('server-setup-failure'),
      child: Padding(
        padding: EdgeInsets.all(tokens.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NmtkStatusBanner(
              title: 'We could not set up the server',
              content: Text(cause),
              tone: NmtkTone.danger,
            ),
            SizedBox(height: tokens.compactGap),
            const Text(
              'Check the server address and the administrator account and '
              'try again. Your data is not affected.',
            ),
            SizedBox(height: tokens.compactGap),
            _actionArea(
              tokens,
              primary: failure.retryable
                  ? ZetaButton(
                      key: const Key('server-setup-retry'),
                      onPressed: _provision,
                      label: 'Try again',
                    )
                  : const SizedBox.shrink(),
              secondary: ZetaButton.text(
                key: const Key('server-setup-change-details'),
                onPressed: () =>
                    ref.read(provisionNotifierProvider.notifier).reset(),
                label: 'Change details',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessPanel(ProvisionResult result, NmtkShellTokens tokens) {
    final appUsername = result.appUsername;
    return NmtkSurfaceCard(
      key: const Key('server-setup-success'),
      child: Padding(
        padding: EdgeInsets.all(tokens.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NmtkStatusBanner(
              title: 'Your server is set up',
              content: Text(
                appUsername.isEmpty
                    ? '${result.host} is ready to use.'
                    : '${result.host} is ready. Sign in with your app account '
                          '($appUsername) to start using it.',
              ),
              tone: NmtkTone.success,
            ),
            if (widget.onProvisioned != null) ...[
              SizedBox(height: tokens.compactGap),
              _actionArea(
                tokens,
                primary: ZetaButton(
                  key: const Key('server-setup-continue'),
                  onPressed: () => widget.onProvisioned!(result),
                  label: 'Continue',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _authChoice(String label, String value) {
    return ZetaRadio<String>(
      label: Text(label),
      value: value,
      groupValue: _authMethod,
      onChanged: (selected) {
        if (selected == null) return;
        setState(() {
          _authMethod = selected;
          _credentialError = null;
        });
      },
    );
  }

  Widget _engineChoice(String label, String value) {
    return ZetaRadio<String>(
      label: Text(label),
      value: value,
      groupValue: _engine,
      onChanged: (selected) {
        if (selected != null) setState(() => _engine = selected);
      },
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
    final host = _host.text.trim();
    final username = _username.text.trim();
    final validHost = _canonicalIpv4(host) != null;
    setState(() {
      _hostError = validHost
          ? null
          : 'Enter the server address, for example 192.168.2.90.';
      _usernameError = username.isEmpty
          ? 'Enter the administrator username.'
          : username.toLowerCase() == 'root'
          ? 'Use a normal account that can install software — not root.'
          : null;
      _credentialError = _credentialEmpty
          ? _authMethod == 'password'
                ? 'Enter the password.'
                : 'Enter the private key.'
          : null;
    });
    return validHost && _usernameError == null && _credentialError == null;
  }

  bool get _credentialEmpty => _authMethod == 'password'
      ? _password.text.isEmpty
      : _privateKey.text.trim().isEmpty;

  Future<void> _provision() async {
    if (!_validate()) return;
    final credential = _authMethod == 'password'
        ? ProvisionCredential.password(_password.text)
        : ProvisionCredential.privateKey(_privateKey.text.trim());
    await ref
        .read(provisionNotifierProvider.notifier)
        .provision(
          ProvisionRequest(
            host: _host.text.trim(),
            sudoUser: _username.text.trim(),
            credential: credential,
            engine: _engine,
          ),
        );
  }

  /// Maps internal provisioning phase labels to plain-English step text, so
  /// the user never reads SSH/administrator/deploy jargon.
  String _phaseLabel(String stageLabel) {
    final normalized = stageLabel.toLowerCase();
    if (normalized.contains('queued')) {
      return 'Preparing to set up your server…';
    }
    if (normalized.contains('connecting with administrator access')) {
      return 'Connecting to your server…';
    }
    if (normalized.contains('checking administrator access')) {
      return 'Checking the administrator account…';
    }
    if (normalized.contains('bootstrapping')) {
      return 'Preparing the account that runs your server…';
    }
    if (normalized.contains('deployment account')) {
      return 'Finishing setup on your server…';
    }
    if (normalized.contains('down')) {
      return 'Stopping old versions of the backend, if any…';
    }
    if (normalized.contains('pull') || normalized.contains('download')) {
      return 'Downloading the latest software…';
    }
    if (normalized.contains('up -d') || normalized.contains('starting')) {
      return 'Starting your backend…';
    }
    if (normalized.contains('health') || normalized.contains('check')) {
      return 'Making sure everything is running…';
    }
    return stageLabel.isEmpty ? 'Setting up your server…' : stageLabel;
  }

  /// Builds a plain-English failure cause from the notifier's failure text,
  /// filtering out any internal markers so the user never sees a stack trace.
  String _plainEnglishCause(String? cause) {
    final recovery = (cause ?? '').trim();
    if (recovery.isNotEmpty && !_looksInternal(recovery)) return recovery;
    return 'The server could not be set up. Check the address and the '
        'administrator account, then try again.';
  }

  bool _looksInternal(String text) {
    const markers = [
      'flutter:',
      'exception:',
      'stacktrace',
      'bad state',
      'formatexception',
      '#0 ',
    ];
    final lowered = text.toLowerCase();
    return markers.any(lowered.contains);
  }

  static String? _canonicalIpv4(String value) {
    final parts = value.trim().split('.');
    if (parts.length != 4) return null;
    final normalized = <String>[];
    for (final part in parts) {
      if (!RegExp(r'^\d{1,3}$').hasMatch(part)) return null;
      final number = int.tryParse(part);
      if (number == null || number > 255) return null;
      normalized.add(number.toString());
    }
    return normalized.join('.');
  }
}
