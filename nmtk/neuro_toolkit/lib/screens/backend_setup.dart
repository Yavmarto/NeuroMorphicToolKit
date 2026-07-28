import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/src/features/deployment/domain/deployment_state.dart';

class BackendSetupScreen extends StatelessWidget {
  const BackendSetupScreen({
    super.key,
    required this.onDeploymentReady,
    this.onQuickConnect,
    this.onQuickConnectSuccess,
    this.initialHost,
    this.message,
    this.localDeploymentAvailable,
  });

  final Future<void> Function(DeploymentTarget target) onDeploymentReady;
  final Future<String?> Function(String input)? onQuickConnect;
  final void Function()? onQuickConnectSuccess;
  final String? initialHost;
  final String? message;
  final bool? localDeploymentAvailable;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(context.nmtkTokens.sectionGap * 1.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Set up your backend',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  SizedBox(height: context.nmtkTokens.compactGap),
                  Text(
                    message ??
                        'Choose where the backend should run. NeuroToolkit '
                            'will install it and connect automatically.',
                  ),
                  SizedBox(height: context.nmtkTokens.sectionGap * 1.5),
                  BackendSetupForm(
                    initialHost: initialHost,
                    localDeploymentAvailable: localDeploymentAvailable,
                    onQuickConnect: onQuickConnect,
                    onQuickConnectSuccess: onQuickConnectSuccess,
                    onDeploymentReady: onDeploymentReady,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class InAppBackendSetupScreen extends ConsumerWidget {
  const InAppBackendSetupScreen({super.key, this.onComplete});

  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(backendDeploymentProvider, (previous, next) {
      final prevReady = previous?.value?.isReady ?? false;
      final nextReady = next.value?.isReady ?? false;
      // A setup dialog can be opened while the current backend is already
      // ready. Its initial provider load must not be treated as a successful
      // form submission and dismiss the dialog immediately.
      if (onComplete == null && !prevReady && nextReady) {
        try {
          context.go('/workspace');
        } on Object catch (_) {}
      }
    });

    final notifier = ref.read(launcherBootstrapProvider.notifier);
    return BackendSetupScreen(
      onQuickConnect: notifier.connectToLauncher,
      onQuickConnectSuccess: () {
        if (onComplete != null) {
          onComplete!.call();
          return;
        }
        try {
          context.go('/workspace');
        } on Object catch (error) {
          unawaited(notifier.recordRouteHandoffFailure(error));
        }
      },
      onDeploymentReady: (target) async {
        await notifier.connectToDeploymentTarget(target);
        onComplete?.call();
      },
    );
  }
}

class BackendSetupForm extends ConsumerStatefulWidget {
  const BackendSetupForm({
    super.key,
    this.onDeploymentReady,
    this.onQuickConnect,
    this.onQuickConnectSuccess,
    this.initialHost,
    this.localDeploymentAvailable,
  });

  final Future<void> Function(DeploymentTarget target)? onDeploymentReady;
  final Future<String?> Function(String input)? onQuickConnect;
  final void Function()? onQuickConnectSuccess;

  /// When set, the form opens on "Remote server" with this host pre-filled
  /// instead of defaulting to "This machine."
  final String? initialHost;
  final bool? localDeploymentAvailable;

  @override
  ConsumerState<BackendSetupForm> createState() => _BackendSetupFormState();
}

class _BackendSetupFormState extends ConsumerState<BackendSetupForm> {
  // Acceptable ephemeral form state: _targetType, _mode, _preflight, _isWorking,
  // and _completionQueued are form-scoped fields that gate buttons and control
  // UI branching within this widget only. They carry no cross-widget business
  // semantics, so a Riverpod Notifier would add boilerplate without benefit.
  // (architecture skill §3 — "local ephemeral UI state is acceptable")
  late String _targetType;
  late String _mode;
  String _authMethod = 'ssh_key';
  late final TextEditingController _displayName;
  late final TextEditingController _host;
  final TextEditingController _username = TextEditingController();
  final TextEditingController _sshPort = TextEditingController(text: '22');
  final TextEditingController _sshPassword = TextEditingController();
  final TextEditingController _sshPrivateKey = TextEditingController();
  // Root-bootstrap sub-form: one-time root creds used for a single SSH
  // session server-side, never persisted -- see bootstrapRemoteUser. Kept
  // out of the _onCredentialFieldChanged listener loop below since these
  // fields don't affect deploy-target preflight/deploy state.
  bool _bootstrapWithRoot = false;
  String _rootAuthMethod = 'ssh_password';
  final TextEditingController _rootUsername = TextEditingController(
    text: 'root',
  );
  final TextEditingController _rootPassword = TextEditingController();
  final TextEditingController _rootPrivateKey = TextEditingController();
  bool _isBootstrapping = false;
  String? _bootstrapMessage;
  bool _bootstrapFailed = false;
  bool _obscureSshPassword = true;
  bool _obscureRootPassword = true;
  final TextEditingController _backendPort = TextEditingController(
    text: '9000',
  );
  final TextEditingController _namespace = TextEditingController(text: 'nmtk');
  final TextEditingController _context = TextEditingController();
  final TextEditingController _apiServer = TextEditingController();
  final TextEditingController _kubeconfig = TextEditingController();
  String? _kubeconfigName;
  DeploymentPreflightResult? _preflight;
  Map<String, String>? _preflightSnapshot;
  bool _isWorking = false;
  bool _cleanInstall = false;
  String? _hostError;
  String? _submittedDeploymentJobId;
  bool _completionQueued = false;
  final TextEditingController _quickConnectHost = TextEditingController();
  bool _isQuickConnecting = false;
  String? _quickConnectError;
  Timer? _heartbeatTimer;
  // Ticks once a second while a job is active, purely to keep the "updated
  // Xs ago" readout live. Deliberately NOT a setState() call — see
  // _buildStatusSection for why.
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  bool get _canRunLocally =>
      widget.localDeploymentAvailable ??
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux));

  @override
  void initState() {
    super.initState();
    final initialHost = widget.initialHost?.trim() ?? '';
    _targetType =
        initialHost.isNotEmpty || !_canRunLocally ? 'remote_host' : 'local';
    _mode = 'docker';
    _quickConnectHost.text = initialHost;
    _displayName = TextEditingController(
      text: _targetType == 'remote_host' ? 'Remote backend' : 'This machine',
    );
    _host = TextEditingController(text: initialHost);
    // Deployment fields are wired to _tick rather than driving the status
    // panel's AnimatedBuilder directly — see _onConfigurationFieldChanged.
    for (final controller in [
      _displayName,
      _host,
      _username,
      _sshPort,
      _sshPassword,
      _sshPrivateKey,
      _backendPort,
      _namespace,
      _context,
      _apiServer,
      _kubeconfig,
    ]) {
      controller.addListener(_onConfigurationFieldChanged);
    }
  }

  /// ZetaTextInput resyncs its controller's text (re-reading `controller.text`
  /// as a fresh `initialValue`) on every rebuild of the form — including
  /// while a keystroke's own notifyListeners() call is still being
  /// dispatched. Bumping `_tick` synchronously here (or worse, calling
  /// setState directly) can therefore fire *during* an in-progress build,
  /// which throws "setState() or markNeedsBuild() called during build."
  /// Deferring to a post-frame callback, and touching only our own private
  /// `_tick` notifier — never the raw text controllers themselves — avoids
  /// both re-entering that resync and rebuilding the text fields at all.
  void _onConfigurationFieldChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tick.value++;
      if (_preflight != null || _preflightSnapshot != null) {
        setState(_clearPreflight);
      }
    });
  }

  void _clearPreflight() {
    _preflight = null;
    _preflightSnapshot = null;
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _tick.dispose();
    for (final controller in [
      _displayName,
      _host,
      _username,
      _sshPort,
      _sshPassword,
      _sshPrivateKey,
      _backendPort,
      _namespace,
      _context,
      _apiServer,
      _kubeconfig,
    ]) {
      controller.removeListener(_onConfigurationFieldChanged);
    }
    _displayName.dispose();
    _host.dispose();
    _username.dispose();
    _sshPort.dispose();
    _sshPassword.dispose();
    _sshPrivateKey.dispose();
    _backendPort.dispose();
    _namespace.dispose();
    _context.dispose();
    _apiServer.dispose();
    _kubeconfig.dispose();
    _rootUsername.dispose();
    _rootPassword.dispose();
    _rootPrivateKey.dispose();
    _quickConnectHost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deploymentStateAsync = ref.watch(backendDeploymentProvider);
    final deploymentState = deploymentStateAsync.value;
    final isReady = deploymentState?.isReady ?? false;
    final tokens = NmtkShellTokens.of(context);
    final activeJob = deploymentState?.activeJob;

    final submittedJobCompleted = activeJob?.id == _submittedDeploymentJobId &&
        activeJob?.stage == 'completed';
    if (submittedJobCompleted && isReady && !_completionQueued) {
      _completionQueued = true;
      DeploymentTarget? target;
      for (final candidate
          in deploymentState?.targets ?? const <DeploymentTarget>[]) {
        if (candidate.id == activeJob?.targetId) {
          target = candidate;
          break;
        }
      }
      final completedTarget = target;
      if (completedTarget != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final callback = widget.onDeploymentReady;
          if (callback != null) {
            unawaited(callback(completedTarget));
          }
        });
      }
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncHeartbeat(activeJob),
    );

    return Column(
      key: const ValueKey<String>('backend-setup-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildQuickConnectSection(tokens),
        SizedBox(height: tokens.sectionGap),
        _buildTargetSection(tokens),
        SizedBox(height: tokens.sectionGap),
        _buildModeSection(tokens),
        SizedBox(height: tokens.sectionGap),
        _buildDetailsSection(tokens),
        _buildStatusSection(deploymentState, tokens),
        SizedBox(height: tokens.sectionGap * 1.5),
        _buildActions(activeJob),
      ],
    );
  }

  /// Rebuilds *only* this subtree when a credential field changes or the
  /// heartbeat ticks — never the surrounding form, and never by listening to
  /// the raw text controllers directly. ZetaTextInput resyncs those same
  /// controllers (re-notifying) as part of its own rebuild, so anything
  /// listening to them directly risks reacting while a build is already in
  /// progress. `_tick` is a private signal `_onCredentialFieldChanged` bumps
  /// from a post-frame callback — never touched by Zeta's internal resync —
  /// so listening to it alone is safe.
  Widget _buildStatusSection(DeploymentState? state, NmtkShellTokens tokens) {
    return AnimatedBuilder(
      animation: _tick,
      builder: (context, _) {
        final panel = _buildStatusPanel(state, tokens);
        if (panel == null) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(top: tokens.sectionGap),
          child: panel,
        );
      },
    );
  }

  /// Starts/stops the 1-second UI ticker that keeps the "updated Xs ago"
  /// readout live while a job is active. Idempotent — only touches the
  /// timer when whether we should be ticking has actually changed, since
  /// this runs from a post-frame callback on every build.
  void _syncHeartbeat(DeploymentJob? job) {
    if (!mounted) return;
    final shouldTick = job != null && !job.isTerminal;
    if (shouldTick == (_heartbeatTimer != null)) return;
    if (shouldTick) {
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _tick.value++;
      });
    } else {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
    }
  }

  Map<String, String> _currentCredentialSnapshot() => {
        'targetType': _targetType,
        'mode': _mode,
        'displayName': _displayName.text,
        'host': _host.text,
        'username': _username.text,
        'sshPort': _sshPort.text,
        'authMethod': _authMethod,
        'sshPassword': _sshPassword.text,
        'sshPrivateKey': _sshPrivateKey.text,
        'backendPort': _backendPort.text,
        'namespace': _namespace.text,
        'context': _context.text,
        'apiServer': _apiServer.text,
        'kubeconfig': _kubeconfig.text,
      };

  bool get _hasFreshPreflight =>
      _preflight != null &&
      mapEquals(_preflightSnapshot, _currentCredentialSnapshot());

  bool get _hasFreshSuccessfulPreflight =>
      _hasFreshPreflight && _preflight!.status == 'ok';

  /// Shows exactly one status view at a time, in priority order, so a
  /// stale card is never shown next to a fresh one:
  /// 1. An active job — live deploy in progress or just finished.
  /// 2. A preflight result — only if still validated against the current
  ///    field values (see [_currentCredentialSnapshot]).
  /// 3. The persisted last-attempt result for known targets.
  Widget? _buildStatusPanel(DeploymentState? state, NmtkShellTokens tokens) {
    final job = state?.activeJob;
    if (job != null) {
      return _buildJobStatusCard(job, tokens);
    }
    final lostReason = state?.connectionLostReason;
    if (lostReason != null) {
      return _buildConnectionLostCard(lostReason, tokens);
    }
    final preflight = _preflight;
    if (preflight != null && _hasFreshPreflight) {
      return _buildPreflightCard(preflight, tokens);
    }
    final targets = state?.targets ?? const <DeploymentTarget>[];
    if (targets.isNotEmpty) {
      return _buildLastResultCard(_mostRecentTarget(targets), tokens);
    }
    return null;
  }

  /// Targets accumulate one per distinct display name ever tried (each is a
  /// separately-created backend record), so `targets` can hold several
  /// entries that are all just earlier attempts at the same real host —
  /// showing all of them reads as duplicated, contradictory noise. Only the
  /// most recently touched one is ever relevant to "what just happened".
  DeploymentTarget _mostRecentTarget(List<DeploymentTarget> targets) {
    var mostRecent = targets.first;
    for (final target in targets.skip(1)) {
      final currentUpdatedAt = mostRecent.updatedAt;
      final candidateUpdatedAt = target.updatedAt;
      if (candidateUpdatedAt != null &&
          (currentUpdatedAt == null ||
              candidateUpdatedAt.isAfter(currentUpdatedAt))) {
        mostRecent = target;
      }
    }
    return mostRecent;
  }

  Widget _buildQuickConnectSection(NmtkShellTokens tokens) {
    return NmtkSurfaceCard(
      child: Padding(
        padding: EdgeInsets.all(tokens.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Already have a server running?'),
            SizedBox(height: tokens.compactGap),
            _field(_quickConnectHost, 'Server host or IP'),
            SizedBox(height: tokens.compactGap),
            Align(
              alignment: Alignment.centerLeft,
              child: ZetaButton(
                key: const Key('backend-setup-quick-connect'),
                onPressed: _isQuickConnecting ? null : _handleQuickConnect,
                label: _isQuickConnecting ? 'Connecting…' : 'Connect',
              ),
            ),
            if (_quickConnectError != null) ...[
              SizedBox(height: tokens.compactGap),
              NmtkStatusBanner(
                key: const Key('backend-setup-quick-connect-error'),
                title: 'Could not connect',
                content: Text(_quickConnectError!),
                tone: NmtkTone.danger,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _handleQuickConnect() async {
    final host = _quickConnectHost.text.trim();
    if (host.isEmpty) {
      setState(() {
        _quickConnectError = 'Enter a server host or IP address.';
      });
      return;
    }
    setState(() {
      _isQuickConnecting = true;
      _quickConnectError = null;
    });
    try {
      final quickConnect = widget.onQuickConnect;
      String? error;
      if (quickConnect != null) {
        error = await quickConnect(host);
        if (mounted && error == null) {
          widget.onQuickConnectSuccess?.call();
        }
      } else {
        final target = DeploymentTarget(
          id: 'quick-connect-$host',
          displayName: host,
          targetType: 'remote_host',
          mode: 'docker',
          authMode: 'none',
          backendPort: 9000,
          host: host,
        );
        await widget.onDeploymentReady?.call(target);
      }
      if (mounted && error != null) {
        setState(() => _quickConnectError = error);
      }
    } on Object {
      if (mounted) {
        setState(() {
          _quickConnectError =
              'The launcher could not be checked. Confirm the address and '
              'try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isQuickConnecting = false);
    }
  }

  Widget _buildTargetSection(NmtkShellTokens tokens) {
    return NmtkSurfaceCard(
      child: Padding(
        padding: EdgeInsets.all(tokens.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('1. Choose where to run the backend'),
            SizedBox(height: tokens.compactGap),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (_canRunLocally) _choice('This machine', 'local'),
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
        : const <String>['standalone', 'docker', 'podman'];
    return NmtkSurfaceCard(
      child: Padding(
        padding: EdgeInsets.all(tokens.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('2. Choose deployment mode'),
            SizedBox(height: tokens.compactGap),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final mode in modes)
                  _choice(_modeLabel(mode), mode, isMode: true),
              ],
            ),
            SizedBox(height: tokens.compactGap),
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
            SizedBox(height: tokens.compactGap),
            _field(_displayName, 'Display name'),
            if (_targetType == 'remote_host') ...[
              SizedBox(height: tokens.compactGap),
              _field(_host, 'SSH host', errorText: _hostError),
              SizedBox(height: tokens.compactGap),
              _field(_username, 'SSH username'),
              SizedBox(height: tokens.compactGap),
              _field(_sshPort, 'SSH port'),
              SizedBox(height: tokens.sectionGap),
              const Text('SSH authentication'),
              SizedBox(height: tokens.compactGap),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _authChoice('Password', 'ssh_password'),
                  _authChoice('SSH key', 'ssh_key'),
                ],
              ),
              SizedBox(height: tokens.compactGap),
              if (_authMethod == 'ssh_password')
                _field(
                  _sshPassword,
                  'SSH password',
                  obscureText: _obscureSshPassword,
                  suffix: IconButton(
                    icon: Icon(
                      _obscureSshPassword
                          ? ZetaIcons.visibility_off
                          : ZetaIcons.visibility,
                    ),
                    onPressed: () => setState(
                      () => _obscureSshPassword = !_obscureSshPassword,
                    ),
                  ),
                )
              else
                _multilineField(
                  _sshPrivateKey,
                  'SSH private key (paste contents)',
                ),
              // Rendered unconditionally (not gated on _bootstrapWithRoot) and
              // right next to the fields it describes -- the root sub-form
              // below collapses back to its "off" state on success, so a
              // message nested inside that gate would vanish in the same
              // rebuild that sets it.
              if (_bootstrapMessage != null) ...[
                SizedBox(height: tokens.compactGap),
                NmtkStatusBanner(
                  title: _bootstrapFailed
                      ? 'Could not create deploy user'
                      : 'New deploy user created',
                  content: Text(_bootstrapMessage!),
                  tone: _bootstrapFailed ? NmtkTone.danger : NmtkTone.success,
                  canClose: true,
                  onClose: () => setState(() => _bootstrapMessage = null),
                ),
              ],
              SizedBox(height: tokens.sectionGap),
              ..._buildRootBootstrapSection(tokens),
            ],
            if (_targetType == 'kubernetes_cluster') ...[
              SizedBox(height: tokens.compactGap),
              ZetaButton.outline(
                onPressed: _pickKubeconfig,
                leadingIcon: ZetaIcons.upload,
                label: _kubeconfigName == null
                    ? 'Import kubeconfig'
                    : 'Kubeconfig: $_kubeconfigName',
              ),
              SizedBox(height: tokens.compactGap),
              _field(_context, 'Kube context'),
              SizedBox(height: tokens.compactGap),
              _field(_namespace, 'Namespace'),
              SizedBox(height: tokens.compactGap),
              _field(_apiServer, 'API server override'),
            ],
            if (_targetType != 'kubernetes_cluster') ...[
              SizedBox(height: tokens.sectionGap),
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Clean install (Factory Reset)'),
                  subtitle: const Text(
                    'Wipes existing backend data volumes before deploying. '
                    'This erases all database contents.',
                  ),
                  value: _cleanInstall,
                  onChanged: (value) => setState(() => _cleanInstall = value),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Renders the optional "I only have root access" sub-form. Returns a
  /// list (spread into the parent Column) rather than a single Widget.
  List<Widget> _buildRootBootstrapSection(NmtkShellTokens tokens) {
    final host = _host.text.trim();
    return [
      Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text("I don't have a dedicated deploy account yet"),
          subtitle: const Text(
            'Use an existing admin/root account once to create one -- that '
            "account's credentials are never saved.",
          ),
          value: _bootstrapWithRoot,
          onChanged: (value) => setState(() => _bootstrapWithRoot = value),
        ),
      ),
      if (_bootstrapWithRoot) ...[
        SizedBox(height: tokens.compactGap),
        Text(
          'Enter an account on ${host.isEmpty ? "this host" : host} that '
          'already has root or sudo access -- often the same account you\'d '
          'normally SSH in as. It creates a dedicated "nmtk" deploy account, '
          'then is discarded.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SizedBox(height: tokens.compactGap),
        _field(_rootUsername, 'Admin username'),
        SizedBox(height: tokens.compactGap),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _rootAuthChoice('Admin password', 'ssh_password'),
            _rootAuthChoice('Admin SSH key', 'ssh_key'),
          ],
        ),
        SizedBox(height: tokens.compactGap),
        if (_rootAuthMethod == 'ssh_password')
          _field(
            _rootPassword,
            'Admin password',
            obscureText: _obscureRootPassword,
            suffix: IconButton(
              icon: Icon(
                _obscureRootPassword
                    ? ZetaIcons.visibility_off
                    : ZetaIcons.visibility,
              ),
              onPressed: () =>
                  setState(() => _obscureRootPassword = !_obscureRootPassword),
            ),
          )
        else
          _multilineField(
            _rootPrivateKey,
            'Admin SSH private key (paste contents)',
          ),
        SizedBox(height: tokens.compactGap),
        ZetaButton(
          onPressed: _isBootstrapping ? null : _bootstrapRemoteUser,
          label: _isBootstrapping
              ? 'Creating deploy user...'
              : 'Create deploy user',
          type: ZetaButtonType.subtle,
        ),
      ],
    ];
  }

  Widget _rootAuthChoice(String label, String value) {
    return ChoiceChip(
      label: Text(label),
      selected: _rootAuthMethod == value,
      onSelected: (_) => setState(() => _rootAuthMethod = value),
    );
  }

  Future<void> _bootstrapRemoteUser() async {
    setState(() {
      _isBootstrapping = true;
      _bootstrapMessage = null;
      _bootstrapFailed = false;
    });
    try {
      final result = await ref
          .read(backendDeploymentProvider.notifier)
          .bootstrapRemoteUser(
            host: _host.text,
            sshPort: int.tryParse(_sshPort.text) ?? 22,
            rootUsername: _rootUsername.text,
            rootPassword:
                _rootAuthMethod == 'ssh_password' ? _rootPassword.text : '',
            rootPrivateKey:
                _rootAuthMethod == 'ssh_key' ? _rootPrivateKey.text : '',
            containerEngine: _mode == 'podman' ? 'podman' : 'docker',
          );
      if (mounted) {
        setState(() {
          _username.text = result.username;
          _authMethod = 'ssh_key';
          _sshPrivateKey.text = result.sshPrivateKey;
          _rootPassword.clear();
          _rootPrivateKey.clear();
          _bootstrapWithRoot = false;
          _bootstrapFailed = false;
          _bootstrapMessage =
              'SSH username and authentication above were replaced with the '
              'generated "${result.username}" account (SSH key auth) on '
              '${_host.text}. The admin credentials you entered were used '
              'once and are not saved.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _bootstrapFailed = true;
          _bootstrapMessage = '$e';
        });
      }
    } finally {
      if (mounted) setState(() => _isBootstrapping = false);
    }
  }

  /// Strips the internal `"preflight failed: "` / `"degraded optional
  /// capability: "` category prefixes for display — they're useful for the
  /// code to match on, but read as jargon and duplicate the card's own
  /// status heading when shown to the user.
  String _displayFinding(String finding) {
    const prefixes = ['preflight failed: ', 'degraded optional capability: '];
    for (final prefix in prefixes) {
      if (finding.toLowerCase().startsWith(prefix)) {
        final rest = finding.substring(prefix.length);
        if (rest.isEmpty) return finding;
        return rest[0].toUpperCase() + rest.substring(1);
      }
    }
    return finding;
  }

  /// Shown instead of a job/preflight card when the notifier has lost
  /// contact with a running job (staleness watchdog or repeated poll
  /// failures) -- deliberately distinct in look and wording from
  /// [_buildPreflightCard] so it can never be mistaken for a fresh
  /// validation result of an unrelated attempt.
  Widget _buildConnectionLostCard(String reason, NmtkShellTokens tokens) {
    return NmtkSurfaceCard(
      child: Padding(
        padding: EdgeInsets.all(tokens.sectionGap),
        child: NmtkStatusBanner(
          title: 'Lost contact with deploy job',
          content: Text(reason),
          tone: NmtkTone.warning,
        ),
      ),
    );
  }

  Widget _buildPreflightCard(
    DeploymentPreflightResult preflight,
    NmtkShellTokens tokens,
  ) {
    final isFailed = preflight.status == 'failed';
    final hasWarnings = preflight.degradedFindings.isNotEmpty;
    return NmtkSurfaceCard(
      child: Padding(
        padding: EdgeInsets.all(tokens.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isFailed
                  ? 'Validation failed'
                  : hasWarnings
                      ? 'Ready to deploy with optional capability warnings'
                      : 'Ready to deploy',
            ),
            SizedBox(height: tokens.compactGap),
            Text(preflight.message),
            SizedBox(height: tokens.compactGap),
            const Text(
              'Validation checks the selected server and prerequisites only; '
              'it does not install, modify, or deploy anything.',
            ),
            for (final finding in [
              ...preflight.blockingFindings,
              ...preflight.degradedFindings,
            ])
              Text('- ${_displayFinding(finding)}'),
            if (preflight.suggestedRecovery.isNotEmpty) ...[
              SizedBox(height: tokens.compactGap),
              Text(preflight.suggestedRecovery),
            ],
            if (isFailed) ...[
              SizedBox(height: tokens.compactGap),
              const Text('Deployment remains locked until validation passes.'),
            ],
          ],
        ),
      ),
    );
  }

  /// Live status for the currently-running (or just-finished) job. Never
  /// shows a progress bar once terminal — a bar implies "still going",
  /// which is exactly the wrong signal right when it's done. While active,
  /// shows a ticking "updated Xs ago" readout (paired with [_syncHeartbeat])
  /// so it's visibly alive rather than a static label the user has to
  /// guess about.
  Widget _buildJobStatusCard(DeploymentJob job, NmtkShellTokens tokens) {
    final isTerminal = job.isTerminal;
    final isSuccess = job.stage == 'completed';
    final isJupyterDegraded = job.error.startsWith(
      'degraded optional capability: Jupyter',
    );
    // Phase updates (_emit server-side) copy their message into stageLabel,
    // so the last log entry duplicates the headline — but raw streamed
    // output lines (_emit_log) do not. Drop the last entry only when it
    // actually equals the headline, otherwise keep the newest real line.
    final rawHistory = (job.logs.isNotEmpty && job.logs.last == job.stageLabel)
        ? job.logs.sublist(0, job.logs.length - 1)
        : job.logs;
    // A repeating heartbeat stage (e.g. a long rsync) appends a new log
    // line every few seconds, all sharing the same message prefix as the
    // live headline below -- keep only entries for genuinely different
    // stages so history doesn't fill up with stale copies of "now".
    final currentStagePrefix = job.stageLabel.split(' (').first;
    final history = rawHistory
        .where((line) => line.split(' (').first != currentStagePrefix)
        .toList();
    final updatedAt = job.updatedAt;
    final secondsAgo = updatedAt == null
        ? null
        : DateTime.now().difference(updatedAt).inSeconds;
    final bundleIdentity = job.bundleVersion > 0
        ? 'Bundle v${job.bundleVersion} · ${job.bundleManifestHash.length <= 12 ? job.bundleManifestHash : job.bundleManifestHash.substring(0, 12)} · image ${job.imageTag}'
        : null;
    final headline = !isTerminal
        ? '${job.percent.round()}% — ${job.stageLabel}'
        : isSuccess
            ? 'Deployed'
            : isJupyterDegraded
                ? 'Notebook capability needs recovery'
                : 'Failed: ${job.error.isNotEmpty ? job.error : job.stageLabel}';

    return NmtkSurfaceCard(
      child: Padding(
        padding: EdgeInsets.all(tokens.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  !isTerminal
                      ? ZetaIcons.sync
                      : isSuccess
                          ? ZetaIcons.check_circle
                          : ZetaIcons.error,
                  color: isTerminal
                      ? (isSuccess ? Colors.green : Colors.red)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(headline)),
              ],
            ),
            if (!isTerminal) ...[
              SizedBox(height: tokens.compactGap),
              // Determinate, reflecting overall deploy progress (job.percent)
              // rather than just "something is happening" -- a single stage
              // like the rsync transfer can run for minutes with the same
              // percent, but that's honest: it really is still on that one
              // step. The ticking "Updated Xs ago" label below (plus the
              // stage's own heartbeat message in the headline) is what
              // confirms it hasn't frozen, so a held-still bar doesn't read
              // as stuck.
              LinearProgressIndicator(value: job.percent / 100),
              if (secondsAgo != null) ...[
                SizedBox(height: tokens.compactGap),
                Text(
                  'Updated ${secondsAgo}s ago',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
            if (history.isNotEmpty) ...[
              SizedBox(height: tokens.compactGap),
              for (final line in history.length > 3
                  ? history.sublist(history.length - 3)
                  : history)
                Text(line),
            ],
            if (bundleIdentity != null) ...[
              SizedBox(height: tokens.compactGap),
              Text(bundleIdentity),
            ],
            if (isJupyterDegraded) ...[
              SizedBox(height: tokens.compactGap),
              const Text(
                'The backend is reachable, but Jupyter is not ready yet. '
                'Recovering keeps existing notebook data.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _readinessLabel(String readiness) {
    switch (readiness) {
      case 'ready':
        return 'Deployed';
      case 'failed':
        return 'Failed';
      case 'degraded':
        return 'Notebook capability needs recovery';
      default:
        return 'Not yet deployed';
    }
  }

  /// Shows the most recently attempted target's persisted last-deployment
  /// outcome when no job is actively in flight and no fresh preflight
  /// applies — this is the ground truth from the backend and doesn't depend
  /// on a live poll surviving, so a real failure (e.g. an SSH auth
  /// rejection) is never invisible to the user. Explicitly labeled as
  /// history, not live status.
  Widget _buildLastResultCard(DeploymentTarget target, NmtkShellTokens tokens) {
    return NmtkSurfaceCard(
      child: Padding(
        padding: EdgeInsets.all(tokens.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${target.displayName} — last attempt: '
              '${_readinessLabel(target.lastReadiness)}',
            ),
            if (target.lastReadiness == 'failed' &&
                target.lastFailureReason.isNotEmpty)
              Text(target.lastFailureReason),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(DeploymentJob? job) {
    final canDeploy = !_isWorking && _hasFreshSuccessfulPreflight;
    final validationGuidance = _hasFreshSuccessfulPreflight
        ? 'Validation passed for the current configuration. Deploying will '
            'install or update the backend on the selected target.'
        : _hasFreshPreflight
            ? 'Fix the validation findings above, then validate again to '
                'unlock deployment.'
            : 'Validate the current configuration to unlock deployment. '
                'Validation does not make any server changes.';
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        ZetaButton(
          key: const Key('backend-setup-validate'),
          onPressed: _isWorking ? null : _runPreflight,
          label: _isWorking ? 'Validating server…' : 'Validate server',
        ),
        ZetaButton(
          key: const Key('backend-setup-deploy'),
          onPressed: canDeploy ? _deploy : null,
          label: 'Deploy backend',
        ),
        Text(validationGuidance),
        if (job != null && !job.isTerminal)
          ZetaButton.text(
            onPressed: () =>
                ref.read(backendDeploymentProvider.notifier).cancelActiveJob(),
            label: 'Cancel',
          ),
        if (job != null &&
            job.isTerminal &&
            job.error.startsWith('degraded optional capability: Jupyter'))
          ZetaButton(
            onPressed: _isWorking ? null : _recoverJupyter,
            label: 'Recover Jupyter',
            type: ZetaButtonType.subtle,
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
              if (_mode == 'kubernetes') _mode = 'standalone';
            } else {
              _displayName.text = 'NMTK cluster';
              _mode = 'kubernetes';
            }
          }
          _clearPreflight();
          _completionQueued = false;
        });
      },
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool obscureText = false,
    Widget? suffix,
    String? errorText,
    String Function(String value)? valueSanitizer,
  }) {
    return NmtkTextInput(
      controller: controller,
      label: label,
      obscureText: obscureText,
      suffix: suffix,
      errorText: errorText,
      valueSanitizer: valueSanitizer,
    );
  }

  Widget _multilineField(TextEditingController controller, String label) {
    // Disabled for the same reason as NmtkTextInput -- see its build() --
    // this field bypasses that wrapper and builds TextField directly.
    return SelectionContainer.disabled(
      child: TextField(
        controller: controller,
        minLines: 4,
        maxLines: 8,
        style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: label,
        ),
      ),
    );
  }

  Widget _authChoice(String label, String value) {
    return ChoiceChip(
      label: Text(label),
      selected: _authMethod == value,
      onSelected: (_) => setState(() {
        _authMethod = value;
        _clearPreflight();
      }),
    );
  }

  Future<void> _pickKubeconfig() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['yaml', 'yml', 'config'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final selected = result.files.single;
    final bytes = selected.bytes ??
        (selected.path == null
            ? null
            : await File(selected.path!).readAsBytes());
    if (bytes == null) return;
    if (!mounted) return;
    setState(() {
      _kubeconfig.text = String.fromCharCodes(bytes);
      _kubeconfigName = selected.name;
      _clearPreflight();
    });
  }

  Future<void> _runPreflight() async {
    if (!_validateRemoteHost()) return;
    setState(() => _isWorking = true);
    // Captured before the await so it reflects exactly what was validated,
    // not whatever the fields happen to hold once the request resolves.
    final snapshot = _currentCredentialSnapshot();
    final result = await ref.read(backendDeploymentProvider.notifier).preflight(
          targetType: _targetType,
          mode: _mode == 'podman' ? 'docker' : _mode,
          displayName: _displayName.text,
          host: _host.text,
          username: _username.text,
          sshPort: int.tryParse(_sshPort.text) ?? 22,
          authMethod: _targetType == 'remote_host' ? _authMethod : 'none',
          sshPassword: _sshPassword.text,
          sshPrivateKey: _sshPrivateKey.text,
          backendPort: int.tryParse(_backendPort.text) ?? 9000,
          namespace: _namespace.text,
          context: _context.text,
          apiServer: _apiServer.text,
          containerEngine: _mode == 'podman' ? 'podman' : 'docker',
          kubeconfig: _kubeconfig.text,
        );
    if (mounted) {
      setState(() {
        _preflight = result;
        _preflightSnapshot = snapshot;
        _isWorking = false;
      });
    }
  }

  Future<void> _deploy() async {
    if (!_hasFreshSuccessfulPreflight) return;
    if (!_validateRemoteHost()) return;
    setState(() {
      _isWorking = true;
      _completionQueued = false;
      // Otherwise an earlier "Validate connection" result stays eligible
      // for display (per _buildStatusPanel's snapshot match) and can
      // resurface mid-deploy as soon as activeJob briefly goes null, reading
      // as an unrelated, stale card.
      _clearPreflight();
    });
    final job = await ref.read(backendDeploymentProvider.notifier).deploy(
          targetType: _targetType,
          mode: _mode == 'podman' ? 'docker' : _mode,
          displayName: _displayName.text,
          host: _host.text,
          username: _username.text,
          sshPort: int.tryParse(_sshPort.text) ?? 22,
          authMethod: _targetType == 'remote_host' ? _authMethod : 'none',
          sshPassword: _sshPassword.text,
          sshPrivateKey: _sshPrivateKey.text,
          backendPort: int.tryParse(_backendPort.text) ?? 9000,
          namespace: _namespace.text,
          context: _context.text,
          apiServer: _apiServer.text,
          containerEngine: _mode == 'podman' ? 'podman' : 'docker',
          kubeconfig: _kubeconfig.text,
          cleanInstall: _cleanInstall,
        );
    if (mounted) {
      setState(() {
        _submittedDeploymentJobId = job.id;
        _isWorking = false;
      });
    }
  }

  Future<void> _recoverJupyter() async {
    setState(() => _isWorking = true);
    // Restarts only the Jupyter container over SSH -- unlike the old
    // recoverActiveJob() path, this doesn't rerun the entire install just to
    // nudge one already-degraded optional service.
    await ref.read(backendDeploymentProvider.notifier).retryJupyter();
    if (mounted) setState(() => _isWorking = false);
  }

  bool _validateRemoteHost() {
    if (_targetType != 'remote_host') return true;
    final valid = _host.text.trim().isNotEmpty;
    setState(() {
      _hostError = valid ? null : 'Enter the SSH host.';
    });
    return valid;
  }

  String _modeLabel(String mode) {
    if (mode == 'docker') return 'Docker';
    if (mode == 'podman') return 'Podman';
    if (mode == 'kubernetes') return 'Kubernetes';
    return 'Standalone';
  }

  String _modeDescription(String mode) {
    if (mode == 'docker') {
      return 'Docker runs the backend in containers and is easier to move and reset. '
          '${_targetType == 'remote_host' ? 'If missing on the remote host, deployment installs it automatically.' : 'Install it on this machine before deploying.'}';
    }
    if (mode == 'podman') {
      return 'Podman is rootless and needs no background daemon. '
          '${_targetType == 'remote_host' ? 'If missing on the remote host, deployment installs it automatically via apt (Debian/Ubuntu) as long as the account has sudo access -- no separate step required.' : 'Install it on this machine before deploying.'}';
    }
    if (mode == 'kubernetes') {
      return 'Kubernetes is best when you already operate a cluster.';
    }
    return 'Standalone runs the backend directly on the machine you choose.';
  }
}
