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
    this.onChanged,
    this.onConnect,
    this.connectLabel = 'Save & Retry',
    this.allowConnect = true,
    this.setupAvailable = true,
    this.showScaffold = true,
    this.initialMode = ServerSetupMode.connect,
    this.onSetupCompleted,
    this.setupUnavailableMessage,
  });

  /// Initial text for the host input field.  The widget owns its controller
  /// internally so there are no cross-widget controller lifetimes to manage.
  final String? initialValue;

  /// Called whenever the host input text changes.
  final ValueChanged<String?>? onChanged;

  final String? message;
  final Future<void> Function()? onConnect;
  final String connectLabel;
  final bool allowConnect;
  final bool setupAvailable;
  final bool showScaffold;
  final ServerSetupMode initialMode;
  final VoidCallback? onSetupCompleted;
  final String? setupUnavailableMessage;

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
    return Text(
      'Connect to server',
      style: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
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
        ZetaTextInput(
          controller: _controller,
          focusNode: _focusNode,
          placeholder: '192.168.1.50',
          onChange: widget.onChanged,
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
    setState(() => _isConnecting = true);
    try {
      await widget.onConnect?.call();
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }
}
