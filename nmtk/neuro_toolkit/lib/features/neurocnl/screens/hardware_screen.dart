// ignore_for_file: unused_shown_name, depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart'
    show
        NmtkSection,
        NmtkSnackBars,
        NmtkTone,
        NmtkShellReadinessState,
        NmtkShellStatusBadge,
        NmtkShellStatusSpec,
        ZetaButton;
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/hardware_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/host_module_navigation.dart';
import 'package:neuro_toolkit/features/neurocnl/services/platform_helper.dart' as platform;
import 'package:neuro_toolkit/features/neurocnl/widgets/ownership_boundary_card.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/sensor_time_series_chart.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/serial_port_selector.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/shell_surface.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

class HardwareScreen extends ConsumerStatefulWidget {
  const HardwareScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<HardwareScreen> createState() => _HardwareScreenState();
}

class _HardwareScreenState extends ConsumerState<HardwareScreen> {
  String? _selectedPort;
  int _baudRate = 115200;

  static const _baudRates = [9600, 115200, 230400];

  @override
  void initState() {
    super.initState();
    // Fetch ports on first load.
    Future.microtask(() => ref.read(hardwareProvider.notifier).refreshPorts());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hardwareProvider);
    final selectedTarget = ref.watch(
      workspaceProvider.select((workspace) => workspace.selectedDeployTarget),
    );
    final neurochipTarget = StudioNeurochipHandoffContract.fromStudioTargetId(
      selectedTarget,
    );

    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHandoffPanel(neurochipTarget),
        const SizedBox(height: 16),
        _buildOwnershipPanel(),
        const SizedBox(height: 16),
        _buildConnectionPanel(state),
        const SizedBox(height: 16),
        _buildSensorPanel(state),
      ],
    );

    if (widget.embedded) {
      return content;
    }

    return Column(
      children: [
        const NeurocnlScreenHeader(
          eyebrow: 'Instrumentation',
          title: 'Hardware',
          subtitle:
              'Review serial connectivity and live telemetry as a subordinate Studio workspace.',
        ),
        Expanded(child: content),
      ],
    );
  }

  Widget _buildHandoffPanel(StudioNeurochipHandoffContract neurochipTarget) {
    return _buildCardSection(
      title: 'Continue in Owner Modules',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Use this Studio surface for short local preview checks only. Live telemetry, recording, and execution work continue in NeuroSense or Neurochip.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ZetaButton(
                onPressed: _openNeurosenseMonitor,
                leadingIcon: Icons
                    .monitor_heart_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                label: 'Open NeuroSense Monitor',
              ),
              ZetaButton.outline(
                onPressed: () => _openNeurochipExecution(neurochipTarget),
                leadingIcon: ZetaIcons.memory,
                label: 'Open ${neurochipTarget.targetLabel} in Neurochip',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOwnershipPanel() {
    return const NeurocnlOwnershipBoundaryCard(
      summary:
          'Use Hardware for local authoring-stage serial checks while shaping a workflow in Studio.',
      details: [
        'Live biosignal acquisition, reusable EMG telemetry, and recording ownership belong to NeuroSense.',
        'Execution-specific flashing and target runtime diagnostics belong to Neurochip after handoff.',
      ],
    );
  }

  Widget _buildCardSection({required String title, required Widget child}) {
    // zeta-card-reduction Task 10: NeurocnlSectionCard → NmtkSection.
    // The legacy `tone` parameter is dropped — NmtkSection is frame-less
    // and does not carry tone styling. The single info-toned call site
    // ("Continue in Owner Modules" handoff panel) communicated semantics
    // via tone alone; the section title + button content remain
    // self-explanatory without it.
    return NmtkSection(title: title, child: child);
  }

  Widget _statusBadge(HardwareState state) {
    final status = NmtkShellStatusSpec.fromReadinessState(
      state.isConnected
          ? NmtkShellReadinessState.ready
          : NmtkShellReadinessState.degraded,
      detailText: state.isConnected
          ? 'Connected to ${state.connectedPort}'
          : 'Disconnected',
    );
    return NmtkShellStatusBadge(status: status);
  }

  Widget _errorText(String message) {
    return Text(
      message,
      style: Zeta.of(context).textStyles.bodyMedium.copyWith(
        color: Zeta.of(context).colors.mainNegative,
      ),
    );
  }

  // ── Section 1: Connection ──────────────────────────────────────────

  Widget _buildConnectionPanel(HardwareState state) {
    return _buildCardSection(
      title: 'Local Serial Check',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SerialPortSelector(
            availablePorts: state.availablePorts,
            selectedPort: _selectedPort,
            isRefreshing: state.isRefreshing,
            onPortChanged: (port) => setState(() => _selectedPort = port),
            onRefresh: () => ref.read(hardwareProvider.notifier).refreshPorts(),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Baud Rate',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _baudRate,
                isExpanded: true,
                isDense: true,
                items: _baudRates
                    .map(
                      (rate) => DropdownMenuItem(
                        value: rate,
                        child: Text(rate.toString()),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _baudRate = val);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildConnectButton(state)),
              const SizedBox(width: 16),
              _statusBadge(state),
            ],
          ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: 8),
            _errorText(state.errorMessage!),
          ],
        ],
      ),
    );
  }

  Widget _buildConnectButton(HardwareState state) {
    if (state.isConnected) {
      return ZetaButton.negative(
        onPressed: () => ref.read(hardwareProvider.notifier).disconnect(),
        leadingIcon: ZetaIcons.link,
        label: 'Disconnect',
      );
    }
    return ZetaButton.positive(
      onPressed: _selectedPort == null
          ? null
          : () => ref
                .read(hardwareProvider.notifier)
                .connect(_selectedPort!, _baudRate),
      leadingIcon: ZetaIcons.link,
      label: 'Connect',
    );
  }

  // ── Section 2: Live Sensor Data ────────────────────────────────────

  Widget _buildSensorPanel(HardwareState state) {
    return _buildCardSection(
      title: 'Telemetry Preview',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!state.isConnected)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Connect to a device to preview local telemetry before handing off to NeuroSense or Neurochip',
                ),
              ),
            )
          else if (state.sensorData.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Waiting for telemetry preview data…'),
              ),
            )
          else ...[
            SensorTimeSeriesChart(frames: state.sensorData),
            const Divider(),
            _buildLatestFrame(state),
          ],
        ],
      ),
    );
  }

  Widget _buildLatestFrame(HardwareState state) {
    final frame = state.sensorData.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Timestamp: ${frame.timestamp.toStringAsFixed(3)} s',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        for (int i = 0; i < frame.emgChannels.length; i++)
          Text('EMG ${i + 1}: ${frame.emgChannels[i].toStringAsFixed(4)}'),
        if (frame.eegBands != null)
          for (final entry in frame.eegBands!.entries)
            Text('EEG ${entry.key}: ${entry.value.toStringAsFixed(4)}'),
        if (frame.proximity != null)
          Text('Proximity: ${frame.proximity!.toStringAsFixed(2)}'),
      ],
    );
  }

  Future<void> _openNeurosenseMonitor() async {
    final deepLink = Uri(
      scheme: 'https',
      host: 'neurosense.local',
      path: '/monitor',
      queryParameters: const <String, String>{'streamType': 'filtered'},
    ).toString();

    bool opened;
    if (hasHostedModuleNavigator(context)) {
      opened = await openModuleInHost(
        context,
        moduleId: 'NeuroSense',
        deepLink: deepLink,
      );
    } else {
      opened = await platform.openUrl(deepLink);
    }

    if (!mounted || opened) {
      return;
    }
    _showMessage(
      'Could not open NeuroSense automatically from this workspace.',
      isError: true,
    );
  }

  Future<void> _openNeurochipExecution(
    StudioNeurochipHandoffContract target,
  ) async {
    final deepLink = Uri(
      scheme: 'https',
      host: 'neurochip.local',
      path: '/${target.destinationWorkspace}',
      queryParameters: <String, String>{
        'selectedTargetId': target.neurochipTargetId,
      },
    ).toString();

    bool opened;
    if (hasHostedModuleNavigator(context)) {
      opened = await openModuleInHost(
        context,
        moduleId: 'Neurochip',
        deepLink: deepLink,
      );
    } else {
      opened = await platform.openUrl(deepLink);
    }

    if (!mounted || opened) {
      return;
    }
    _showMessage(
      'Could not open Neurochip automatically from this workspace.',
      isError: true,
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    if (isError) {
      NmtkSnackBars.error(context, message);
    } else {
      NmtkSnackBars.success(context, message);
    }
  }
}
