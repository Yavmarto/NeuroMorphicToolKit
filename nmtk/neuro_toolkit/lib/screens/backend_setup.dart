import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        defaultTargetPlatform,
        kIsWeb,
        mapEquals,
        visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:zeta_flutter/zeta_flutter.dart' show ZetaDialog;

import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
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
      onQuickConnect: (input) async {
        final error = await notifier.connectToLauncher(input);
        if (error != null) {
          return error;
        }
        await _refreshServerBackedProviders(ref);
        if (onComplete != null) {
          onComplete!.call();
          return null;
        }
        if (!context.mounted) {
          return null;
        }
        try {
          context.go('/workspace');
        } on Object catch (error) {
          unawaited(notifier.recordRouteHandoffFailure(error));
        }
        return null;
      },
      onDeploymentReady: (target) async {
        await notifier.connectToDeploymentTarget(target);
        await _refreshServerBackedProviders(ref);
        onComplete?.call();
      },
    );
  }

  Future<void> _refreshServerBackedProviders(WidgetRef ref) async {
    ref.invalidate(controlApiServiceProvider);
    await Future.wait([
      ref.refresh(moduleProvider.future),
      ref.refresh(workspaceProvider.future),
    ]);
    ref.invalidate(serverConnectionProvider);
    ref.invalidate(backendUpdateProvider);
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

  @visibleForTesting
  static String operationProgressLabelForTesting(
    DeploymentActiveOperation operation,
    DateTime now,
  ) {
    return _operationProgressLabel(operation, now);
  }

  static String _operationProgressLabel(
    DeploymentActiveOperation operation,
    DateTime now,
  ) {
    final elapsed =
        now.difference(operation.startedAt).inSeconds.clamp(0, 1 << 31);
    if (elapsed >= operation.timeoutSeconds) {
      return '${operation.automaticRecovery ? 'Automatic recovery · ' : ''}'
          '${operation.label} · timeout reached · stopping safely';
    }
    return '${operation.automaticRecovery ? 'Automatic recovery · ' : ''}'
        '${operation.label} · ${elapsed}s elapsed · '
        'up to ${operation.timeoutSeconds}s';
  }

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
  final String _authMethod = 'ssh_key';
  late final TextEditingController _displayName;
  late final TextEditingController _host;
  final TextEditingController _username = TextEditingController();
  final TextEditingController _sshPort = TextEditingController(text: '22');
  final TextEditingController _sshPassword = TextEditingController();
  final TextEditingController _sshPrivateKey = TextEditingController();
  String _rootAuthMethod = 'ssh_password';
  final TextEditingController _rootUsername = TextEditingController(
    text: 'root',
  );
  final TextEditingController _rootPassword = TextEditingController();
  // Retrying a stalled setup has to re-ask for the administrator credential,
  // because it is deliberately never persisted. Focusing the field is what makes
  // that one extra step obvious instead of feeling like a dead end.
  final FocusNode _rootPasswordFocus = FocusNode();
  final FocusNode _rootPrivateKeyFocus = FocusNode();
  final TextEditingController _rootPrivateKey = TextEditingController();
  String? _setupError;
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
  bool _factoryReset = false;
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
    _rootPasswordFocus.dispose();
    _rootPrivateKeyFocus.dispose();
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
        _buildUpdateBanner(tokens),
        _buildQuickConnectSection(tokens),
        SizedBox(height: tokens.sectionGap),
        _buildTargetSection(tokens),
        SizedBox(height: tokens.sectionGap),
        _buildModeSection(tokens),
        SizedBox(height: tokens.sectionGap),
        _buildDetailsSection(tokens),
        _buildStatusSection(deploymentState, tokens),
        SizedBox(height: tokens.sectionGap * 1.5),
        _buildActions(activeJob, deploymentState?.connectionLostReason),
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
  /// 1. An active job — live deploy in progress, stalled, or just finished.
  /// 2. A preflight result — only if still validated against the current
  ///    field values (see [_currentCredentialSnapshot]).
  /// 3. The persisted last-attempt result for known targets.
  ///
  /// A stalled job keeps the job card rather than falling through to the
  /// connection-lost card, but the card must say it has stalled: showing a live
  /// progress bar for a deployment the app has stopped believing in is the
  /// difference between "still working" and "waiting forever".
  Widget? _buildStatusPanel(DeploymentState? state, NmtkShellTokens tokens) {
    final job = state?.activeJob;
    final lostReason = state?.connectionLostReason;
    if (job != null) {
      return _buildJobStatusCard(
        job,
        tokens,
        stalledReason: job.isTerminal ? null : lostReason,
      );
    }
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
            _field(_quickConnectHost, 'Server IP'),
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
    final host = _canonicalIpv4(_quickConnectHost.text);
    if (host == null) {
      setState(() {
        _quickConnectError = 'Enter an IPv4 address, for example 192.168.2.34.';
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
    } on Object catch (error) {
      debugPrint('Quick connect failed: $error');
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
        : _targetType == 'remote_host'
            ? const <String>['docker', 'podman']
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
            if (_targetType != 'remote_host')
              _field(_displayName, 'Display name'),
            if (_targetType == 'remote_host') ...[
              SizedBox(height: tokens.compactGap),
              _field(_host, 'Server IP', errorText: _hostError),
              SizedBox(height: tokens.compactGap),
              _field(_rootUsername, 'Admin user'),
              SizedBox(height: tokens.sectionGap),
              const Text('Administrator authentication'),
              SizedBox(height: tokens.compactGap),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _adminAuthChoice('Password', 'ssh_password'),
                  _adminAuthChoice('SSH key', 'ssh_key'),
                ],
              ),
              SizedBox(height: tokens.compactGap),
              if (_rootAuthMethod == 'ssh_password')
                _field(
                  _rootPassword,
                  'Admin password',
                  focusNode: _rootPasswordFocus,
                  obscureText: _obscureRootPassword,
                  suffix: IconButton(
                    icon: Icon(
                      _obscureRootPassword
                          ? ZetaIcons.visibility_off
                          : ZetaIcons.visibility,
                    ),
                    onPressed: () => setState(
                      () => _obscureRootPassword = !_obscureRootPassword,
                    ),
                  ),
                )
              else
                _multilineField(
                  _rootPrivateKey,
                  'Admin SSH key',
                  focusNode: _rootPrivateKeyFocus,
                ),
              SizedBox(height: tokens.sectionGap),
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Factory reset server data'),
                  subtitle: const Text(
                    'Optional and destructive. Normal setup removes old NMTK '
                    'containers across Docker and Podman while preserving '
                    'notebooks, databases, and workspace data.',
                  ),
                  value: _factoryReset,
                  onChanged: (value) => setState(() => _factoryReset = value),
                ),
              ),
              if (_setupError != null) ...[
                SizedBox(height: tokens.compactGap),
                NmtkStatusBanner(
                  title: 'Could not start server setup',
                  content: Text(_setupError!),
                  tone: NmtkTone.danger,
                  canClose: true,
                  onClose: () => setState(() => _setupError = null),
                ),
              ],
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
            if (_targetType == 'local') ...[
              SizedBox(height: tokens.sectionGap),
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Factory reset local data'),
                  subtitle: const Text(
                    'Wipes existing backend data volumes before deploying. '
                    'This erases all database contents.',
                  ),
                  value: _factoryReset,
                  onChanged: (value) => setState(() => _factoryReset = value),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _adminAuthChoice(String label, String value) {
    return ChoiceChip(
      label: Text(label),
      selected: _rootAuthMethod == value,
      onSelected: (_) => setState(() => _rootAuthMethod = value),
    );
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
  Widget _buildJobStatusCard(
    DeploymentJob job,
    NmtkShellTokens tokens, {
    String? stalledReason,
  }) {
    final isTerminal = job.isTerminal;
    final isStalled = stalledReason != null;
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
    final activeOperation = job.activeOperation;
    final bundleIdentity = job.bundleVersion > 0
        ? 'Bundle v${job.bundleVersion} · ${job.bundleManifestHash.length <= 12 ? job.bundleManifestHash : job.bundleManifestHash.substring(0, 12)} · image ${job.imageTag}'
        : null;
    final headline = isStalled
        ? 'Server setup stopped responding at ${job.percent.round()}%'
        : !isTerminal
            ? '${job.percent.round()}% — ${job.stageLabel}'
            : isSuccess
                ? 'Deployed'
                : isJupyterDegraded
                    ? 'Notebook capability needs recovery'
                    : job.failureDetails?.summary ?? 'Server setup failed';
    final failure = job.failureDetails;

    return NmtkSurfaceCard(
      child: Padding(
        padding: EdgeInsets.all(tokens.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  !isTerminal && !isStalled
                      ? ZetaIcons.sync
                      : isSuccess
                          ? ZetaIcons.check_circle
                          : ZetaIcons.error,
                  color: isStalled
                      ? tokens.errorColor
                      : isTerminal
                          ? (isSuccess
                              ? tokens.healthyColor
                              : tokens.errorColor)
                          : null,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(headline)),
              ],
            ),
            if (isStalled) ...[
              SizedBox(height: tokens.compactGap),
              Text(
                stalledReason,
                key: Key('deployment-stalled-reason-${job.id}'),
              ),
              SizedBox(height: tokens.compactGap),
              Text(
                'Last step: ${job.stageLabel}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (!isTerminal && !isStalled) ...[
              SizedBox(height: tokens.compactGap),
              // Determinate, reflecting overall deploy progress (job.percent)
              // rather than just "something is happening" -- a single stage
              // like the rsync transfer can run for minutes with the same
              // percent, but that's honest: it really is still on that one
              // step. The active operation and its ticking elapsed time below
              // confirm it has not frozen; phases without operation metadata
              // retain the generic last-update heartbeat.
              LinearProgressIndicator(value: job.percent / 100),
              if (activeOperation != null) ...[
                SizedBox(height: tokens.compactGap),
                Text(
                  BackendSetupForm._operationProgressLabel(
                    activeOperation,
                    DateTime.now(),
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else if (secondsAgo != null) ...[
                SizedBox(height: tokens.compactGap),
                Text(
                  'Still working · updated ${secondsAgo}s ago',
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
            if (failure != null) ...[
              SizedBox(height: tokens.compactGap),
              Text(failure.recovery),
              SizedBox(height: tokens.compactGap),
              Text(
                failure.existingConnectionReachable == true
                    ? 'The reinstall failed, but the existing server is still connected.'
                    : failure.existingConnectionReachable == false
                        ? 'The existing server is not reachable from this device.'
                        : 'Existing connection health could not be confirmed.',
              ),
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
            SizedBox(height: tokens.compactGap),
            Align(
              alignment: Alignment.centerLeft,
              child: ZetaButton.outline(
                key: Key('deployment-view-details-${job.id}'),
                onPressed: () => _showTerminalOutput(job),
                label: 'View raw SSH output',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTerminalOutput(DeploymentJob job) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, child) {
          final state = ref.watch(backendDeploymentProvider).value;
          final current =
              state?.activeJob?.id == job.id ? state!.activeJob! : job;
          final enteredHost = _host.text.trim();
          final targetHost = RegExp(
            r'^remote-(\d+)-(\d+)-(\d+)-(\d+)$',
          ).firstMatch(current.targetId);
          final host = enteredHost.isNotEmpty
              ? enteredHost
              : targetHost == null
                  ? ''
                  : [
                      targetHost.group(1),
                      targetHost.group(2),
                      targetHost.group(3),
                      targetHost.group(4),
                    ].join('.');
          return NmtkLogViewerDialog(
            title: host.isEmpty ? 'Raw SSH output' : 'Raw SSH output — $host',
            lines: current.terminalOutput,
            isRunning: !current.isTerminal,
          );
        },
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

  Widget _buildActions(DeploymentJob? job, String? connectionLostReason) {
    if (_targetType == 'remote_host') {
      final isStalled =
          job != null && !job.isTerminal && connectionLostReason != null;
      final isActive = job != null && !job.isTerminal && !isStalled;
      // A stalled attempt and a failed one need the same thing: start over on
      // the same host. Without this the failure text asked the user to "Select
      // Retry" while no such control existed.
      final canRetry = isStalled ||
          (job != null &&
              job.stage == DeploymentPhase.failed.wireName &&
              !job.error.startsWith('degraded optional capability'));
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          ZetaButton(
            key: const Key('backend-setup-set-up-and-connect'),
            onPressed: _isWorking || isActive ? null : _setupRemoteServer,
            label: _isWorking
                ? 'Preparing server…'
                : isActive
                    ? 'Setting up server…'
                    : 'Set up and connect',
          ),
          const Text(
            'The administrator credential is used once and is never saved. '
            'Connection happens automatically after required services respond.',
          ),
          if (canRetry)
            ZetaButton(
              key: const Key('backend-setup-retry'),
              onPressed: _isWorking ? null : _retryRemoteSetup,
              label: 'Retry setup',
            ),
          if (isActive)
            ZetaButton.text(
              onPressed: () => ref
                  .read(backendDeploymentProvider.notifier)
                  .cancelActiveJob(),
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
              if (_mode == 'kubernetes' || _mode == 'standalone') {
                _mode = 'docker';
              }
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
    FocusNode? focusNode,
  }) {
    return NmtkTextInput(
      controller: controller,
      label: label,
      obscureText: obscureText,
      suffix: suffix,
      errorText: errorText,
      valueSanitizer: valueSanitizer,
      focusNode: focusNode,
    );
  }

  Widget _multilineField(
    TextEditingController controller,
    String label, {
    FocusNode? focusNode,
  }) {
    // Disabled for the same reason as NmtkTextInput -- see its build() --
    // this field bypasses that wrapper and builds TextField directly.
    return SelectionContainer.disabled(
      child: TextField(
        controller: controller,
        focusNode: focusNode,
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
          cleanInstall: _factoryReset,
        );
    if (mounted) {
      setState(() {
        _submittedDeploymentJobId = job.id;
        _isWorking = false;
      });
    }
  }

  /// One-tap backend update: validate, then redeploy in place.
  ///
  /// Reuses the ordinary validate-then-deploy path rather than adding a second
  /// deployment route — `install.sh` already does `compose down` → `pull` →
  /// `up -d`, which *is* an update. Validation is kept deliberately: it checks
  /// SSH and the container engine before touching a backend that currently
  /// works.
  Future<void> _updateBackend() async {
    // An update must never drop volumes — keeping workspaces and notebooks is
    // the entire difference between this and a clean install.
    if (_factoryReset) {
      setState(() => _factoryReset = false);
    }
    await _runPreflight();
    if (!mounted || !_hasFreshSuccessfulPreflight) return;
    await _deploy();
  }

  Widget _buildUpdateBanner(NmtkShellTokens tokens) {
    final update = ref.watch(backendUpdateProvider).value;
    // Null covers every "nothing to offer" case — unreachable backend, source
    // build, GitHub down, already current. Never guess at an update.
    if (update == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.sectionGap),
      child: NmtkSurfaceCard(
        key: const Key('backend-update-available'),
        child: Padding(
          padding: EdgeInsets.all(tokens.sectionGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NmtkStatusBanner(
                title: 'Backend update available — ${update.version}',
                content: const Text(
                  'Your workspaces and notebooks are kept. The backend '
                  'restarts while it updates, so finish any running training '
                  'first.',
                ),
                tone: NmtkTone.info,
              ),
              SizedBox(height: tokens.compactGap),
              ZetaButton(
                key: const Key('backend-update-action'),
                onPressed: _isWorking ? null : _updateBackend,
                label: _isWorking ? 'Updating…' : 'Update backend',
              ),
            ],
          ),
        ),
      ),
    );
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
    final valid = _canonicalIpv4(_host.text) != null;
    setState(() {
      _hostError =
          valid ? null : 'Enter an IPv4 address, for example 192.168.2.34.';
    });
    return valid;
  }

  /// Starts the same setup again on the same host after a stall or failure.
  ///
  /// The administrator credential is never persisted, so the one thing the user
  /// must supply again is the password or key. Ask for it in place instead of
  /// failing validation with a generic message.
  Future<void> _retryRemoteSetup() async {
    final hasCredential = _rootAuthMethod == 'ssh_password'
        ? _rootPassword.text.isNotEmpty
        : _rootPrivateKey.text.trim().isNotEmpty;
    if (!hasCredential) {
      setState(() {
        _setupError = 'Enter the administrator password again to retry. '
            'It is used once and never saved.';
      });
      (_rootAuthMethod == 'ssh_password'
              ? _rootPasswordFocus
              : _rootPrivateKeyFocus)
          .requestFocus();
      return;
    }
    await _setupRemoteServer(isRetry: true);
  }

  Future<void> _setupRemoteServer({bool isRetry = false}) async {
    if (!_validateRemoteHost()) return;
    final hasCredential = _rootAuthMethod == 'ssh_password'
        ? _rootPassword.text.isNotEmpty
        : _rootPrivateKey.text.trim().isNotEmpty;
    if (_rootUsername.text.trim().isEmpty || !hasCredential) {
      setState(() {
        _setupError =
            'Enter the administrator username and selected credential.';
      });
      return;
    }
    final factoryReset = _factoryReset;
    if (factoryReset) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => ZetaDialog(
          title: 'Factory reset server data?',
          message: 'This permanently removes NMTK databases, notebooks, '
              'workspace state, and container volumes on ${_host.text.trim()}.',
          primaryButtonLabel: 'Erase and reinstall',
          onPrimaryButtonPressed: () => Navigator.pop(dialogContext, true),
          secondaryButtonLabel: 'Cancel',
          onSecondaryButtonPressed: () => Navigator.pop(dialogContext, false),
        ),
      );
      if (confirmed != true) return;
    }
    setState(() {
      _isWorking = true;
      _setupError = null;
      _factoryReset = false;
      _completionQueued = false;
      _clearPreflight();
    });
    try {
      final notifier = ref.read(backendDeploymentProvider.notifier);
      final request = RemoteServerSetupRequest(
        host: _host.text,
        adminUsername: _rootUsername.text,
        adminPassword:
            _rootAuthMethod == 'ssh_password' ? _rootPassword.text : '',
        adminPrivateKey:
            _rootAuthMethod == 'ssh_key' ? _rootPrivateKey.text : '',
        containerEngine: _mode,
        reinstallMode: factoryReset
            ? RemoteReinstallMode.factoryReset
            : RemoteReinstallMode.preserveData,
      );
      final job = isRetry
          ? await notifier.retryRemoteSetup(request)
          : await notifier.setupRemoteServer(request);
      if (!mounted) return;
      setState(() {
        _submittedDeploymentJobId = job.id;
        _rootPassword.clear();
        _rootPrivateKey.clear();
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _setupError = _displaySetupError(error));
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  String _displaySetupError(Object error) {
    return error
        .toString()
        .replaceFirst(RegExp(r'^(Bad state|FormatException):\s*'), '');
  }

  String? _canonicalIpv4(String value) {
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
