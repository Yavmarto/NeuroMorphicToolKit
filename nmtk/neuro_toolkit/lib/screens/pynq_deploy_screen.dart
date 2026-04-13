import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/pynq_deploy_provider.dart';
import 'package:provider/provider.dart';

/// PYNQ Z2 deployment screen.
///
/// Workflow:
/// 1. CNL Specification — enter spec, choose bit-width, check exportability
/// 2. Exportability Verdict — support state badge, warnings, rejections
/// 3. Remote Endpoint — configure board URL and optional API key, deploy
/// 4. Deployment Status — poll until configured or failed
/// 5. SITL Verification (optional) — run Dream-Hand SITL, show result
class PynqDeployScreen extends StatefulWidget {
  const PynqDeployScreen({super.key});

  @override
  State<PynqDeployScreen> createState() => _PynqDeployScreenState();
}

class _PynqDeployScreenState extends State<PynqDeployScreen> {
  final _specController = TextEditingController();
  final _boardUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  int _weightBitWidth = 4;

  @override
  void dispose() {
    _specController.dispose();
    _boardUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PYNQ Z2 Deploy'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset',
            onPressed: () => context.read<PynqDeployProvider>().reset(),
          ),
        ],
      ),
      body: Consumer<PynqDeployProvider>(
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
                      if (_canShowEndpointCard(provider)) ...[
                        const SizedBox(height: 16),
                        _buildEndpointCard(context, provider),
                      ],
                      if (provider.deployJob != null) ...[
                        const SizedBox(height: 16),
                        _buildDeployStatusCard(context, provider),
                      ],
                      if (provider.sitlResult != null) ...[
                        const SizedBox(height: 16),
                        _buildSitlResultCard(context, provider),
                      ],
                      if (provider.errorMessage != null &&
                          provider.currentStep == PynqDeployStep.error) ...[
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

  /// Maps the current [PynqDeployStep] to pipeline stepper step data.
  List<NmtkPipelineStepData> _buildPipelineSteps(PynqDeployProvider provider) {
    final step = provider.currentStep;

    NmtkStepStatus prepareStatus;
    NmtkStepStatus deployStatus;
    NmtkStepStatus monitorStatus;
    NmtkStepStatus verifyStatus;

    switch (step) {
      case PynqDeployStep.idle:
        prepareStatus = NmtkStepStatus.idle;
        deployStatus = NmtkStepStatus.idle;
        monitorStatus = NmtkStepStatus.idle;
        verifyStatus = NmtkStepStatus.idle;
      case PynqDeployStep.checking:
        prepareStatus = NmtkStepStatus.running;
        deployStatus = NmtkStepStatus.idle;
        monitorStatus = NmtkStepStatus.idle;
        verifyStatus = NmtkStepStatus.idle;
      case PynqDeployStep.checked:
        prepareStatus = NmtkStepStatus.success;
        deployStatus = NmtkStepStatus.idle;
        monitorStatus = NmtkStepStatus.idle;
        verifyStatus = NmtkStepStatus.idle;
      case PynqDeployStep.deploying:
        prepareStatus = NmtkStepStatus.success;
        deployStatus = NmtkStepStatus.running;
        monitorStatus = NmtkStepStatus.idle;
        verifyStatus = NmtkStepStatus.idle;
      case PynqDeployStep.polling:
        prepareStatus = NmtkStepStatus.success;
        deployStatus = NmtkStepStatus.success;
        monitorStatus = NmtkStepStatus.running;
        verifyStatus = NmtkStepStatus.idle;
      case PynqDeployStep.verifying:
        prepareStatus = NmtkStepStatus.success;
        deployStatus = NmtkStepStatus.success;
        monitorStatus = NmtkStepStatus.success;
        verifyStatus = NmtkStepStatus.running;
      case PynqDeployStep.done:
        prepareStatus = NmtkStepStatus.success;
        deployStatus = NmtkStepStatus.success;
        monitorStatus = NmtkStepStatus.success;
        verifyStatus = provider.sitlResult != null
            ? NmtkStepStatus.success
            : NmtkStepStatus.idle;
      case PynqDeployStep.error:
        // Mark the step that failed; determine from what's populated.
        if (provider.exportResult == null) {
          prepareStatus = NmtkStepStatus.error;
          deployStatus = NmtkStepStatus.idle;
          monitorStatus = NmtkStepStatus.idle;
          verifyStatus = NmtkStepStatus.idle;
        } else if (provider.deployJob == null) {
          prepareStatus = NmtkStepStatus.success;
          deployStatus = NmtkStepStatus.error;
          monitorStatus = NmtkStepStatus.idle;
          verifyStatus = NmtkStepStatus.idle;
        } else if (provider.sitlResult == null) {
          prepareStatus = NmtkStepStatus.success;
          deployStatus = NmtkStepStatus.success;
          monitorStatus = NmtkStepStatus.error;
          verifyStatus = NmtkStepStatus.idle;
        } else {
          prepareStatus = NmtkStepStatus.success;
          deployStatus = NmtkStepStatus.success;
          monitorStatus = NmtkStepStatus.success;
          verifyStatus = NmtkStepStatus.error;
        }
    }

    return [
      NmtkPipelineStepData(
        label: 'Prepare',
        status: prepareStatus,
        detail: _prepareDetail(provider),
        icon: Icons.fact_check_outlined,
      ),
      NmtkPipelineStepData(
        label: 'Deploy',
        status: deployStatus,
        detail: step == PynqDeployStep.deploying ? 'uploading…' : null,
        icon: Icons.rocket_launch_outlined,
      ),
      NmtkPipelineStepData(
        label: 'Monitor',
        status: monitorStatus,
        detail: step == PynqDeployStep.polling ? 'polling…' : null,
        icon: Icons.monitor_heart_outlined,
      ),
      NmtkPipelineStepData(
        label: 'Verify',
        status: verifyStatus,
        detail: _verifyDetail(provider),
        icon: Icons.science_outlined,
      ),
    ];
  }

  String? _prepareDetail(PynqDeployProvider provider) {
    final result = provider.exportResult;
    if (result == null) return null;
    switch (result.supportState) {
      case PynqSupportState.exportable:
        return 'exportable';
      case PynqSupportState.exportableWithWarnings:
        return '${result.warnings.length} warning(s)';
      case PynqSupportState.notExportable:
        return 'not exportable';
      case PynqSupportState.deployable:
        return 'deployed';
      case PynqSupportState.notDeployable:
        return 'not deployable';
    }
  }

  String? _verifyDetail(PynqDeployProvider provider) {
    final result = provider.sitlResult;
    if (result == null) return null;
    return result.passed
        ? '${result.passedCases}/${result.totalCases} passed'
        : 'failed';
  }

  bool _canShowEndpointCard(PynqDeployProvider provider) {
    if (provider.exportResult == null) return false;
    final state = provider.exportResult!.supportState;
    return state == PynqSupportState.exportable ||
        state == PynqSupportState.exportableWithWarnings ||
        state == PynqSupportState.deployable;
  }

  // ---------- Step 1: CNL Input ----------

  Widget _buildCnlInputCard(
      BuildContext context, PynqDeployProvider provider) {
    final isChecking = provider.currentStep == PynqDeployStep.checking;

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
                    'Enter your NeuroCNL specification...\n'
                    'Example: The sensory neuron MUST fire ONLY IF '
                    'membrane potential exceeds 1.0.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Weight bit-width:'),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _weightBitWidth,
                  items: const [
                    DropdownMenuItem(value: 4, child: Text('4-bit (int4)')),
                    DropdownMenuItem(value: 8, child: Text('8-bit (int8)')),
                    DropdownMenuItem(value: 16, child: Text('16-bit (int16)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _weightBitWidth = v);
                  },
                ),
                const Spacer(),
                Flexible(
                  child: FilledButton.icon(
                    onPressed: isChecking || _specController.text.trim().isEmpty
                        ? null
                        : () => provider.checkExportability(
                              spec: _specController.text,
                              weightBitWidth: _weightBitWidth,
                            ),
                    icon: isChecking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.fact_check),
                    label: Text(
                      isChecking ? 'Checking...' : 'Check Exportability',
                    ),
                  ),
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
      BuildContext context, PynqDeployProvider provider) {
    final result = provider.exportResult!;
    return PynqSupportStateCard(
      supportState: result.supportState,
      warnings: result.warnings,
      rejections: result.rejectionReasons,
      networkSummary: result.networkSummary,
    );
  }

  // ---------- Step 3: Remote Endpoint Config ----------

  Widget _buildEndpointCard(
      BuildContext context, PynqDeployProvider provider) {
    final isDeploying = provider.currentStep == PynqDeployStep.deploying ||
        provider.currentStep == PynqDeployStep.polling;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Remote PYNQ Board',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _boardUrlController,
              decoration: const InputDecoration(
                labelText: 'Board endpoint URL',
                hintText: 'http://192.168.2.99:8002',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.developer_board),
              ),
              onChanged: provider.setBoardBaseUrl,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API key (optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
              ),
              obscureText: true,
              onChanged: provider.setBoardApiKey,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Switch(
                  value: provider.runSitl,
                  onChanged: provider.setRunSitl,
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text('Run SITL verification after deploy'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: isDeploying
                      ? null
                      : () => _startDeploy(provider),
                  icon: isDeploying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.rocket_launch),
                  label: Text(isDeploying ? 'Deploying...' : 'Deploy to Board'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _startDeploy(PynqDeployProvider provider) {
    final deployPayload = provider.exportResult?.deployPayload;
    if (deployPayload == null) {
      return;
    }

    provider.startDeploy(
      weights: deployPayload.weights,
      config: deployPayload.config,
      bitstreamPath: deployPayload.bitstreamPath,
      registerMap: deployPayload.registerMap,
    );
  }

  // ---------- Step 4: Deployment Status ----------

  Widget _buildDeployStatusCard(
      BuildContext context, PynqDeployProvider provider) {
    final job = provider.deployJob!;
    final isConfigured = job.status == PynqDeployJobStatus.configured;
    final isFailed = job.status == PynqDeployJobStatus.failed;
    final isPolling = provider.currentStep == PynqDeployStep.polling;

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
            LinearProgressIndicator(
              value: isConfigured
                  ? 1.0
                  : isFailed
                      ? 0.0
                      : isPolling
                          ? null // indeterminate while polling
                          : job.status.progressFraction,
              color: isFailed ? Colors.red : null,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  isConfigured
                      ? Icons.check_circle
                      : isFailed
                          ? Icons.error
                          : Icons.hourglass_top,
                  color: isConfigured
                      ? Colors.green
                      : isFailed
                          ? Colors.red
                          : Colors.blue,
                ),
                const SizedBox(width: 8),
                Text(
                  _deployJobLabel(job, isPolling),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isFailed ? Colors.red : null,
                  ),
                ),
              ],
            ),
            if (job.bitstreamPath != null) ...[
              const SizedBox(height: 4),
              Text(
                'Bitstream: ${job.bitstreamPath}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (!provider.runSitl &&
                isConfigured &&
                provider.currentStep == PynqDeployStep.done) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => provider.runVerification(),
                  icon: const Icon(Icons.science),
                  label: const Text('Run SITL Verification'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _deployJobLabel(PynqDeployJob job, bool isPolling) {
    if (isPolling && job.status == PynqDeployJobStatus.deploying) {
      return 'Loading overlay…';
    }
    switch (job.status) {
      case PynqDeployJobStatus.notInitialised:
        return 'Initialising…';
      case PynqDeployJobStatus.loaded:
        return 'Overlay loaded — writing weights…';
      case PynqDeployJobStatus.deploying:
        return 'Loading overlay…';
      case PynqDeployJobStatus.configured:
        return 'Overlay configured — board ready';
      case PynqDeployJobStatus.running:
        return 'Running';
      case PynqDeployJobStatus.failed:
        return 'Deploy failed';
    }
  }

  // ---------- Step 5: SITL Verification ----------

  Widget _buildSitlResultCard(
      BuildContext context, PynqDeployProvider provider) {
    final result = provider.sitlResult!;

    return Card(
      color: result.passed
          ? Colors.green.withValues(alpha: 0.08)
          : Colors.red.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.passed ? Icons.verified : Icons.error,
                  color: result.passed ? Colors.green : Colors.red,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  result.passed
                      ? 'SITL Verification Passed'
                      : 'SITL Verification Failed',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: result.passed ? Colors.green : Colors.red,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(result.summary),
            const SizedBox(height: 4),
            Text(
              '${result.passedCases}/${result.totalCases} cases passed · '
              'mean ${result.meanExecUs.toStringAsFixed(1)} µs · '
              'max ${result.maxExecUs.toStringAsFixed(1)} µs',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Error ----------

  Widget _buildErrorCard(
      BuildContext context, PynqDeployProvider provider) {
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
