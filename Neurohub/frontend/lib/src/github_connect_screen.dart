import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

import 'package:neurohub_frontend/src/github_connect_theme.dart';
import 'package:neurohub_frontend/src/github_device_flow_client.dart';
import 'package:neurohub_frontend/src/github_link_launcher.dart';
import 'package:neurohub_frontend/src/github_token_storage.dart';

/// 'Connect GitHub' screen that runs Neurohub's OAuth Device Flow.
///
/// Flow:
///  1. Fetch `GET /api/neurohub/oauth/config` to confirm the provider is
///     configured.
///  2. Start the device flow via `POST /api/neurohub/oauth/device/start`.
///  3. Show the returned `user_code` and `verification_uri` (with a copy
///     button and a tappable link) while polling
///     `POST /api/neurohub/oauth/device/poll` until GitHub authorizes the
///     request or the session expires / is denied.
///  4. On success, persist the access token through [tokenStorage] and report
///     it via [onConnected].
///
/// Styling follows the `NmtkShellTokens` conventions from
/// `nmtk/neuro_toolkit/lib/ui_core/` (see [GithubConnectTokens]). The widget
/// is state-management-agnostic: inject [client], [tokenStorage], and
/// [linkLauncher] so tests can substitute fakes.
class GithubConnectScreen extends StatefulWidget {
  const GithubConnectScreen({
    super.key,
    required this.client,
    required this.tokenStorage,
    this.linkLauncher = const PlatformGithubLinkLauncher(),
    this.onConnected,
    this.onDisconnected,
  });

  /// Device-flow API client (mock in tests).
  final GithubDeviceFlowClient client;

  /// Where the resulting GitHub access token is persisted between sessions.
  final GithubTokenStorage tokenStorage;

  /// Opens the verification URI in the browser (mock in tests).
  final GithubLinkLauncher linkLauncher;

  /// Invoked with the access token once the device flow succeeds.
  final ValueChanged<String>? onConnected;

  /// Invoked after the user disconnects and the stored token is deleted.
  final VoidCallback? onDisconnected;

  @override
  State<GithubConnectScreen> createState() => _GithubConnectScreenState();
}

class _GithubConnectScreenState extends State<GithubConnectScreen> {
  GithubDeviceCodeStarted? _started;
  Timer? _countdown;
  int _pollGeneration = 0;
  int _secondsRemaining = 0;
  bool _starting = true;
  bool _polling = false;
  bool _connected = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    // Bumping the generation makes any in-flight poll loop exit early.
    _pollGeneration++;
    _countdown?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _pollGeneration++;
    _countdown?.cancel();
    setState(() {
      _starting = true;
      _polling = false;
      _connected = false;
      _error = null;
      _started = null;
    });
    try {
      // Confirms the provider is configured; surfaces an actionable error
      // (e.g. the operator has not set GITHUB_OAUTH_CLIENT_ID) before the
      // user sees a code that would never be accepted.
      await widget.client.fetchConfig();
      final started = await widget.client.startDeviceAuthorization();
      if (!mounted) return;
      setState(() {
        _starting = false;
        _started = started;
        _secondsRemaining = started.expiresIn;
      });
      _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _secondsRemaining <= 0) {
          timer.cancel();
          return;
        }
        setState(() => _secondsRemaining--);
      });
      unawaited(_poll(started, started.interval));
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = _friendlyStartError(error);
      });
    }
  }

  Future<void> _poll(
    GithubDeviceCodeStarted started,
    int intervalSeconds,
  ) async {
    final generation = ++_pollGeneration;
    setState(() {
      _polling = true;
      _error = null;
    });
    var interval = intervalSeconds;
    while (mounted && generation == _pollGeneration) {
      await Future<void>.delayed(Duration(seconds: interval));
      if (!mounted || generation != _pollGeneration) return;
      try {
        final result = await widget.client.pollDeviceAuthorization(
          started.sessionId,
        );
        if (!mounted || generation != _pollGeneration) return;
        interval = result.interval ?? interval;
        if (result.isSuccess && result.accessToken != null) {
          await _complete(result.accessToken!);
          return;
        }
        if (result.status == 'expired') {
          _stopPolling('This code expired. Request a new code to continue.');
          return;
        }
        if (result.status == 'denied') {
          _stopPolling(
            'Sign-in was cancelled. Request a new code when you are ready.',
          );
          return;
        }
      } on Exception {
        _stopPolling(
          'Neurohub could not check your sign-in. Try checking again.',
        );
        return;
      }
    }
  }

  void _stopPolling(String message) {
    _countdown?.cancel();
    if (!mounted) return;
    setState(() {
      _polling = false;
      _error = message;
    });
  }

  Future<void> _complete(String token) async {
    _countdown?.cancel();
    await widget.tokenStorage.write(token);
    if (!mounted) return;
    setState(() {
      _polling = false;
      _connected = true;
    });
    widget.onConnected?.call(token);
  }

  Future<void> _disconnect() async {
    _pollGeneration++;
    _countdown?.cancel();
    await widget.tokenStorage.delete();
    widget.onDisconnected?.call();
    if (!mounted) return;
    setState(() {
      _connected = false;
      _starting = false;
      _started = null;
      _error = null;
    });
  }

  Future<void> _copyCode() async {
    final code = _started?.userCode;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sign-in code copied.')));
  }

  Future<void> _openLink() async {
    final url = _started?.verificationUri;
    if (url == null) return;
    final opened = await widget.linkLauncher.open(url);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The browser could not open. Copy the address and open it manually.',
          ),
        ),
      );
    }
  }

  String _friendlyStartError(Object error) {
    if (error is HttpApiException) {
      if (error.statusCode == 503) {
        return error.body;
      }
      return 'Neurohub sign-in is unavailable right now. Try again shortly.';
    }
    return 'Neurohub sign-in could not start. Check your connection and try again.';
  }

  String get _remainingLabel {
    final minutes = _secondsRemaining ~/ 60;
    final seconds = _secondsRemaining % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')} remaining';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('github-connect-screen'),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  GithubConnectTokens.radiusMd,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text('Connect GitHub', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text(
                      'Connect your GitHub account to save and share Neurohub workspaces.',
                    ),
                    const SizedBox(height: 24),
                    if (_starting)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_connected)
                      _buildConnected(theme)
                    else if (_started case final started?) ...<Widget>[
                      _buildCodeCard(theme, started),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        key: const Key('github-open-link'),
                        onPressed: _openLink,
                        icon: const Icon(Icons.open_in_new),
                        label: Text(
                          'Open ${started.verificationUri}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_polling) ...<Widget>[
                        const SizedBox(height: 16),
                        const Row(
                          children: <Widget>[
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Waiting for you to finish in the browser…',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                    if (_error case final error?) ...<Widget>[
                      const SizedBox(height: 16),
                      Text(
                        error,
                        key: const Key('github-connect-error'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: GithubConnectTokens.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        if (_connected)
                          TextButton(
                            key: const Key('github-disconnect'),
                            onPressed: _disconnect,
                            child: const Text('Disconnect'),
                          )
                        else ...[
                          TextButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            child: const Text('Cancel'),
                          ),
                          if (_error != null) ...<Widget>[
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              key: const Key('github-new-code'),
                              onPressed: _start,
                              icon: const Icon(Icons.refresh),
                              label: Text(
                                _started == null ? 'Try again' : 'New code',
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCodeCard(ThemeData theme, GithubDeviceCodeStarted started) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GithubConnectTokens.radiusSm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Enter this code on GitHub',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _remainingLabel,
              key: const Key('github-remaining-label'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: SelectableText(
                    started.userCode,
                    key: const Key('github-user-code'),
                    style: theme.textTheme.displaySmall,
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  key: const Key('github-copy-code'),
                  onPressed: _copyCode,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy code'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnected(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: <Widget>[
          const Icon(
            Icons.check_circle_outline,
            key: Key('github-connected'),
            size: 48,
            color: GithubConnectTokens.success,
          ),
          const SizedBox(height: 12),
          Text('Connected to GitHub', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Your GitHub access token is saved on this device.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
