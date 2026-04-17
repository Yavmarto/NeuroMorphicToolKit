import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/pynq_deploy_provider.dart';
import 'package:provider/provider.dart';

class PynqDeployScreen extends StatefulWidget {
  const PynqDeployScreen({super.key});

  @override
  State<PynqDeployScreen> createState() => _PynqDeployScreenState();
}

class _PynqDeployScreenState extends State<PynqDeployScreen> {
  final _specController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _hostController = TextEditingController();
  final _usernameController = TextEditingController(text: 'xilinx');
  final _sshPortController = TextEditingController(text: '22');
  final _credentialRefController = TextEditingController();
  final _passwordController = TextEditingController();
  final _sshKeyPathController = TextEditingController();
  final _runtimeApiUrlOverrideController = TextEditingController();
  final _overlayVersionController = TextEditingController();
  final _bitstreamPathController = TextEditingController();

  int _weightBitWidth = 4;
  PynqBoardAuthMode _authMode = PynqBoardAuthMode.password;
  String? _formBoardId;

  @override
  void dispose() {
    _specController.dispose();
    _displayNameController.dispose();
    _hostController.dispose();
    _usernameController.dispose();
    _sshPortController.dispose();
    _credentialRefController.dispose();
    _passwordController.dispose();
    _sshKeyPathController.dispose();
    _runtimeApiUrlOverrideController.dispose();
    _overlayVersionController.dispose();
    _bitstreamPathController.dispose();
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
            tooltip: 'Reset workflow',
            onPressed: () => context.read<PynqDeployProvider>().reset(),
          ),
        ],
      ),
      body: Consumer<PynqDeployProvider>(
        builder: (context, provider, child) {
          _syncControllers(provider);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NmtkPipelineStepper(steps: _buildPipelineSteps(provider)),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCnlInputCard(context, provider),
                      const SizedBox(height: 16),
                      _buildBoardCard(context, provider),
                      if (provider.exportResult != null) ...[
                        const SizedBox(height: 16),
                        _buildVerdictCard(context, provider),
                      ],
                      if (provider.deployPayload != null) ...[
                        const SizedBox(height: 16),
                        _buildDeployPackageCard(context, provider),
                      ],
                      if (provider.deployPayload != null) ...[
                        const SizedBox(height: 16),
                        _buildDeployActionCard(context, provider),
                      ],
                      if (provider.deployJob != null) ...[
                        const SizedBox(height: 16),
                        _buildDeployStatusCard(context, provider),
                      ],
                      if (provider.sitlResult != null) ...[
                        const SizedBox(height: 16),
                        _buildSitlResultCard(context, provider),
                      ],
                      if (provider.errorMessage != null) ...[
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

  void _syncControllers(PynqDeployProvider provider) {
    final selectedBoard = provider.selectedBoard;
    if (_formBoardId != selectedBoard?.id && selectedBoard != null) {
      _formBoardId = selectedBoard.id;
      _displayNameController.text = selectedBoard.displayName;
      _hostController.text = selectedBoard.host;
      _usernameController.text = selectedBoard.username;
      _sshPortController.text = selectedBoard.sshPort.toString();
      _credentialRefController.text = selectedBoard.credentialRef;
      _passwordController.clear();
      _sshKeyPathController.text = selectedBoard.sshKeyPath;
      _runtimeApiUrlOverrideController.text =
          selectedBoard.runtimeApiUrlOverride;
      _overlayVersionController.text = selectedBoard.overlayVersion;
      _authMode = selectedBoard.authMode;
    } else if (selectedBoard == null && _formBoardId != null) {
      _formBoardId = null;
      _runtimeApiUrlOverrideController.clear();
    }

    if (_bitstreamPathController.text != provider.bitstreamPathOverride) {
      _bitstreamPathController.value = TextEditingValue(
        text: provider.bitstreamPathOverride,
        selection: TextSelection.collapsed(
          offset: provider.bitstreamPathOverride.length,
        ),
      );
    }
  }

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
        prepareStatus = provider.exportResult == null
            ? NmtkStepStatus.error
            : NmtkStepStatus.success;
        deployStatus =
            provider.exportResult != null && provider.deployJob == null
                ? NmtkStepStatus.error
                : provider.deployJob != null
                    ? NmtkStepStatus.success
                    : NmtkStepStatus.idle;
        monitorStatus = provider.deployJob != null
            ? NmtkStepStatus.error
            : NmtkStepStatus.idle;
        verifyStatus = provider.sitlResult != null
            ? NmtkStepStatus.error
            : NmtkStepStatus.idle;
    }

    return [
      NmtkPipelineStepData(
        label: 'Prepare',
        status: prepareStatus,
        detail: provider.exportResult?.supportState.label,
        icon: Icons.fact_check_outlined,
      ),
      NmtkPipelineStepData(
        label: 'Deploy',
        status: deployStatus,
        detail: provider.selectedBoard?.state.label,
        icon: Icons.rocket_launch_outlined,
      ),
      NmtkPipelineStepData(
        label: 'Monitor',
        status: monitorStatus,
        detail: provider.deployJob?.status.name,
        icon: Icons.monitor_heart_outlined,
      ),
      NmtkPipelineStepData(
        label: 'Verify',
        status: verifyStatus,
        detail: provider.sitlResult == null
            ? null
            : '${provider.sitlResult!.passedCases}/${provider.sitlResult!.totalCases} passed',
        icon: Icons.science_outlined,
      ),
    ];
  }

  Widget _buildCnlInputCard(BuildContext context, PynqDeployProvider provider) {
    final isChecking = provider.currentStep == PynqDeployStep.checking;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CNL Specification',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _specController,
              maxLines: 8,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter your NeuroCNL specification...',
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
                    DropdownMenuItem(value: 4, child: Text('4-bit')),
                    DropdownMenuItem(value: 8, child: Text('8-bit')),
                    DropdownMenuItem(value: 16, child: Text('16-bit')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _weightBitWidth = value);
                    }
                  },
                ),
                const Spacer(),
                FilledButton.icon(
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
                  label:
                      Text(isChecking ? 'Checking...' : 'Check Exportability'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoardCard(BuildContext context, PynqDeployProvider provider) {
    final selectedBoard = provider.selectedBoard;
    final boardActionInProgress = provider.boardOperationInProgress;
    final activeBoardOperation = provider.activeBoardOperation;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paired Board',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'The launcher owns pairing, provisioning, readiness, and board deploy orchestration.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: provider.selectedBoardId,
              hint: const Text('Create new board...'),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Remembered board',
              ),
              items: provider.pairedBoards
                  .map(
                    (board) => DropdownMenuItem<String>(
                      value: board.id,
                      child:
                          Text('${board.displayName} • ${board.state.label}'),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                provider.selectBoard(value);
                if (value == null) {
                  _displayNameController.clear();
                  _hostController.clear();
                  _credentialRefController.clear();
                  _passwordController.clear();
                  _sshKeyPathController.clear();
                  _runtimeApiUrlOverrideController.clear();
                  _overlayVersionController.clear();
                  setState(() => _authMode = PynqBoardAuthMode.password);
                }
              },
            ),
            const SizedBox(height: 12),
            if (provider.boardFeedbackMessage != null) ...[
              Card(
                color: Colors.blue.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      boardActionInProgress
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.info_outline, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          provider.boardFeedbackMessage!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _displayNameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Display name',
                    ),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _hostController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Board host or IP',
                    ),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'SSH username',
                    ),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _sshPortController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'SSH port',
                    ),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<PynqBoardAuthMode>(
                    value: _authMode,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Auth mode',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: PynqBoardAuthMode.password,
                        child: Text('Password'),
                      ),
                      DropdownMenuItem(
                        value: PynqBoardAuthMode.sshKey,
                        child: Text('SSH key'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _authMode = value);
                      }
                    },
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _credentialRefController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Runtime API key (optional)',
                    ),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _overlayVersionController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Overlay version (optional)',
                    ),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _runtimeApiUrlOverrideController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Runtime API URL override (optional)',
                      helperText: 'Leave blank to use http://<host>:8002',
                    ),
                  ),
                ),
                if (_authMode == PynqBoardAuthMode.password)
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: selectedBoard?.hasPassword == true
                            ? 'SSH password (leave blank to keep stored value)'
                            : 'SSH password',
                      ),
                    ),
                  )
                else
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _sshKeyPathController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'SSH key path',
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
                  onPressed: boardActionInProgress
                      ? null
                      : () => provider.savePairedBoard(
                            boardId: provider.selectedBoardId,
                            displayName:
                                _displayNameController.text.trim().isEmpty
                                    ? _hostController.text.trim()
                                    : _displayNameController.text.trim(),
                            host: _hostController.text.trim(),
                            sshPort:
                                int.tryParse(_sshPortController.text.trim()) ??
                                    22,
                            username: _usernameController.text.trim().isEmpty
                                ? 'xilinx'
                                : _usernameController.text.trim(),
                            authMode: _authMode,
                            credentialRef: _credentialRefController.text.trim(),
                            password: _passwordController.text,
                            sshKeyPath: _sshKeyPathController.text.trim(),
                            runtimeApiUrlOverride:
                                _runtimeApiUrlOverrideController.text.trim(),
                            overlayVersion:
                                _overlayVersionController.text.trim(),
                          ),
                  icon: activeBoardOperation == PynqBoardOperation.savingPairing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link),
                  label: Text(
                      activeBoardOperation == PynqBoardOperation.savingPairing
                          ? 'Saving...'
                          : provider.selectedBoard == null
                              ? 'Pair Board'
                              : 'Save Pairing'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      provider.selectedBoard == null || boardActionInProgress
                          ? null
                          : () => provider.testSelectedBoardConnectivity(),
                  icon: activeBoardOperation == PynqBoardOperation.testingSsh
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check),
                  label: Text(
                    activeBoardOperation == PynqBoardOperation.testingSsh
                        ? 'Testing SSH...'
                        : 'Test SSH',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      provider.selectedBoard == null || boardActionInProgress
                          ? null
                          : () => provider.provisionSelectedBoard(),
                  icon: activeBoardOperation ==
                          PynqBoardOperation.provisioningRuntime
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.system_update_alt),
                  label: Text(
                    activeBoardOperation ==
                            PynqBoardOperation.provisioningRuntime
                        ? 'Provisioning...'
                        : 'Provision Runtime',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      provider.selectedBoard == null || boardActionInProgress
                          ? null
                          : () => provider.installOverlayForSelectedBoard(),
                  icon: activeBoardOperation ==
                          PynqBoardOperation.installingOverlay
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.memory_outlined),
                  label: Text(
                    activeBoardOperation == PynqBoardOperation.installingOverlay
                        ? 'Installing...'
                        : 'Install Overlay',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      provider.selectedBoard == null || boardActionInProgress
                          ? null
                          : () => provider.refreshSelectedBoardPreflight(),
                  icon: activeBoardOperation ==
                          PynqBoardOperation.checkingReadiness
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.health_and_safety_outlined),
                  label: Text(
                    activeBoardOperation == PynqBoardOperation.checkingReadiness
                        ? 'Checking...'
                        : 'Check Readiness',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      provider.selectedBoard == null || boardActionInProgress
                          ? null
                          : () => provider.restartSelectedBoardRuntime(),
                  icon: activeBoardOperation ==
                          PynqBoardOperation.restartingRuntime
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.restart_alt),
                  label: Text(
                    activeBoardOperation == PynqBoardOperation.restartingRuntime
                        ? 'Restarting...'
                        : 'Restart Runtime',
                  ),
                ),
                TextButton.icon(
                  onPressed: boardActionInProgress
                      ? null
                      : () {
                          provider.selectBoard(null);
                          _displayNameController.clear();
                          _hostController.clear();
                          _credentialRefController.clear();
                          _passwordController.clear();
                          _sshKeyPathController.clear();
                          _runtimeApiUrlOverrideController.clear();
                          _overlayVersionController.clear();
                          setState(
                              () => _authMode = PynqBoardAuthMode.password);
                        },
                  icon: const Icon(Icons.add_link_outlined),
                  label: const Text('New Pairing'),
                ),
                TextButton.icon(
                  onPressed:
                      provider.selectedBoard == null || boardActionInProgress
                          ? null
                          : () => provider.deleteSelectedBoard(),
                  icon:
                      activeBoardOperation == PynqBoardOperation.deletingPairing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_outline),
                  label: Text(
                    activeBoardOperation == PynqBoardOperation.deletingPairing
                        ? 'Deleting...'
                        : 'Delete',
                  ),
                ),
              ],
            ),
            if (selectedBoard != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text('State: ${selectedBoard.state.label}')),
                  Chip(label: Text('Runtime: ${selectedBoard.runtimeApiUrl}')),
                  if (selectedBoard.lastPreflightStatus.isNotEmpty)
                    Chip(
                        label: Text(
                            'Preflight: ${selectedBoard.lastPreflightStatus}')),
                ],
              ),
              if (selectedBoard.lastPreflightMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  selectedBoard.lastPreflightMessage,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVerdictCard(BuildContext context, PynqDeployProvider provider) {
    final result = provider.exportResult!;
    return PynqSupportStateCard(
      supportState: result.supportState,
      warnings: result.warnings,
      rejections: result.rejectionReasons,
      networkSummary: result.networkSummary,
    );
  }

  Widget _buildDeployPackageCard(
      BuildContext context, PynqDeployProvider provider) {
    final payload = provider.deployPayload!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Deployment Package',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _buildPackageChip(
                  context,
                  icon: Icons.scale,
                  label: '${payload.config.bitWidth}-bit quantisation',
                ),
                _buildPackageChip(
                  context,
                  icon: Icons.account_tree_outlined,
                  label: '${payload.weightCount} packed weights',
                ),
                _buildPackageChip(
                  context,
                  icon: Icons.memory_outlined,
                  label: payload.registerMap.dmaChannel,
                ),
                _buildPackageChip(
                  context,
                  icon: Icons.timer_outlined,
                  label: '${payload.registerMap.timestepUs} µs timestep',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Validated bitstream path: ${payload.bitstreamPath}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackageChip(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }

  Widget _buildDeployActionCard(
      BuildContext context, PynqDeployProvider provider) {
    final selectedBoard = provider.selectedBoard;
    final isDeploying = provider.currentStep == PynqDeployStep.deploying ||
        provider.currentStep == PynqDeployStep.polling;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Deploy And Verify',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              selectedBoard == null
                  ? 'Pair and provision a board before deploy.'
                  : 'Deploy will route through launcher-control to ${selectedBoard.displayName}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bitstreamPathController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Bitstream path override (optional)',
              ),
              onChanged: provider.setBitstreamPathOverride,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Switch(
                  value: provider.runSitl,
                  onChanged: provider.setRunSitl,
                ),
                const SizedBox(width: 8),
                const Expanded(
                    child: Text('Run SITL verification after deploy')),
                FilledButton.icon(
                  onPressed: isDeploying || selectedBoard == null
                      ? null
                      : () => provider.startDeploy(),
                  icon: isDeploying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.rocket_launch),
                  label: Text(isDeploying ? 'Deploying...' : 'Deploy To Board'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeployStatusCard(
      BuildContext context, PynqDeployProvider provider) {
    final job = provider.deployJob!;
    final isConfigured = job.status == PynqDeployJobStatus.configured;
    final isFailed = job.status == PynqDeployJobStatus.failed;
    final isPolling = provider.currentStep == PynqDeployStep.polling;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Deployment Status',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: isConfigured
                  ? 1.0
                  : isFailed
                      ? 0.0
                      : isPolling
                          ? null
                          : job.status.progressFraction,
              color: isFailed ? Colors.red : null,
            ),
            const SizedBox(height: 8),
            Text(
              job.status.name,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (job.bitstreamPath != null) ...[
              const SizedBox(height: 4),
              Text('Bitstream: ${job.bitstreamPath}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSitlResultCard(
      BuildContext context, PynqDeployProvider provider) {
    final result = provider.sitlResult!;
    return Card(
      color: result.passed
          ? Colors.green.withValues(alpha: 0.08)
          : Colors.red.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.passed
                  ? 'SITL Verification Passed'
                  : 'SITL Verification Failed',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: result.passed ? Colors.green : Colors.red,
                  ),
            ),
            const SizedBox(height: 8),
            Text(result.summary),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, PynqDeployProvider provider) {
    return Card(
      color: Colors.red.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
          ],
        ),
      ),
    );
  }
}
