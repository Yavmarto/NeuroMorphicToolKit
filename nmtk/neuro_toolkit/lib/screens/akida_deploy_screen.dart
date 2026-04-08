import 'package:flutter/material.dart';
import 'package:neuro_toolkit/providers/akida_deploy_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// BrainChip Akida scaffold export and optional SDK deployment screen.
///
/// Workflow:
/// 1. CNL Specification — enter spec, choose bit-width and Akida version,
///    check readiness via NeuroCNL
/// 2. Exportability Verdict — support state badge with topology verdict
/// 3. Deploy Config — confirm settings, optionally enable Neurobench verify,
///    download scaffold package from Neurochip
/// 4. Deployment Status — progress indicator; open saved ZIP in Finder
/// 5. Neurobench Verification (optional) — poll job status, show results
class AkidaDeployScreen extends StatefulWidget {
  const AkidaDeployScreen({super.key});

  @override
  State<AkidaDeployScreen> createState() => _AkidaDeployScreenState();
}

class _AkidaDeployScreenState extends State<AkidaDeployScreen> {
  final _specController = TextEditingController();
  int _weightBitWidth = 4;
  String _akidaVersion = 'akida1';

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
            onPressed: () => context.read<AkidaDeployProvider>().reset(),
          ),
        ],
      ),
      body: Consumer<AkidaDeployProvider>(
        builder: (context, provider, child) {
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
                        _buildDeployConfigCard(context, provider),
                      ],
                      if (provider.deployJob != null ||
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
  List<NmtkPipelineStepData> _buildPipelineSteps(
      AkidaDeployProvider provider) {
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
        sdkStatus = NmtkStepStatus.success;
        verifyStatus = NmtkStepStatus.running;
      case AkidaDeployStep.done:
        readinessStatus = NmtkStepStatus.success;
        scaffoldStatus = NmtkStepStatus.success;
        sdkStatus = NmtkStepStatus.success;
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
        detail: step == AkidaDeployStep.polling ? 'polling…' : null,
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
      BuildContext context, AkidaDeployProvider provider) {
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
                hintText:
                    'Enter your NeuroCNL specification…\n'
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

  Widget _buildVerdictCard(
      BuildContext context, AkidaDeployProvider provider) {
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

  Widget _buildDeployConfigCard(
      BuildContext context, AkidaDeployProvider provider) {
    final isDeploying = provider.currentStep == AkidaDeployStep.deploying ||
        provider.currentStep == AkidaDeployStep.polling;

    final state = provider.exportResult?.supportState;
    final String cardTitle;
    final Color headerColor;
    if (state == AkidaSupportState.sdkDeployable) {
      cardTitle = 'SDK Deployment';
      headerColor = const Color(0xFF388E3C); // Green 700
    } else if (state == AkidaSupportState.sdkNotDeployable) {
      cardTitle = 'Scaffold Only — SDK Unavailable';
      headerColor = const Color(0xFFFFA000); // Amber 700
    } else {
      cardTitle = 'Scaffold Package';
      headerColor = const Color(0xFF5C6BC0); // Indigo 400
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cardTitle,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: headerColor),
            ),
            if (state == AkidaSupportState.sdkNotDeployable) ...[
              const SizedBox(height: 8),
              const Text(
                'The Akida SDK is not installed. A MetaTF scaffold package '
                'will be generated for offline use with the BrainChip SDK.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
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
      BuildContext context, AkidaDeployProvider provider) {
    final job = provider.deployJob;
    final savedPath = provider.savedPackagePath;
    final isPolling = provider.currentStep == AkidaDeployStep.polling;
    final isDone = provider.currentStep == AkidaDeployStep.done ||
        provider.currentStep == AkidaDeployStep.verifying;

    final progressValue = job != null
        ? (isPolling &&
                job.status == AkidaDeployJobStatus.notInitialised
            ? null
            : job.status.progressFraction)
        : (isDone ? 1.0 : null);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deployment Status',
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
              if (job.deviceInfo != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Device: ${job.deviceInfo}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
            if (!provider.runNeurobench &&
                isDone &&
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
        return 'Model mapped — device ready';
      case AkidaDeployJobStatus.running:
        return 'Running inference';
      case AkidaDeployJobStatus.failed:
        return 'Backend deploy failed';
    }
  }

  // ---------- Step 5: Neurobench Verification ----------

  Widget _buildNeurobenchResultCard(
      BuildContext context, AkidaDeployProvider provider) {
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

  Widget _buildErrorCard(
      BuildContext context, AkidaDeployProvider provider) {
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
