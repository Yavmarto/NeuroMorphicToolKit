import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/providers/akida_deploy_provider.dart'
    as deploy_provider;

typedef AkidaDeployProvider = deploy_provider.AkidaDeployProvider;
typedef AkidaDeployStep = deploy_provider.AkidaDeployStep;
typedef DeployRuntimeMode = deploy_provider.AkidaRuntimeMode;

/// BrainChip Akida scaffold export and runtime verification screen.
///
/// Workflow:
/// 1. CNL Specification — enter spec, choose bit-width and Akida version,
///    check readiness via NeuroCNL
/// 2. Exportability Verdict — support state badge with topology verdict
/// 3. Deploy Config — generate scaffold package, then verify SDK deployability
///    through Neurochip
/// 4. Package And SDK Status — show saved ZIP plus runtime verification result
/// 5. Neurobench Verification (optional) — available only after SDK verification
class AkidaDeployScreen extends ConsumerStatefulWidget {
  const AkidaDeployScreen({super.key});

  @override
  ConsumerState<AkidaDeployScreen> createState() => _AkidaDeployScreenState();
}

class _AkidaDeployScreenState extends ConsumerState<AkidaDeployScreen> {
  final _specController = TextEditingController();
  final _remoteHostNameController = TextEditingController();
  final _remoteHostAddressController = TextEditingController();
  final _remoteHostSshPortController = TextEditingController(text: '22');
  final _remoteHostUsernameController = TextEditingController();
  final _remoteHostPasswordController = TextEditingController();
  final _remoteHostUrlController = TextEditingController();
  final _remoteControlUrlController = TextEditingController();
  final _remoteInstallRootController = TextEditingController(
    text: '/opt/neurochip-akida-host',
  );
  final _remoteServiceUserController = TextEditingController(
    text: 'neurochip',
  );
  int _weightBitWidth = 4;
  String _akidaVersion = 'akida1';
  String? _remoteHostFormId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(akidaDeployStateProvider).refreshRuntimeSetup();
    });
  }

  @override
  void dispose() {
    _specController.dispose();
    _remoteHostNameController.dispose();
    _remoteHostAddressController.dispose();
    _remoteHostSshPortController.dispose();
    _remoteHostUsernameController.dispose();
    _remoteHostPasswordController.dispose();
    _remoteHostUrlController.dispose();
    _remoteControlUrlController.dispose();
    _remoteInstallRootController.dispose();
    _remoteServiceUserController.dispose();
    super.dispose();
  }

  void _syncRemoteHostControllers(AkidaDeployProvider provider) {
    final selectedRemoteHost = provider.selectedRemoteHost;
    if (_remoteHostFormId != selectedRemoteHost?.id &&
        selectedRemoteHost != null) {
      _remoteHostFormId = selectedRemoteHost.id;
      _remoteHostNameController.text = selectedRemoteHost.displayName;
      _remoteHostAddressController.text = selectedRemoteHost.host;
      _remoteHostSshPortController.text = selectedRemoteHost.sshPort.toString();
      _remoteHostUsernameController.text = selectedRemoteHost.username;
      _remoteHostPasswordController.clear();
      _remoteHostUrlController.text = selectedRemoteHost.runtimeApiUrl;
      _remoteControlUrlController.text = selectedRemoteHost.controlApiUrl;
      _remoteInstallRootController.text = selectedRemoteHost.remoteInstallRoot;
      _remoteServiceUserController.text = selectedRemoteHost.serviceUser;
    } else if (selectedRemoteHost == null && _remoteHostFormId != null) {
      _remoteHostFormId = null;
      _remoteHostNameController.clear();
      _remoteHostAddressController.clear();
      _remoteHostSshPortController.text = '22';
      _remoteHostUsernameController.clear();
      _remoteHostPasswordController.clear();
      _remoteHostUrlController.clear();
      _remoteControlUrlController.clear();
      _remoteInstallRootController.text = '/opt/neurochip-akida-host';
      _remoteServiceUserController.text = 'neurochip';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Akida Deploy'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset',
            onPressed: () => ref.read(akidaDeployStateProvider).reset(),
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          final provider = ref.watch(akidaDeployStateProvider);
          _syncRemoteHostControllers(provider);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NmtkPipelineStepper(steps: _buildPipelineSteps(provider)),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCnlInputCard(context, provider),
                      if (provider.exportResult != null) ...[
                        const SizedBox(height: 16),
                        _buildVerdictCard(context, provider),
                      ],
                      if (_canShowDeployCard(provider)) ...[
                        const SizedBox(height: 16),
                        _buildRuntimeTargetCard(context, provider),
                        const SizedBox(height: 16),
                        _buildDeployConfigCard(context, provider),
                      ],
                      if (provider.deployJob != null ||
                          provider.sdkVerification != null ||
                          provider.savedPackagePath != null) ...[
                        const SizedBox(height: 16),
                        _buildDeployStatusCard(context, provider),
                      ],
                      if (provider.neurobenchResult != null) ...[
                        const SizedBox(height: 16),
                        _buildNeurobenchResultCard(context, provider),
                      ],
                      if (provider.errorMessage != null &&
                          provider.currentStep == AkidaDeployStep.error) ...[
                        const SizedBox(height: 16),
                        _buildErrorCard(context, provider),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Maps the current [AkidaDeployStep] to pipeline stepper step data.
  List<NmtkPipelineStepData> _buildPipelineSteps(AkidaDeployProvider provider) {
    final step = provider.currentStep;

    NmtkStepStatus readinessStatus;
    NmtkStepStatus scaffoldStatus;
    NmtkStepStatus runtimeStatus;
    NmtkStepStatus verifyStatus;

    switch (step) {
      case AkidaDeployStep.idle:
        readinessStatus = NmtkStepStatus.idle;
        scaffoldStatus = NmtkStepStatus.idle;
        runtimeStatus = NmtkStepStatus.idle;
        verifyStatus = NmtkStepStatus.idle;
      case AkidaDeployStep.checking:
        readinessStatus = NmtkStepStatus.running;
        scaffoldStatus = NmtkStepStatus.idle;
        runtimeStatus = NmtkStepStatus.idle;
        verifyStatus = NmtkStepStatus.idle;
      case AkidaDeployStep.checked:
        readinessStatus = NmtkStepStatus.success;
        scaffoldStatus = NmtkStepStatus.idle;
        runtimeStatus = NmtkStepStatus.idle;
        verifyStatus = NmtkStepStatus.idle;
      case AkidaDeployStep.deploying:
        readinessStatus = NmtkStepStatus.success;
        scaffoldStatus = NmtkStepStatus.running;
        runtimeStatus = NmtkStepStatus.idle;
        verifyStatus = NmtkStepStatus.idle;
      case AkidaDeployStep.polling:
        readinessStatus = NmtkStepStatus.success;
        scaffoldStatus = NmtkStepStatus.success;
        runtimeStatus = NmtkStepStatus.running;
        verifyStatus = NmtkStepStatus.idle;
      case AkidaDeployStep.verifying:
        readinessStatus = NmtkStepStatus.success;
        scaffoldStatus = NmtkStepStatus.success;
        runtimeStatus = _runtimeStepStatus(provider);
        verifyStatus = NmtkStepStatus.running;
      case AkidaDeployStep.done:
        readinessStatus = NmtkStepStatus.success;
        scaffoldStatus = NmtkStepStatus.success;
        runtimeStatus = _runtimeStepStatus(provider);
        verifyStatus = provider.neurobenchResult != null
            ? NmtkStepStatus.success
            : NmtkStepStatus.idle;
      case AkidaDeployStep.error:
        if (provider.exportResult == null) {
          readinessStatus = NmtkStepStatus.error;
          scaffoldStatus = NmtkStepStatus.idle;
          runtimeStatus = NmtkStepStatus.idle;
          verifyStatus = NmtkStepStatus.idle;
        } else if (provider.savedPackagePath == null) {
          readinessStatus = NmtkStepStatus.success;
          scaffoldStatus = NmtkStepStatus.error;
          runtimeStatus = NmtkStepStatus.idle;
          verifyStatus = NmtkStepStatus.idle;
        } else if (provider.neurobenchJobId == null) {
          readinessStatus = NmtkStepStatus.success;
          scaffoldStatus = NmtkStepStatus.success;
          runtimeStatus = _runtimeStepStatus(provider);
          verifyStatus = NmtkStepStatus.idle;
        } else {
          readinessStatus = NmtkStepStatus.success;
          scaffoldStatus = NmtkStepStatus.success;
          runtimeStatus = _runtimeStepStatus(provider);
          verifyStatus = NmtkStepStatus.error;
        }
    }

    return [
      NmtkPipelineStepData(
        label: 'Readiness',
        status: readinessStatus,
        detail: _readinessDetail(provider),
        icon: Icons.fact_check_outlined,
      ),
      NmtkPipelineStepData(
        label: 'Scaffold',
        status: scaffoldStatus,
        detail: step == AkidaDeployStep.deploying ? 'generating…' : null,
        icon: Icons.architecture_outlined,
      ),
      NmtkPipelineStepData(
        label: 'Runtime',
        status: runtimeStatus,
        detail: _runtimeDetail(provider),
        icon: Icons.memory_outlined,
      ),
      NmtkPipelineStepData(
        label: 'Verify',
        status: verifyStatus,
        detail: _verifyDetail(provider),
        icon: Icons.science_outlined,
      ),
    ];
  }

  String? _readinessDetail(AkidaDeployProvider provider) {
    final result = provider.exportResult;
    if (result == null) return null;
    switch (result.supportState) {
      case AkidaSupportState.exportableScaffold:
        return 'scaffold ready';
      case AkidaSupportState.exportableScaffoldWithWarnings:
        return '${result.warnings.length} warning(s)';
      case AkidaSupportState.unsupported:
        return 'unsupported';
      case AkidaSupportState.sdkDeployable:
        return 'sdk deployable';
      case AkidaSupportState.sdkNotDeployable:
        return 'sdk unavailable';
    }
  }

  String? _verifyDetail(AkidaDeployProvider provider) {
    final result = provider.neurobenchResult;
    if (result == null) return null;
    final status = result['status'] as String? ?? '';
    return status.isNotEmpty ? status : null;
  }

  NmtkStepStatus _runtimeStepStatus(AkidaDeployProvider provider) {
    final verification = provider.sdkVerification;
    if (verification == null) {
      return provider.currentStep == AkidaDeployStep.polling
          ? NmtkStepStatus.running
          : NmtkStepStatus.idle;
    }
    if (provider.isExpectedLocalSimulatorOutcome) {
      return NmtkStepStatus.success;
    }
    return verification.isDeployable
        ? NmtkStepStatus.success
        : NmtkStepStatus.error;
  }

  String? _runtimeDetail(AkidaDeployProvider provider) {
    if (provider.currentStep == AkidaDeployStep.polling &&
        provider.sdkVerification == null) {
      return provider.runtimeMode.label.toLowerCase();
    }

    final verification = provider.sdkVerification;
    if (verification == null) {
      return provider.exportResult == null ? null : provider.runtimeMode.label;
    }

    if (provider.isExpectedLocalSimulatorOutcome) {
      return 'local simulator';
    }

    switch (verification.sdkStatus) {
      case 'deployable':
        return provider.runtimeMode.label;
      case 'not_available':
        return provider.runtimeMode == DeployRuntimeMode.remoteSdk
            ? 'remote SDK unavailable'
            : 'SDK unavailable';
      case 'mapping_failed':
        return 'mapping failed';
      default:
        return provider.runtimeMode.label;
    }
  }

  bool _canShowDeployCard(AkidaDeployProvider provider) {
    if (provider.exportResult == null) return false;
    final state = provider.exportResult!.supportState;
    return state == AkidaSupportState.exportableScaffold ||
        state == AkidaSupportState.exportableScaffoldWithWarnings ||
        state == AkidaSupportState.sdkDeployable ||
        state == AkidaSupportState.sdkNotDeployable;
  }

  // ---------- Step 1: CNL Input ----------

  Widget _buildCnlInputCard(
    BuildContext context,
    AkidaDeployProvider provider,
  ) {
    final isChecking = provider.currentStep == AkidaDeployStep.checking;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CNL Specification',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _specController,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: 'Enter your NeuroCNL specification…\n'
                    'Example: The sensory neuron MUST fire ONLY IF '
                    'membrane potential exceeds 1.0.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Weight bit-width:'),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _weightBitWidth,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('1-bit')),
                        DropdownMenuItem(value: 2, child: Text('2-bit')),
                        DropdownMenuItem(value: 4, child: Text('4-bit')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _weightBitWidth = v);
                      },
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Akida version:'),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _akidaVersion,
                      items: const [
                        DropdownMenuItem(
                          value: 'akida1',
                          child: Text('Akida 1'),
                        ),
                        DropdownMenuItem(
                          value: 'akida2',
                          child: Text('Akida 2'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _akidaVersion = v);
                      },
                    ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: isChecking || _specController.text.trim().isEmpty
                      ? null
                      : () => provider.checkExportability(
                            spec: _specController.text,
                            weightBitWidth: _weightBitWidth,
                            akidaVersion: _akidaVersion,
                          ),
                  icon: isChecking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fact_check),
                  label: Text(isChecking ? 'Checking…' : 'Check Readiness'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Step 2: Exportability Verdict ----------

  Widget _buildVerdictCard(BuildContext context, AkidaDeployProvider provider) {
    final result = provider.exportResult!;
    return AkidaSupportStateCard(
      supportState: result.supportState,
      warnings: result.warnings,
      rejections: result.rejectionReasons,
      networkSummary: result.networkSummary,
      akidaVersion: result.akidaVersion,
      topologyVerdict: result.topologyVerdict,
    );
  }

  // ---------- Step 3: Deploy Config ----------

  Widget _buildRuntimeTargetCard(
    BuildContext context,
    AkidaDeployProvider provider,
  ) {
    final module = provider.neurochipModule;
    final runtimeStatus = provider.runtimeStatus;
    final runtimeConfig = module?.akidaRuntime;
    final runtimeState = module?.akidaRuntimeState;
    final checks = provider.sdkVerification?.environmentChecks;
    final platformKey = _currentPlatformKey(context);
    final hostSupported =
        runtimeConfig?.supportedPlatforms.contains(platformKey) ?? false;
    final simulatorOnly =
        !hostSupported && runtimeConfig?.localModeFallback == 'simulator_only';
    final connectedChecks = runtimeStatus?.environmentChecks;
    final requiresRemoteRuntime = checks?.recommendedRuntime == 'remote_sdk' ||
        connectedChecks?.recommendedRuntime == 'remote_sdk' ||
        runtimeState?.status == 'unsupported_python';
    final showPrepareButton = provider.isLocalSdkMode &&
        runtimeConfig != null &&
        hostSupported &&
        !provider.isPreparingRuntime &&
        !requiresRemoteRuntime &&
        runtimeState?.status != 'ready';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Runtime Target',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Deploy and runtime verification requests follow the mode you choose here.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: DeployRuntimeMode.values
                  .map(
                    (mode) => ChoiceChip(
                      label: Text(mode.label),
                      selected: provider.runtimeMode == mode,
                      onSelected: (_) => provider.setRuntimeMode(mode),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 16),
            if (provider.isLoadingRuntimeSetup)
              const LinearProgressIndicator()
            else ...[
              if (runtimeStatus != null) ...[
                _buildRuntimeDiagnostics(context, runtimeStatus),
                const SizedBox(height: 12),
              ],
              if (provider.runtimeMode == DeployRuntimeMode.localSimulator)
                Text(
                  'Use the local Neurochip module in simulator-only mode. Scaffold generation stays local, and runtime checks remain truthful about the absence of a local BrainChip SDK.',
                )
              else if (requiresRemoteRuntime)
                const Text(
                  'This Neurochip environment does not satisfy the local Akida SDK requirements. Keep scaffold export local, then verify through a Linux or Windows Neurochip host running Python 3.10-3.12.',
                )
              else if (provider.runtimeMode == DeployRuntimeMode.localSdk)
                _buildLocalRuntimeSection(
                  context,
                  provider,
                  runtimeConfig: runtimeConfig,
                  runtimeState: runtimeState,
                  platformKey: platformKey,
                  simulatorOnly: simulatorOnly,
                  showPrepareButton: showPrepareButton,
                )
              else
                _buildRemoteRuntimeSection(context, provider),
            ],
            if (provider.runtimeSetupError != null) ...[
              const SizedBox(height: 12),
              Text(
                provider.runtimeSetupError!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRuntimeDiagnostics(
    BuildContext context,
    AkidaSdkVerification runtimeStatus,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_runtimeStatusHeadline(runtimeStatus)),
        const SizedBox(height: 8),
        Text(
          'Runtime target: ${_runtimeTargetLabel(runtimeStatus.runtimeTarget)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (runtimeStatus.deviceInfo != null) ...[
          const SizedBox(height: 4),
          Text(
            'Device: ${runtimeStatus.deviceInfo}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (runtimeStatus.sdkIssues.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Runtime issues: ${runtimeStatus.sdkIssues.join(", ")}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (runtimeStatus.sdkIssueDetail != null) ...[
          const SizedBox(height: 4),
          Text(
            runtimeStatus.sdkIssueDetail!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _buildLocalRuntimeSection(
    BuildContext context,
    AkidaDeployProvider provider, {
    required AkidaRuntimeConfig? runtimeConfig,
    required AkidaRuntimeState? runtimeState,
    required String platformKey,
    required bool simulatorOnly,
    required bool showPrepareButton,
  }) {
    if (runtimeConfig == null) {
      return Text(
        'Launcher runtime metadata is unavailable. Akida deploy can still generate scaffold packages.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (simulatorOnly)
          Text(
            'This launcher host is running on $platformKey. Local Akida SDK install is simulator-only here; use a Linux or Windows Neurochip host for SDK verification.',
          )
        else if (runtimeState?.status == 'ready')
          const Text(
            'Local Neurochip runtime is prepared for Akida SDK verification.',
          )
        else
          Text(
            'Install the BrainChip MetaTF runtime into the Neurochip environment only when you need local SDK verification. Base Neurochip install stays lean by default.',
          ),
        const SizedBox(height: 8),
        Text(
          'Target profile: ${runtimeConfig.pythonRange} • ${runtimeConfig.requiredPackages.join(", ")}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (runtimeState?.message != null) ...[
          const SizedBox(height: 8),
          Text(
            runtimeState!.message!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (runtimeState?.preparedAt != null) ...[
          const SizedBox(height: 4),
          Text(
            'Prepared: ${runtimeState!.preparedAt}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            if (showPrepareButton)
              FilledButton.icon(
                onPressed: () => provider.prepareLocalRuntime(),
                icon: const Icon(Icons.download_for_offline_outlined),
                label: const Text('Prepare Akida Runtime'),
              )
            else if (provider.isPreparingRuntime)
              const Expanded(child: LinearProgressIndicator()),
            const Spacer(),
            if (runtimeConfig.docsUrl.isNotEmpty)
              TextButton.icon(
                onPressed: () => _openUrl(runtimeConfig.docsUrl),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('BrainChip Install Docs'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildRemoteRuntimeSection(
    BuildContext context,
    AkidaDeployProvider provider,
  ) {
    final selectedRemoteHost = provider.selectedRemoteHost;
    final hostOperationInProgress = provider.hostOperationInProgress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Register a blank Linux host, test SSH connectivity, provision Neurochip and the Akida runtime, then use the resulting runtime for scaffold generation and SDK verification.',
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: provider.selectedRemoteHostId,
          isExpanded: true,
          hint: const Text('Create new remote host...'),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Remembered remote host',
          ),
          items: provider.remoteHosts
              .map(
                (host) => DropdownMenuItem<String>(
                  value: host.id,
                  child: Text(
                    host.displayName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: provider.selectRemoteHost,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 240,
              child: TextField(
                controller: _remoteHostNameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Display name',
                ),
              ),
            ),
            SizedBox(
              width: 240,
              child: TextField(
                controller: _remoteHostAddressController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Host address',
                  helperText: 'Example: akida-linux.local',
                ),
              ),
            ),
            SizedBox(
              width: 120,
              child: TextField(
                controller: _remoteHostSshPortController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'SSH port',
                ),
              ),
            ),
            SizedBox(
              width: 180,
              child: TextField(
                controller: _remoteHostUsernameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'SSH user',
                ),
              ),
            ),
            SizedBox(
              width: 240,
              child: TextField(
                controller: _remoteHostPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'SSH password',
                ),
              ),
            ),
            SizedBox(
              width: 320,
              child: TextField(
                controller: _remoteHostUrlController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Neurochip runtime URL',
                  helperText: 'Example: http://akida-linux:8002',
                ),
              ),
            ),
            SizedBox(
              width: 320,
              child: TextField(
                controller: _remoteControlUrlController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Control API URL',
                  helperText: 'Example: http://akida-linux:8090',
                ),
              ),
            ),
            SizedBox(
              width: 320,
              child: TextField(
                controller: _remoteInstallRootController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Remote install root',
                ),
              ),
            ),
            SizedBox(
              width: 180,
              child: TextField(
                controller: _remoteServiceUserController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Service user',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: hostOperationInProgress
                  ? null
                  : () => provider.saveRemoteHost(
                        hostId: selectedRemoteHost?.id,
                        displayName:
                            _remoteHostNameController.text.trim().isEmpty
                                ? _remoteHostAddressController.text.trim()
                                : _remoteHostNameController.text.trim(),
                        hostAddress: _remoteHostAddressController.text.trim(),
                        sshPort: int.tryParse(
                                _remoteHostSshPortController.text.trim()) ??
                            22,
                        username: _remoteHostUsernameController.text.trim(),
                        password: _remoteHostPasswordController.text,
                        runtimeApiUrl: _remoteHostUrlController.text.trim(),
                        controlApiUrl: _remoteControlUrlController.text.trim(),
                        remoteInstallRoot:
                            _remoteInstallRootController.text.trim(),
                        serviceUser: _remoteServiceUserController.text.trim(),
                      ),
              icon: const Icon(Icons.cloud_done_outlined),
              label: Text(
                selectedRemoteHost == null ? 'Save Host' : 'Update Host',
              ),
            ),
            OutlinedButton.icon(
              onPressed: selectedRemoteHost == null || hostOperationInProgress
                  ? null
                  : () => provider.testSelectedRemoteHostConnectivity(),
              icon: const Icon(Icons.network_ping_outlined),
              label: const Text('Test Connectivity'),
            ),
            FilledButton.icon(
              onPressed: selectedRemoteHost == null || hostOperationInProgress
                  ? null
                  : () => provider.provisionSelectedRemoteHost(),
              icon: const Icon(Icons.download_for_offline_outlined),
              label: const Text('Provision Host'),
            ),
            OutlinedButton.icon(
              onPressed: selectedRemoteHost == null || hostOperationInProgress
                  ? null
                  : () => provider.checkSelectedRemoteHostReadiness(),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Check Readiness'),
            ),
            OutlinedButton.icon(
              onPressed: selectedRemoteHost == null || hostOperationInProgress
                  ? null
                  : () => provider.repairSelectedRemoteHost(),
              icon: const Icon(Icons.build_circle_outlined),
              label: const Text('Repair'),
            ),
            OutlinedButton.icon(
              onPressed: selectedRemoteHost == null || hostOperationInProgress
                  ? null
                  : () => provider.restartSelectedRemoteHostServices(),
              icon: const Icon(Icons.restart_alt_outlined),
              label: const Text('Restart Services'),
            ),
            OutlinedButton.icon(
              onPressed: selectedRemoteHost == null || hostOperationInProgress
                  ? null
                  : () => provider.deleteSelectedRemoteHost(),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove Host'),
            ),
          ],
        ),
        if (provider.hostOperationInProgress) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (provider.hostFeedbackMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            provider.hostFeedbackMessage!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (selectedRemoteHost != null) ...[
          const SizedBox(height: 12),
          Text(
            'Selected runtime: ${selectedRemoteHost.displayName} • ${selectedRemoteHost.runtimeApiUrl}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'State: ${selectedRemoteHost.state.label} • SSH ${selectedRemoteHost.username}@${selectedRemoteHost.host}:${selectedRemoteHost.sshPort}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (selectedRemoteHost.controlApiUrl.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Control API: ${selectedRemoteHost.controlApiUrl}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (selectedRemoteHost.lastReadinessMessage.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              selectedRemoteHost.lastReadinessMessage,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (selectedRemoteHost.hostOs.isNotEmpty ||
              selectedRemoteHost.pythonVersion.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Remote environment: ${selectedRemoteHost.hostOs.isEmpty ? "unknown os" : selectedRemoteHost.hostOs} • Python ${selectedRemoteHost.pythonVersion.isEmpty ? "unknown" : selectedRemoteHost.pythonVersion}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (selectedRemoteHost.hasPassword) ...[
            const SizedBox(height: 4),
            Text(
              'Launcher has stored SSH credentials for provisioning and repair.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildDeployConfigCard(
    BuildContext context,
    AkidaDeployProvider provider,
  ) {
    final isDeploying = provider.currentStep == AkidaDeployStep.deploying ||
        provider.currentStep == AkidaDeployStep.polling;
    final canStartDeploy = provider.exportResult?.mappedNetwork != null &&
        provider.canDeployToSelectedRuntime;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Scaffold Package + Runtime Verify',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: const Color(0xFF5C6BC0)),
            ),
            const SizedBox(height: 8),
            Text(
              _deployCardDescription(provider),
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 12),
            Text(
              'Selected target: ${_selectedRuntimeSummary(provider)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Switch(
                  value: provider.runNeurobench,
                  onChanged: provider.setRunNeurobench,
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text('Run Neurobench verification after deploy'),
                ),
                const Spacer(),
                if (!provider.canDeployToSelectedRuntime) ...[
                  Flexible(
                    child: Text(
                      'Save a remote SDK host before sending deploy and verification requests away from the local Neurochip module.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.red),
                      textAlign: TextAlign.end,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                FilledButton.icon(
                  onPressed: isDeploying || !canStartDeploy
                      ? null
                      : () => _startDeploy(provider),
                  icon: isDeploying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: Text(
                    isDeploying ? 'Generating…' : 'Download Scaffold Package',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startDeploy(AkidaDeployProvider provider) async {
    final mappedNetwork = provider.exportResult?.mappedNetwork;
    if (mappedNetwork == null) return;
    final dir = await getApplicationDocumentsDirectory();
    if (!mounted) return;
    await provider.startDeploy(
      mappedNetwork: mappedNetwork,
      bitWidth: _weightBitWidth,
      outputDir: dir.path,
    );
  }

  String _deployCardDescription(AkidaDeployProvider provider) {
    switch (provider.runtimeMode) {
      case DeployRuntimeMode.localSimulator:
        return 'Generate the scaffold package through the local Neurochip module, then confirm the launcher remains in local simulator mode without claiming SDK-backed execution.';
      case DeployRuntimeMode.localSdk:
        return 'Generate the scaffold package locally, then let the local Neurochip module verify whether the same mapped payload is deployable via the Akida SDK.';
      case DeployRuntimeMode.remoteSdk:
        final selectedRemoteHost = provider.selectedRemoteHost;
        if (selectedRemoteHost == null) {
          return 'Select a remote Neurochip runtime before sending scaffold generation and runtime verification requests to a remote SDK host.';
        }
        return 'Send scaffold generation and runtime verification requests to ${selectedRemoteHost.displayName} so the remote Neurochip host decides whether the mapped payload is SDK-deployable.';
    }
  }

  String _selectedRuntimeSummary(AkidaDeployProvider provider) {
    switch (provider.runtimeMode) {
      case DeployRuntimeMode.localSimulator:
        return 'Local Neurochip module • simulator-only mode';
      case DeployRuntimeMode.localSdk:
        return 'Local Neurochip module • SDK runtime';
      case DeployRuntimeMode.remoteSdk:
        final selectedRemoteHost = provider.selectedRemoteHost;
        if (selectedRemoteHost == null) {
          return 'Remote SDK host not configured';
        }
        return '${selectedRemoteHost.displayName} • ${selectedRemoteHost.runtimeApiUrl}';
    }
  }

  // ---------- Step 4: Deployment Status ----------

  Widget _buildDeployStatusCard(
    BuildContext context,
    AkidaDeployProvider provider,
  ) {
    final job = provider.deployJob;
    final sdkVerification = provider.sdkVerification;
    final savedPath = provider.savedPackagePath;
    final isPolling = provider.currentStep == AkidaDeployStep.polling;
    final isDone = provider.currentStep == AkidaDeployStep.done ||
        provider.currentStep == AkidaDeployStep.verifying;

    final progressValue =
        isPolling ? null : (savedPath != null || isDone ? 1.0 : null);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Package And SDK Status',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progressValue),
            const SizedBox(height: 8),
            Text(
              'Selected target: ${_selectedRuntimeSummary(provider)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (savedPath != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Package saved: $savedPath',
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _openInFinder(savedPath),
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('Open'),
                  ),
                ],
              ),
            ],
            if (job != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    _jobIcon(job.status),
                    color: _jobColor(job.status),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(_jobLabel(job)),
                ],
              ),
            ],
            if (sdkVerification != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    _runtimeIcon(provider, sdkVerification),
                    color: _runtimeColor(provider, sdkVerification),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_runtimeStatusLabel(provider, sdkVerification)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Backend outcome: ${_runtimeTargetLabel(sdkVerification.runtimeTarget)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (sdkVerification.deviceInfo != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Device: ${sdkVerification.deviceInfo}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (sdkVerification.sdkIssues.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Runtime issues: ${sdkVerification.sdkIssues.join(", ")}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (sdkVerification.sdkIssueDetail != null) ...[
                const SizedBox(height: 4),
                Text(
                  sdkVerification.sdkIssueDetail!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (sdkVerification.environmentChecks?.recommendedRuntime ==
                  'remote_sdk') ...[
                const SizedBox(height: 4),
                Text(
                  'This Neurochip environment does not satisfy the local Akida SDK requirements. Re-run SDK verification through a Linux or Windows Neurochip host with Python 3.10-3.12.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else if (sdkVerification
                      .environmentChecks?.recommendedRuntime ==
                  'simulator_only') ...[
                const SizedBox(height: 4),
                Text(
                  'Local simulator is available, but real SDK verification requires Neurochip on Linux or Windows.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else if (sdkVerification.sdkStatus == 'not_available') ...[
                const SizedBox(height: 4),
                Text(
                  'Run Neurochip on Linux or Windows with the BrainChip SDK installed to verify deployability.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
            if (provider.runNeurobench &&
                isDone &&
                provider.neurobenchResult == null &&
                provider.sdkVerification?.isDeployable != true) ...[
              const SizedBox(height: 12),
              Text(
                'Neurobench verification was skipped because SDK verification did not succeed.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (!provider.runNeurobench &&
                isDone &&
                provider.sdkVerification?.isDeployable == true &&
                provider.neurobenchResult == null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => provider.runVerification(),
                  icon: const Icon(Icons.science),
                  label: const Text('Run Neurobench Verification'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openInFinder(String path) async {
    final uri = Uri.parse('file://$path');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  IconData _jobIcon(AkidaDeployJobStatus status) {
    switch (status) {
      case AkidaDeployJobStatus.mapped:
      case AkidaDeployJobStatus.running:
        return Icons.check_circle;
      case AkidaDeployJobStatus.failed:
        return Icons.error;
      default:
        return Icons.hourglass_top;
    }
  }

  Color _jobColor(AkidaDeployJobStatus status) {
    switch (status) {
      case AkidaDeployJobStatus.mapped:
      case AkidaDeployJobStatus.running:
        return Colors.green;
      case AkidaDeployJobStatus.failed:
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  String _jobLabel(AkidaDeployJob job) {
    switch (job.status) {
      case AkidaDeployJobStatus.notInitialised:
        return 'Initialising backend…';
      case AkidaDeployJobStatus.sdkLoading:
        return 'Loading Akida SDK…';
      case AkidaDeployJobStatus.modelMapping:
        return 'Mapping model to device…';
      case AkidaDeployJobStatus.mapped:
        return 'Mapped representation prepared';
      case AkidaDeployJobStatus.running:
        return 'Running inference';
      case AkidaDeployJobStatus.failed:
        return 'Backend deploy failed';
    }
  }

  IconData _runtimeIcon(
    AkidaDeployProvider provider,
    AkidaSdkVerification verification,
  ) {
    if (provider.isExpectedLocalSimulatorOutcome) {
      return Icons.memory_outlined;
    }
    switch (verification.sdkStatus) {
      case 'deployable':
        return Icons.check_circle;
      case 'mapping_failed':
        return Icons.error;
      case 'not_available':
        return Icons.cloud_off;
      default:
        return Icons.help_outline;
    }
  }

  Color _runtimeColor(
    AkidaDeployProvider provider,
    AkidaSdkVerification verification,
  ) {
    if (provider.isExpectedLocalSimulatorOutcome) {
      return Colors.blue;
    }
    switch (verification.sdkStatus) {
      case 'deployable':
        return Colors.green;
      case 'mapping_failed':
      case 'not_available':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  String _runtimeStatusLabel(
    AkidaDeployProvider provider,
    AkidaSdkVerification verification,
  ) {
    if (provider.isExpectedLocalSimulatorOutcome) {
      return 'Local simulator mode selected';
    }

    final checks = verification.environmentChecks;
    if (verification.sdkStatus == 'not_available' && checks != null) {
      if (!checks.hostSupported) {
        return provider.runtimeMode == DeployRuntimeMode.remoteSdk
            ? 'Selected remote SDK host does not support Akida'
            : 'Local SDK install unsupported on this host';
      }
      if (!checks.pythonSupported) {
        return 'SDK verification blocked: unsupported Python runtime';
      }
      if (!checks.tensorflowAvailable) {
        return 'SDK verification blocked: TensorFlow 2.19 missing';
      }
      if (!checks.cnn2snnAvailable) {
        return 'SDK verification blocked: cnn2snn missing';
      }
      if (!checks.akidaModelsAvailable) {
        return 'SDK verification blocked: akida-models missing';
      }
    }
    switch (verification.sdkStatus) {
      case 'deployable':
        return 'SDK verification succeeded';
      case 'mapping_failed':
        return 'SDK verification failed during model mapping';
      case 'not_available':
        return 'SDK verification blocked: BrainChip SDK unavailable';
      default:
        return 'SDK verification pending';
    }
  }

  String _runtimeStatusHeadline(AkidaSdkVerification verification) {
    switch (verification.runtimeTarget) {
      case 'hardware':
        return 'Connected Neurochip runtime reports attached Akida hardware.';
      case 'akd1000_simulator':
        return 'Connected Neurochip runtime is using the AKD1000 simulator; no physical Akida device is attached.';
      case 'software_fallback':
        if (verification.sdkStatus == 'not_available') {
          return 'Connected Neurochip runtime is in software fallback only; real SDK mapping is not available on this host.';
        }
        return 'Connected Neurochip runtime is using software fallback only.';
      default:
        if (verification.sdkStatus == 'mapping_failed') {
          return 'Connected Neurochip runtime reached the SDK, but model mapping failed.';
        }
        if (verification.sdkIssues.isNotEmpty ||
            verification.sdkIssueDetail != null) {
          return 'Connected Neurochip runtime is reachable, but Akida runtime diagnostics report configuration problems.';
        }
        return 'Connected Neurochip runtime diagnostics are available, but no Akida target has been verified yet.';
    }
  }

  String _runtimeTargetLabel(String runtimeTarget) {
    switch (runtimeTarget) {
      case 'hardware':
        return 'hardware';
      case 'akd1000_simulator':
        return 'AKD1000 simulator';
      case 'software_fallback':
        return 'software fallback';
      default:
        return 'unknown';
    }
  }

  String _currentPlatformKey(BuildContext context) {
    switch (Theme.of(context).platform) {
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      default:
        return Theme.of(context).platform.name;
    }
  }

  // ---------- Step 5: Neurobench Verification ----------

  Widget _buildNeurobenchResultCard(
    BuildContext context,
    AkidaDeployProvider provider,
  ) {
    final result = provider.neurobenchResult!;
    final status = result['status'] as String? ?? '';
    final isCompleted = status == 'completed';
    final isFailed = status == 'failed';

    return Card(
      color: isCompleted
          ? Colors.green.withValues(alpha: 0.08)
          : isFailed
              ? Colors.red.withValues(alpha: 0.08)
              : null,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isCompleted
                      ? Icons.verified
                      : isFailed
                          ? Icons.error
                          : Icons.hourglass_top,
                  color: isCompleted
                      ? Colors.green
                      : isFailed
                          ? Colors.red
                          : Colors.blue,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  'Neurobench Verification',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (provider.neurobenchJobId != null)
                  Text(
                    'Job: ${provider.neurobenchJobId}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            if (!isCompleted && !isFailed) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              Text(
                'Status: $status',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (result['results'] != null) ...[
              const SizedBox(height: 8),
              Text(
                result['results'].toString(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------- Error ----------

  Widget _buildErrorCard(BuildContext context, AkidaDeployProvider provider) {
    return Card(
      color: Colors.red.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            const Icon(Icons.error, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                provider.errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
            TextButton(
              onPressed: () => provider.reset(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
