import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/providers/teensy_deploy_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// Teensy deployment screen with a stepper UI.
///
/// Workflow: CNL Input → Verdict → Firmware Export → Serial Port → Flash → Verify
class TeensyDeployScreen extends ConsumerStatefulWidget {
  const TeensyDeployScreen({super.key});

  @override
  ConsumerState<TeensyDeployScreen> createState() => _TeensyDeployScreenState();
}

class _TeensyDeployScreenState extends ConsumerState<TeensyDeployScreen> {
  final _specController = TextEditingController();
  int _weightBitWidth = 8;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(teensyDeployStateProvider).refreshPorts();
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
        title: const Text('Teensy 4.1 Deploy'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset',
            onPressed: () => ref.read(teensyDeployStateProvider).reset(),
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          final provider = ref.watch(teensyDeployStateProvider);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCnlInputCard(context, provider),
                const SizedBox(height: 16),
                if (provider.deployResult != null)
                  _buildVerdictCard(context, provider),
                if (provider.firmwareBytes != null) ...[
                  const SizedBox(height: 16),
                  _buildFirmwareCard(context, provider),
                ],
                if (provider.currentStep.index >=
                    TeensyDeployStep.selectingPort.index) ...[
                  const SizedBox(height: 16),
                  _buildSerialPortCard(context, provider),
                ],
                if (provider.flashJob != null) ...[
                  const SizedBox(height: 16),
                  _buildFlashProgressCard(context, provider),
                ],
                if (provider.verificationReport != null) ...[
                  const SizedBox(height: 16),
                  _buildVerificationCard(context, provider),
                ],
                if (provider.errorMessage != null &&
                    provider.currentStep == TeensyDeployStep.error) ...[
                  const SizedBox(height: 16),
                  _buildErrorCard(context, provider),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------- Step 1: CNL Input ----------

  Widget _buildCnlInputCard(
      BuildContext context, TeensyDeployProvider provider) {
    final isDeploying = provider.currentStep == TeensyDeployStep.deploying;

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
                hintText: 'Enter your NeuroCNL specification...\n'
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
                    DropdownMenuItem(value: 8, child: Text('8-bit')),
                    DropdownMenuItem(value: 16, child: Text('16-bit')),
                    DropdownMenuItem(value: 32, child: Text('32-bit')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _weightBitWidth = v);
                  },
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: isDeploying || _specController.text.trim().isEmpty
                      ? null
                      : () => provider.deployAndExport(
                            spec: _specController.text,
                            weightBitWidth: _weightBitWidth,
                          ),
                  icon: isDeploying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.rocket_launch),
                  label: Text(isDeploying ? 'Deploying...' : 'Deploy'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Step 2: Verdict ----------

  Widget _buildVerdictCard(
      BuildContext context, TeensyDeployProvider provider) {
    final result = provider.deployResult!;
    final Color colour;
    final IconData icon;
    final String label;

    switch (result.verdict) {
      case TeensyDeploymentVerdict.faithful:
        colour = Colors.green;
        icon = Icons.check_circle;
        label = 'Faithful — fully deployable';
      case TeensyDeploymentVerdict.approximate:
        colour = Colors.orange;
        icon = Icons.warning_amber;
        label = 'Approximate — deployable with warnings';
      case TeensyDeploymentVerdict.notDeployable:
        colour = Colors.red;
        icon = Icons.cancel;
        label = 'Not Deployable';
    }

    return Card(
      color: colour.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colour, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: colour),
                  ),
                ),
              ],
            ),
            if (result.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...result.warnings.map(
                (w) => Padding(
                  padding: const EdgeInsets.only(left: 36, bottom: 4),
                  child: Text('⚠ $w',
                      style: const TextStyle(color: Colors.orange)),
                ),
              ),
            ],
            if (result.rejectionReasons.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...result.rejectionReasons.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(left: 36, bottom: 4),
                  child:
                      Text('✗ $r', style: const TextStyle(color: Colors.red)),
                ),
              ),
            ],
            if (result.payload != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 36),
                child: Text(
                  '${result.payload!["num_neurons"]} neurons · '
                  '${result.payload!["num_synapses"]} synapses · '
                  '${result.payload!["neuron_model"]} · '
                  'depth ${result.payload!["network_depth"]}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------- Step 3: Firmware ----------

  Widget _buildFirmwareCard(
      BuildContext context, TeensyDeployProvider provider) {
    final sizeKb = (provider.firmwareBytes!.length / 1024).toStringAsFixed(1);

    return Card(
      child: ListTile(
        leading: const Icon(Icons.archive, color: Colors.blue),
        title: const Text('Firmware Ready'),
        subtitle: Text('neurochip_firmware.zip — $sizeKb KB'),
        trailing: const Icon(Icons.check_circle, color: Colors.green),
      ),
    );
  }

  // ---------- Step 4: Serial Port ----------

  Widget _buildSerialPortCard(
      BuildContext context, TeensyDeployProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Serial Port',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh ports',
                  onPressed: () => provider.refreshPorts(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (provider.serialPorts.isEmpty)
              const Text(
                'No serial ports detected. Connect your Teensy 4.1 and refresh.',
                style: TextStyle(color: Colors.grey),
              )
            else
              RadioGroup<String>(
                groupValue: provider.selectedPort?.device,
                onChanged: (value) {
                  if (value == null) return;
                  final port = provider.serialPorts.firstWhere(
                    (serialPort) => serialPort.device == value,
                  );
                  provider.selectPort(port);
                },
                child: Column(
                  children: provider.serialPorts
                      .map(
                        (port) => RadioListTile<String>(
                          title: Text(port.device),
                          subtitle: Text(port.description ?? ''),
                          secondary: port.isTeensy
                              ? const Chip(label: Text('Teensy'))
                              : null,
                          value: port.device,
                        ),
                      )
                      .toList(),
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: provider.selectedPort == null ||
                        provider.currentStep == TeensyDeployStep.flashing
                    ? null
                    : () => provider.startFlash(),
                icon: const Icon(Icons.flash_on),
                label: const Text('Flash Firmware'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Step 5: Flash Progress ----------

  Widget _buildFlashProgressCard(
      BuildContext context, TeensyDeployProvider provider) {
    final job = provider.flashJob!;
    final isDone = job.status == FlashJobStatus.done;
    final isFailed = job.status == FlashJobStatus.failed;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Flash Progress',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: isDone
                  ? 1.0
                  : isFailed
                      ? 0.0
                      : job.status.progressFraction,
              color: isFailed ? Colors.red : null,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  isDone
                      ? Icons.check_circle
                      : isFailed
                          ? Icons.error
                          : Icons.hourglass_top,
                  color: isDone
                      ? Colors.green
                      : isFailed
                          ? Colors.red
                          : Colors.blue,
                ),
                const SizedBox(width: 8),
                Text(
                  job.message ?? job.status.name.toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isFailed ? Colors.red : null,
                  ),
                ),
              ],
            ),
            if (job.error != null) ...[
              const SizedBox(height: 4),
              Text(job.error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }

  // ---------- Step 6: Verification ----------

  Widget _buildVerificationCard(
      BuildContext context, TeensyDeployProvider provider) {
    final report = provider.verificationReport!;

    return Card(
      color: report.passed
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
                  report.passed ? Icons.verified : Icons.error,
                  color: report.passed ? Colors.green : Colors.red,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  report.passed ? 'Verification Passed' : 'Verification Failed',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: report.passed ? Colors.green : Colors.red,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(report.summary),
            if (report.smoke.latencyMs != null) ...[
              const SizedBox(height: 4),
              Text(
                'Smoke check latency: ${report.smoke.latencyMs!.toStringAsFixed(1)} ms',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (report.demo != null) ...[
              const SizedBox(height: 4),
              Text(
                'Demo: ${report.demo!.framesReceived}/5 frames received',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------- Error ----------

  Widget _buildErrorCard(BuildContext context, TeensyDeployProvider provider) {
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
