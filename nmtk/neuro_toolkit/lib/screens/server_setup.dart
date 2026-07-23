import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/screens/backend_setup.dart';

enum ServerSetupMode {
  connect,
  setup,
}

class ServerSetupScreen extends ConsumerStatefulWidget {
  const ServerSetupScreen({
    super.key,
    required this.message,
    this.initialValue,
    this.onConnect,
    this.connectLabel = 'Save & Retry',
    this.allowConnect = true,
    this.setupAvailable = true,
    this.showScaffold = true,
    this.initialMode = ServerSetupMode.connect,
    this.onSetupCompleted,
    this.setupUnavailableMessage,
    this.setupInitialHost,
  });

  /// Initial text for the host input field.  The widget owns its controller
  /// internally so there are no cross-widget controller lifetimes to manage.
  final String? initialValue;

  final String? message;

  /// Called with the current host field text when the user presses Connect.
  final Future<void> Function(String host)? onConnect;
  final String connectLabel;
  final bool allowConnect;
  final bool setupAvailable;
  final bool showScaffold;
  final ServerSetupMode initialMode;
  final VoidCallback? onSetupCompleted;
  final String? setupUnavailableMessage;

  /// When set, the provisioning form defaults to "Remote server" with this
  /// host pre-filled instead of "This machine."
  final String? setupInitialHost;

  @override
  ConsumerState<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends ConsumerState<ServerSetupScreen> {
  late final ServerSetupMode _mode = widget.initialMode;
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue ?? '');
  late final FocusNode _focusNode = FocusNode();
  // Acceptable ephemeral UI state: gates a single button during an async
  // callback. It does not represent business data or cross-widget state, so
  // Riverpod ownership would add overhead without benefit (architecture skill §3).
  bool _isConnecting = false;
  String? _connectError;

  @override
  void didUpdateWidget(covariant ServerSetupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusNode.hasFocus) {
      return;
    }
    final nextValue = widget.initialValue ?? '';
    if (oldWidget.initialValue != widget.initialValue &&
        _controller.text != nextValue) {
      _controller.text = nextValue;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusText = _buildStatusText(context);
    final body = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(context.nmtkTokens.sectionGap * 1.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context),
                if (statusText != null) ...[
                  SizedBox(height: context.nmtkTokens.compactGap),
                  statusText,
                ],
                SizedBox(height: context.nmtkTokens.sectionGap * 1.5),
                if (widget.allowConnect) ...[
                  _buildConnectCard(context),
                  SizedBox(height: context.nmtkTokens.sectionGap * 1.5),
                ],
                if (widget.allowConnect && widget.setupAvailable) ...[
                  Center(
                    child: Text(
                      'or',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  SizedBox(height: context.nmtkTokens.sectionGap * 1.5),
                ],
                _buildSetupCard(context),
              ],
            ),
          ),
        ),
      ),
    );

    if (!widget.showScaffold) {
      return body;
    }

    return Scaffold(body: body);
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          Icons.dns_rounded, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
          size: 32,
          color: theme.colorScheme.primary,
        ),
        SizedBox(width: context.nmtkTokens.compactGap),
        Text(
          'Connect to server',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  /// Renders the connect failure (if any), falling back to [widget.message].
  /// Mirrors the error-text style already used for Python install failures
  /// in [FirstRunSetupScreen] rather than inventing a new banner widget.
  Widget? _buildStatusText(BuildContext context) {
    final text = _connectError ?? widget.message;
    if (text == null || text.isEmpty) {
      return null;
    }
    return SelectableText(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: _connectError != null
                ? Theme.of(context).colorScheme.error
                : null,
          ),
    );
  }

  Widget _buildConnectCard(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Server address',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        SizedBox(height: context.nmtkTokens.compactGap),
        NmtkTextInput(
          controller: _controller,
          focusNode: _focusNode,
          placeholder: '192.168.1.50',
        ),
        SizedBox(height: context.nmtkTokens.sectionGap),
        NmtkPrimaryButton(
          onPressed:
              _isConnecting || widget.onConnect == null ? null : _handleConnect,
          icon: ZetaIcons.wifi,
          label: widget.connectLabel,
        ),
      ],
    );
  }

  Widget _buildSetupCard(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);

    if (!widget.setupAvailable) {
      return NmtkSection(
        title: 'Set up a new server',
        subtitle: 'Available after the launcher control API is reachable.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.setupUnavailableMessage ??
                  'Connect to a launcher server first. Once the control API is reachable, you can provision a new backend from the same screen.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return AnimatedContainer(
      duration: tokens.fastMotion,
      curve: Curves.easeOutCubic,
      child: NmtkSection(
        title: 'Set up a new server',
        subtitle:
            'Provision a backend target here, then continue automatically when it becomes ready.',
        child: AnimatedSwitcher(
          duration: tokens.fastMotion,
          child: _mode == ServerSetupMode.setup
              ? BackendSetupForm(
                  onDeploymentReady: widget.onSetupCompleted,
                  initialHost: widget.setupInitialHost,
                )
              : Text(
                  'Already have a launcher host? Connect above instead. If not, use this path to create a new backend target here.',
                  key: const ValueKey<String>('setup-summary'),
                  style: theme.textTheme.bodyMedium,
                ),
        ),
      ),
    );
  }

  Future<void> _handleConnect() async {
    setState(() {
      _isConnecting = true;
      _connectError = null;
    });
    try {
      await widget.onConnect?.call(_controller.text.trim());
    } catch (_) {
      if (mounted) {
        setState(() {
          _connectError =
              'Could not save that server address. Check the host and try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }
}
