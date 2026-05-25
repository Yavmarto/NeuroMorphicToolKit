import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/providers/backend_deployment_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/server_setup.dart';

class BackendSetupScreen extends StatelessWidget {
  const BackendSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ServerSetupScreen(
      message: 'Provision a backend target for this launcher.',
      allowConnect: false,
      initialMode: ServerSetupMode.setup,
      onSetupCompleted: () {
        if (context.mounted) {
          context.go('/workspace');
        }
      },
    );
  }
}

class BackendSetupForm extends ConsumerStatefulWidget {
  const BackendSetupForm({
    super.key,
    this.onDeploymentReady,
  });

  final VoidCallback? onDeploymentReady;

  @override
  ConsumerState<BackendSetupForm> createState() => _BackendSetupFormState();
}

class _BackendSetupFormState extends ConsumerState<BackendSetupForm> {
  String _targetType = 'local';
  String _mode = 'standalone';
  final TextEditingController _displayName =
      TextEditingController(text: 'This machine');
  final TextEditingController _host = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _sshPort = TextEditingController(text: '22');
  final TextEditingController _backendPort =
      TextEditingController(text: '9000');
  final TextEditingController _namespace = TextEditingController(text: 'nmtk');
  final TextEditingController _context = TextEditingController();
  final TextEditingController _apiServer = TextEditingController();
  DeploymentPreflightResult? _preflight;
  bool _isWorking = false;
  bool _completionQueued = false;

  @override
  void dispose() {
    _displayName.dispose();
    _host.dispose();
    _username.dispose();
    _sshPort.dispose();
    _backendPort.dispose();
    _namespace.dispose();
    _context.dispose();
    _apiServer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(backendDeploymentStateProvider);
    final tokens = NmtkShellTokens.of(context);

    if (provider.isReady && !_completionQueued) {
      _completionQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onDeploymentReady?.call();
      });
    }

    return Column(
      key: const ValueKey<String>('backend-setup-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTargetSection(tokens),
        const SizedBox(height: 16),
        _buildModeSection(tokens),
        const SizedBox(height: 16),
        _buildDetailsSection(tokens),
        const SizedBox(height: 16),
        if (_preflight != null) _buildPreflightCard(_preflight!, tokens),
        if (provider.activeJob != null) ...[
          const SizedBox(height: 16),
          _buildProgressCard(provider.activeJob!, tokens),
        ],
        const SizedBox(height: 24),
        _buildActions(provider),
      ],
    );
  }

  Widget _buildTargetSection(NmtkShellTokens tokens) {
    return NmtkSurfaceCard(
      child: Padding(
        padding: EdgeInsets.all(tokens.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('1. Choose where to run the backend'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _choice('This machine', 'local'),
                _choice('Remote server', 'remote_host'),
                _choice('Existing Kubernetes cluster', 'kubernetes_cluster'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSection(NmtkShellTokens tokens) {
    final modes = _targetType == 'kubernetes_cluster'
        ? const <String>['kubernetes']
        : const <String>['standalone', 'docker'];
    if (!modes.contains(_mode)) {
      _mode = modes.first;
    }
    return NmtkSurfaceCard(
      child: Padding(
        padding: EdgeInsets.all(tokens.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('2. Choose deployment mode'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final mode in modes)
                  _choice(_modeLabel(mode), mode, isMode: true),
              ],
            ),
            const SizedBox(height: 12),
            Text(_modeDescription(_mode)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsSection(NmtkShellTokens tokens) {
    return NmtkSurfaceCard(
      child: Padding(
        padding: EdgeInsets.all(tokens.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('3. Enter only the required details'),
            const SizedBox(height: 12),
            _field(_displayName, 'Display name'),
            const SizedBox(height: 12),
            if (_targetType == 'remote_host') ...[
              _field(_host, 'IP address or hostname'),
              const SizedBox(height: 12),
              _field(_username, 'SSH username'),
              const SizedBox(height: 12),
              _field(_sshPort, 'SSH port'),
              const SizedBox(height: 12),
            ],
            if (_targetType == 'kubernetes_cluster') ...[
              _field(_context, 'Kube context'),
              const SizedBox(height: 12),
              _field(_namespace, 'Namespace'),
              const SizedBox(height: 12),
              _field(_apiServer, 'API server override'),
              const SizedBox(height: 12),
            ],
            _field(_backendPort, 'Backend port'),
          ],
        ),
      ),
    );
  }

  Widget _buildPreflightCard(
    DeploymentPreflightResult preflight,
    NmtkShellTokens tokens,
  ) {
    final isFailed = preflight.status == 'failed';
    return NmtkSurfaceCard(
      child: Padding(
        padding: EdgeInsets.all(tokens.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isFailed ? 'Preflight failed' : preflight.message),
            const SizedBox(height: 8),
            for (final finding in [
              ...preflight.blockingFindings,
              ...preflight.degradedFindings,
            ])
              Text('- $finding'),
            if (preflight.suggestedRecovery.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(preflight.suggestedRecovery),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard(DeploymentJob job, NmtkShellTokens tokens) {
    return NmtkSurfaceCard(
      child: Padding(
        padding: EdgeInsets.all(tokens.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(job.stage == 'completed' ? 'Ready' : job.stageLabel),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: job.percent / 100),
            const SizedBox(height: 12),
            for (final line in job.logs.take(6)) Text(line),
            if (job.error.isNotEmpty) Text(job.error),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BackendDeploymentProvider backendProvider) {
    final job = backendProvider.activeJob;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        ZetaButton(
          onPressed: _isWorking ? null : _runPreflight,
          label: 'Validate connection',
        ),
        ZetaButton(
          onPressed: _isWorking ||
                  (_preflight != null && _preflight!.status == 'failed')
              ? null
              : _deploy,
          label: 'Review and deploy',
          type: ZetaButtonType.subtle,
        ),
        if (job != null && !job.isTerminal)
          ZetaButton.text(
            onPressed: () => backendProvider.cancelActiveJob(),
            label: 'Cancel',
          ),
      ],
    );
  }

  Widget _choice(String label, String value, {bool isMode = false}) {
    final selected = isMode ? _mode == value : _targetType == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          if (isMode) {
            _mode = value;
          } else {
            _targetType = value;
            if (value == 'local') {
              _displayName.text = 'This machine';
            } else if (value == 'remote_host') {
              _displayName.text = 'Remote backend';
            } else {
              _displayName.text = 'NMTK cluster';
              _mode = 'kubernetes';
            }
          }
          _preflight = null;
          _completionQueued = false;
        });
      },
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return ZetaTextInput(
      controller: controller,
      label: label,
      // ZETA-MIGRATION-TODO: border dropped
    );
  }

  Future<void> _runPreflight() async {
    setState(() => _isWorking = true);
    final provider = ref.read(backendDeploymentStateProvider);
    final result = await provider.preflight(
      targetType: _targetType,
      mode: _mode,
      displayName: _displayName.text,
      host: _host.text,
      username: _username.text,
      sshPort: int.tryParse(_sshPort.text) ?? 22,
      backendPort: int.tryParse(_backendPort.text) ?? 9000,
      namespace: _namespace.text,
      context: _context.text,
      apiServer: _apiServer.text,
    );
    setState(() {
      _preflight = result;
      _isWorking = false;
    });
  }

  Future<void> _deploy() async {
    setState(() {
      _isWorking = true;
      _completionQueued = false;
    });
    final provider = ref.read(backendDeploymentStateProvider);
    await provider.deploy(
      targetType: _targetType,
      mode: _mode,
      displayName: _displayName.text,
      host: _host.text,
      username: _username.text,
      sshPort: int.tryParse(_sshPort.text) ?? 22,
      backendPort: int.tryParse(_backendPort.text) ?? 9000,
      namespace: _namespace.text,
      context: _context.text,
      apiServer: _apiServer.text,
    );
    if (mounted) {
      setState(() => _isWorking = false);
    }
  }

  String _modeLabel(String mode) {
    if (mode == 'docker') {
      return 'Docker';
    }
    if (mode == 'kubernetes') {
      return 'Kubernetes';
    }
    return 'Standalone';
  }

  String _modeDescription(String mode) {
    if (mode == 'docker') {
      return 'Docker runs the backend in containers and is easier to move and reset.';
    }
    if (mode == 'kubernetes') {
      return 'Kubernetes is best when you already operate a cluster.';
    }
    return 'Standalone runs the backend directly on the machine you choose.';
  }
}
