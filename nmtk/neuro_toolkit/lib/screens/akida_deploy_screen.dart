import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/providers/akida_deploy_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

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
  int _weightBitWidth = 4;
  String _akidaVersion = 'akida1';

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
    super.dispose();
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
                        _buildRuntimeSetupCard(context, provider),
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
    NmtkStepStatus sdkStatus;
    NmtkStepStatus verifyStatus;

    switch (step) {
      case AkidaDeployStep.idle:
        readinessStatus = NmtkStepStatus.idle;
        scaffoldStatus = NmtkStepStatus.idle;
        sdkStatus = NmtkStepStatus.idle;
        verifyStatus = NmtkStepStatus.idle;
      case AkidaDeployStep.checking:
        readinessStatus = NmtkStepStatus.running;
        scaffoldStatus = NmtkStepStatus.idle;
        sdkStatus = NmtkStepStatus.idle;
        verifyStatus = NmtkStepStatus.idle;
      case AkidaDeployStep.checked:
        readinessStatus = NmtkStepStatus.success;
        scaffoldStatus = NmtkStepStatus.idle;
        sdkStatus = NmtkStepStatus.idle;
        verifyStatus = NmtkStepStatus.idle;
      case AkidaDeployStep.deploying:
        readinessStatus = NmtkStepStatus.success;
        scaffoldStatus = NmtkStepStatus.running;
        sdkStatus = NmtkStepStatus.idle;
        verifyStatus = NmtkStepStatus.idle;
      case AkidaDeployStep.polling:
        readinessStatus = NmtkStepStatus.success;
        scaffoldStatus = NmtkStepStatus.success;
        sdkStatus = NmtkStepStatus.running;
        verifyStatus = NmtkStepStatus.idle;
      case AkidaDeployStep.verifying:
        readinessStatus = NmtkStepStatus.success;
        scaffoldStatus = NmtkStepStatus.success;
        sdkStatus = provider.sdkVerification?.isDeployable == true
            ? NmtkStepStatus.success
            : NmtkStepStatus.error;
        verifyStatus = NmtkStepStatus.running;
      case AkidaDeployStep.done:
        readinessStatus = NmtkStepStatus.success;
        scaffoldStatus = NmtkStepStatus.success;
        sdkStatus = _sdkStepStatus(provider);
        verifyStatus = provider.neurobenchResult != null
            ? NmtkStepStatus.success
            : NmtkStepStatus.idle;
      case AkidaDeployStep.error:
        if (provider.exportResult == null) {
          readinessStatus = NmtkStepStatus.error;
          scaffoldStatus = NmtkStepStatus.idle;
          sdkStatus = NmtkStepStatus.idle;
          verifyStatus = NmtkStepStatus.idle;
        } else if (provider.savedPackagePath == null) {
          readinessStatus = NmtkStepStatus.success;
          scaffoldStatus = NmtkStepStatus.error;
          sdkStatus = NmtkStepStatus.idle;
          verifyStatus = NmtkStepStatus.idle;
        } else if (provider.neurobenchJobId == null) {
          readinessStatus = NmtkStepStatus.success;
          scaffoldStatus = NmtkStepStatus.success;
          sdkStatus = NmtkStepStatus.error;
          verifyStatus = NmtkStepStatus.idle;
        } else {
          readinessStatus = NmtkStepStatus.success;
          scaffoldStatus = NmtkStepStatus.success;
          sdkStatus = NmtkStepStatus.success;
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
        label: 'SDK',
        status: sdkStatus,
        detail: _sdkDetail(provider),
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

  NmtkStepStatus _sdkStepStatus(AkidaDeployProvider provider) {
    final verification = provider.sdkVerification;
    if (verification == null) {
      return provider.currentStep == AkidaDeployStep.polling
          ? NmtkStepStatus.running
          : NmtkStepStatus.idle;
    }
    return verification.isDeployable
        ? NmtkStepStatus.success
        : NmtkStepStatus.error;
  }

  String? _sdkDetail(AkidaDeployProvider provider) {
    if (provider.currentStep == AkidaDeployStep.polling &&
        provider.sdkVerification == null) {
      return 'verifying…';
    }

    final verification = provider.sdkVerification;
    if (verification == null) return null;

    switch (verification.sdkStatus) {
      case 'deployable':
        return _runtimeTargetLabel(verification.runtimeTarget);
      case 'not_available':
        return 'sdk unavailable';
      case 'mapping_failed':
        return 'mapping failed';
      default:
        return 'not verified';
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

  Widget _buildRuntimeSetupCard(
    BuildContext context,
    AkidaDeployProvider provider,
  ) {
    final module = provider.neurochipModule;
    final runtimeStatus = provider.runtimeStatus;
    final runtimeConfig = module?.akidaRuntime;
    final runtimeState = module?.akidaRuntimeState;
    final checks = provider.sdkVerification?.environmentChecks;

    if (runtimeConfig == null &&
        runtimeStatus == null &&
        !provider.isLoadingRuntimeSetup) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            provider.runtimeSetupError ??
                'Launcher runtime metadata is unavailable. Akida deploy can still generate scaffold packages.',
          ),
        ),
      );
    }

    final platformKey = _currentPlatformKey(context);
    final hostSupported =
        runtimeConfig?.supportedPlatforms.contains(platformKey) ?? false;
    final simulatorOnly =
        !hostSupported && runtimeConfig?.localModeFallback == 'simulator_only';
    final connectedChecks = runtimeStatus?.environmentChecks;
    final requiresRemoteRuntime = checks?.recommendedRuntime == 'remote_sdk' ||
        connectedChecks?.recommendedRuntime == 'remote_sdk' ||
        runtimeState?.status == 'unsupported_python';
    final showPrepareButton = runtimeConfig != null &&
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
              'Runtime Setup And Diagnostics',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (provider.isLoadingRuntimeSetup)
              const LinearProgressIndicator()
            else if (runtimeStatus != null) ...[
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
            ] else if (simulatorOnly)
              Text(
                'This launcher host is running on $platformKey. Local Akida SDK install is simulator-only here; use a Linux or Windows Neurochip host for SDK verification.',
              )
            else if (requiresRemoteRuntime)
              const Text(
                'This Neurochip environment does not satisfy the local Akida SDK requirements. Keep scaffold export local, then verify through a Linux or Windows Neurochip host running Python 3.10-3.12.',
              )
            else if (checks != null &&
                checks.recommendedRuntime == 'local_sdk' &&
                runtimeState?.status == 'ready')
              const Text(
                'Local Neurochip runtime is prepared for Akida SDK verification.',
              )
            else
              Text(
                'Install the BrainChip MetaTF runtime into the Neurochip environment only when you need local SDK verification. Base Neurochip install stays lean by default.',
              ),
            if (runtimeConfig != null) ...[
              const SizedBox(height: 8),
              Text(
                'Target profile: ${runtimeConfig.pythonRange} • ${runtimeConfig.requiredPackages.join(", ")}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
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
            if (provider.runtimeSetupError != null) ...[
              const SizedBox(height: 8),
              Text(
                provider.runtimeSetupError!,
                style: const TextStyle(color: Colors.red),
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
                if (runtimeConfig != null && runtimeConfig.docsUrl.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _openUrl(runtimeConfig.docsUrl),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('BrainChip Install Docs'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeployConfigCard(
    BuildContext context,
    AkidaDeployProvider provider,
  ) {
    final isDeploying = provider.currentStep == AkidaDeployStep.deploying ||
        provider.currentStep == AkidaDeployStep.polling;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Scaffold Package + SDK Verify',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: const Color(0xFF5C6BC0)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Generate the scaffold package first, then let Neurochip verify '
              'whether the same mapped payload is deployable via the Akida SDK '
              'in the current runtime environment.',
              style: TextStyle(fontStyle: FontStyle.italic),
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
                FilledButton.icon(
                  onPressed: isDeploying ||
                          provider.exportResult?.mappedNetwork == null
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
            if (savedPath != null) ...[
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
                    _sdkIcon(sdkVerification),
                    color: _sdkColor(sdkVerification),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_sdkStatusLabel(sdkVerification))),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Runtime target: ${_runtimeTargetLabel(sdkVerification.runtimeTarget)}',
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

  IconData _sdkIcon(AkidaSdkVerification verification) {
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

  Color _sdkColor(AkidaSdkVerification verification) {
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

  String _sdkStatusLabel(AkidaSdkVerification verification) {
    final checks = verification.environmentChecks;
    if (verification.sdkStatus == 'not_available' && checks != null) {
      if (!checks.hostSupported) {
        return 'Local SDK install unsupported on this host';
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
