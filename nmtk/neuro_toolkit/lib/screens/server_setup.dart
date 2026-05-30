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
  late ServerSetupMode _mode = widget.initialMode;
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue ?? '');
  bool _isConnecting = false;

  @override
  void dispose() {
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
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context),
                const SizedBox(height: 24),
                if (widget.allowConnect) ...[
                  _buildConnectCard(context),
                  const SizedBox(height: 16),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Launcher Server',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Connect to an existing launcher server or set up a new one. You only need one path to continue.',
          style: theme.textTheme.bodyLarge,
        ),
      ],
    );
  }

  Widget _buildConnectCard(BuildContext context) {
    final isActive = _mode == ServerSetupMode.connect;

    return NmtkSection(
      title: 'Connect to a server',
      subtitle: 'Use an existing launcher control API host or base URL.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NmtkShellReadinessStateView.fromState(
            isActive
                ? NmtkShellReadinessState.error
                : NmtkShellReadinessState.degraded,
            message: widget.message ??
                'Enter the host or base URL for the launcher control API.',
          ),
          const SizedBox(height: 16),
          Text(
            'Launcher Control API Host or URL',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          ZetaTextInput(
            controller: _controller,
            placeholder: 'http://192.168.1.50:8091',
            onChange: widget.onChanged,
          ),
          const SizedBox(height: 8),
          Text(
            'Run `python3 scripts/launcher_control_service.py --host 0.0.0.0 --port 8091` on the target machine if the launcher server is not already running.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              NmtkPrimaryButton(
                onPressed: _isConnecting || widget.onConnect == null
                    ? null
                    : _handleConnect,
                icon: Icons.wifi_find_rounded,
                label: widget.connectLabel,
              ),
              if (widget.setupAvailable)
                NmtkOutlinedButton(
                  onPressed: () {
                    setState(() => _mode = ServerSetupMode.setup);
                  },
                  icon: Icons.add_circle_outline,
                  label: 'Set Up a New Server',
                ),
            ],
          ),
        ],
      ),
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
