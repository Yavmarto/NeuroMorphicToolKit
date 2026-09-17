import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_config.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/models/sc_neurocore_synthesis_target.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_pipeline_steps.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_result_session.dart';
import 'package:neuro_toolkit/features/neurocnl/models/template.dart';
import 'package:neuro_toolkit/features/neurocnl/models/workspace_file.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/workflow/snn_workflow_stepper.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canonical_doc_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/simulation_provider.dart'
    as canvas_sim;
import 'package:neuro_toolkit/features/neurocnl/providers/nir_import_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/simulator_preflight_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/step_unlock_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_result_session_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_view_mode_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/template_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/hardware_auto_add_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/deploy_error_formatter.dart';
import 'package:neuro_toolkit/features/neurocnl/services/host_module_navigation.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurohub_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurosim_handoff.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurosim_handoff_coordinator.dart';
import 'package:neuro_toolkit/features/neurocnl/services/platform_helper.dart'
    as platform;
import 'package:neuro_toolkit/features/neurocnl/services/sc_neurocore_target_service.dart';
import 'package:neuro_toolkit/features/neurocnl/services/template_load_guard.dart';
import 'package:neuro_toolkit/features/neurocnl/services/workspace_payload_builder.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/neurohub_workspace_save.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/workspace_feature.dart'
    show
        WorkspaceTabViewData,
        WorkspaceFileIoController,
        StudioWorkspaceFileIoHost,
        restoreCanvasSectionFromPayload,
        restoreResultSessionFromPayload;
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/presentation/workspace_open_overlay.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/setup_step/setup_step.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/studio_screen_shell/studio_deploy_panel_host.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/studio_screen_shell/studio_desktop_shell.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/studio_screen_shell/studio_keyboard_shortcut_scope.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/studio_screen_shell/studio_layout_metrics.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/studio_screen_shell/studio_mobile_shell.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_assistant_host.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/studio_screen_shell/studio_pipeline_step_content.dart';

class StudioScreen extends ConsumerStatefulWidget {
  const StudioScreen({
    super.key,
    this.initialTemplateId,
    this.workspaceHeaderAction,
    this.onEditServer,
  });

  final String? initialTemplateId;

  /// Optional launcher-owned action displayed beside the workspace name in
  /// the desktop Studio toolbar.
  final Widget? workspaceHeaderAction;

  /// Launcher-owned action that opens the suite server connection popup.
  final Future<void> Function()? onEditServer;

  @override
  ConsumerState<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends ConsumerState<StudioScreen>
    implements StudioWorkspaceFileIoHost {
  late final WorkspaceFileIoController _fileIo = WorkspaceFileIoController(
    this,
  );
  final double _simulationDuration = 1.0;
  final GlobalKey<SetupStepState> _setupStepKey = GlobalKey<SetupStepState>();
  StudioResultView _runResultView = StudioResultView.architecture;
  bool _didHydrateInitialSpec = false;
  bool _isOpeningWorkspace = false;
  // A model-sync failure can arrive while the cold-start recovery dialog is
  // visible. The recovery decision must remain actionable in that state.
  bool _modelSyncNotificationsReady = false;
  String? _lastRouteSyncKey;
  String? _splitPipelineStep;
  final Map<String, String> _selectedHardwareDeviceIds = <String, String>{};
  final Map<String, String> _selectedHardwareDeviceLabels = <String, String>{};
  final Map<String, Object> _selectedHardwareDeviceData = <String, Object>{};
  final Map<String, String> _lastDeployValidationKeys = <String, String>{};

  // listenManual subscription — provider side-effect listener that must not
  // fire during build. Registered in initState, closed in dispose.
  //
  // CNL/Canvas/NIR no longer need reconciling listeners here: canonicalDocProvider
  // is the only writer of spec content, and canvas_provider.dart /
  // spec_provider.dart derive from it directly, so every view updates
  // reactively the moment the canonical doc changes — no manual relay.
  late final ProviderSubscription<WorkspaceState> _workspaceListenerSub;

  // Canvas/simulation/training listeners driving the debounced autosave in
  // `_fileIo.scheduleCanvasAutosave` (workspace_file_io_controller.dart) — the "eval grid"
  // (Train/Eval pipeline) otherwise never gets written to local storage and
  // comes back empty after a hot restart. Registered in initState, closed
  // in dispose, alongside the Timer they debounce into.
  late final ProviderSubscription<(CanvasGraph, PipelinePhases, PipelineConfig)>
  _canvasAutosaveListenerSub;
  late final ProviderSubscription<canvas_sim.SimulationState>
  _simulationAutosaveListenerSub;
  late final ProviderSubscription<StudioResultSessionState>
  _resultSessionAutosaveListenerSub;
  Timer? _canvasAutosaveTimer;

  @override
  Timer? get canvasAutosaveTimer => _canvasAutosaveTimer;
  @override
  set canvasAutosaveTimer(Timer? value) => _canvasAutosaveTimer = value;

  @override
  bool get isOpeningWorkspace => _isOpeningWorkspace;
  @override
  set isOpeningWorkspace(bool value) => _isOpeningWorkspace = value;

  /// Lets [WorkspaceFileIoController] trigger a rebuild without calling the
  /// `@protected` `State.setState` from outside this class's body — the
  /// controller is an external caller even though it only ever acts on this
  /// exact instance, so `setState` itself must stay confined to instance
  /// methods declared directly on this class.
  @override
  void rebuild(VoidCallback fn) => setState(fn);

  void _setRunResultView(StudioResultView view) {
    if (_runResultView == view) return;
    setState(() => _runResultView = view);
  }

  /// Commits the current workspace to Neurohub: builds the portable payload
  /// from the live canvas/CNL state and saves it to the bound GitHub repo
  /// (or creates a new private workspace repo on first save). The
  /// Neurohub save flow surfaces a workspace conflict with a real
  /// reload/compare/save-copy choice instead of a generic failure.
  Future<void> commitWorkspaceToNeurohub() async {
    final workspace = ref.read(workspaceProvider);
    final payload = buildCompleteWorkspacePayload(
      workspace: workspace,
      canvas: ref.read(canvasProvider),
      simulation: ref.read(canvas_sim.simulationProvider),
      resultSnapshot: ref
          .read(studioResultSessionProvider)
          .persistableSnapshot
          ?.toJson(),
    );
    await saveCurrentWorkspaceToNeurohub(
      context,
      ref,
      payload: payload,
      workspaceName: workspace.workspaceName,
      reloadWorkspace: _reloadNeurohubWorkspace,
    );
  }

  /// Loads a Neurohub workspace document back into Studio after a conflict
  /// "reload saved version" choice.
  Future<void> _reloadNeurohubWorkspace(NeurohubWorkspace remote) async {
    ref
        .read(workspaceProvider.notifier)
        .replaceFromWorkspacePayload(
          remote.workspace,
          sourceFileName: remote.displayName,
          sourceFilePath: null,
        );
    restoreCanvasSectionFromPayload(ref, remote.workspace);
  }

  @override
  void initState() {
    super.initState();
    // File-switch → cancel simulation + ensure pipeline results are hydrated.
    _workspaceListenerSub = ref.listenManual<WorkspaceState>(
      workspaceProvider,
      (prev, next) {
        final fileChanged = prev?.activeFile?.id != next.activeFile?.id;
        if (_didHydrateInitialSpec && fileChanged) {
          ref.read(pipelineProvider.notifier).cancelSimulation();
          _syncSpecFromWorkspace(runPipeline: true);
        }
      },
    );
    // Covers all three canvases, and nothing else. `graph` is the Model
    // canvas; `pipelinePhases` is Train + Eval; `pipeline` is the settings
    // config. Selecting only `graph` (as this briefly did) silently stopped
    // persisting Train/Eval entirely, because a pipeline edit never touches
    // `graph` — exactly the "comes back empty after a hot restart" failure the
    // comment above describes.
    //
    // Equality works out per-field: CanvasGraph compares by identity, so it
    // fires on real graph mutations (including each drag frame, which
    // _canvasAutosaveDebounce collapses into one write on release), while
    // PipelinePhases and PipelineConfig both define operator == and so compare
    // by value. Viewport and selection are deliberately absent — panning is
    // not an edit and must not trigger a write.
    _canvasAutosaveListenerSub = ref.listenManual(
      canvasProvider.select(
        (CanvasState s) => (s.graph, s.pipelinePhases, s.pipeline),
      ),
      (_, _) => _fileIo.scheduleCanvasAutosave(),
    );
    _simulationAutosaveListenerSub = ref
        .listenManual<canvas_sim.SimulationState>(
          canvas_sim.simulationProvider,
          (_, _) => _fileIo.scheduleCanvasAutosave(),
        );
    _resultSessionAutosaveListenerSub = ref
        .listenManual<StudioResultSessionState>(studioResultSessionProvider, (
          previous,
          next,
        ) {
          _fileIo.scheduleCanvasAutosave();
        });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final legacyText = ref
          .read(workspaceProvider.notifier)
          .consumePendingLegacyMigrationText();
      if (legacyText != null && legacyText.trim().isNotEmpty) {
        unawaited(
          ref.read(canonicalDocProvider.notifier).updateFromCnl(legacyText),
        );
      }
      final workspaceNotifier = ref.read(workspaceProvider.notifier);
      if (workspaceNotifier.hasPendingWorkspaceResume) {
        if (!workspaceNotifier.beginWorkspaceResumePrompt()) return;
        final shouldResume = await _confirmResumeWorkspace();
        if (!mounted) return;
        if (shouldResume) {
          workspaceNotifier.resumeCachedWorkspace();
        } else {
          workspaceNotifier.discardPendingWorkspaceResume();
          ref.read(canvasProvider.notifier).resetPipelineForFreshSession();
          ref.read(canonicalDocProvider.notifier).clear();
        }
      }
      final canvasRestorePayload = workspaceNotifier
          .consumePendingCanvasRestorePayload();
      if (canvasRestorePayload != null) {
        restoreCanvasSectionFromPayload(ref, canvasRestorePayload);
      }
      final resultRestorePayload = workspaceNotifier
          .consumePendingResultRestorePayload();
      if (resultRestorePayload != null) {
        restoreResultSessionFromPayload(ref, resultRestorePayload);
      }
      _syncSpecFromWorkspace(runPipeline: true);
      unawaited(_loadInitialTemplate());
      unawaited(_loadDefaultHardwareTargets());
      _didHydrateInitialSpec = true;
      _modelSyncNotificationsReady = true;
    });
  }

  /// Asks the user whether to resume a previously-saved workspace found in
  /// local storage at cold start. Deliberately explicit (not automatic) —
  /// see the round-4/round-5 memory-leak history in `current tasks/`:
  /// auto-restoring on cold start was the confirmed cause of a severe RAM
  /// leak, so resume is now opt-in and restores the model plus one bounded,
  /// terminal result summary. Simulation arrays, decoded activity, and
  /// in-flight job ids are never restored.
  Future<bool> _confirmResumeWorkspace() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore previous session?'),
        actions: [
          ZetaButton.text(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            label: 'Start Fresh',
          ),
          ZetaButton.text(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            label: 'Restore',
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  void dispose() {
    _workspaceListenerSub.close();
    _canvasAutosaveListenerSub.close();
    _simulationAutosaveListenerSub.close();
    _resultSessionAutosaveListenerSub.close();
    _canvasAutosaveTimer?.cancel();
    super.dispose();
  }

  Widget _buildStepContent(int index) {
    return StudioPipelineStepContent(
      index: index,
      setupStepKey: _setupStepKey,
      runResultView: _runResultView,
      onRunResultViewChanged: _setRunResultView,
      onManageHardwareTarget: (targetId) =>
          _handleManageHardwareTarget(context, targetId),
      showSetupWorkspaceActions: MediaQuery.sizeOf(context).width < 1200,
      deployPanel: StudioDeployPanelHost(
        selectedDeviceLabels: _selectedHardwareDeviceLabels,
        selectedDeviceDataByTarget: _selectedHardwareDeviceData,
        onSelectTarget: _selectDeployTarget,
        onOpenInNeurosim: () => _openInNeurosim(ref.read(specTextProvider)),
        onManageHardwareTarget: (targetId) =>
            _handleManageHardwareTarget(context, targetId),
        onSyncSelectedHardware: _syncSelectedHardwareProvider,
        onScheduleDeployValidation: _scheduleDeployValidation,
        onScheduleSimulatorPreflight: _scheduleSimulatorPreflight,
      ),
    );
  }

  void _handlePhaseSelected(
    SnnWorkflowPhase phase, {
    required bool platformsReady,
    required Set<String> unlockedSteps,
  }) {
    if (!unlockedSteps.contains(phase.name)) {
      _notifyPlatformRequired(platformsReady);
      return;
    }
    final splitStep = _splitPipelineStep;
    if (splitStep != null) {
      final splitPhase = SnnWorkflowPhase.values.firstWhere(
        (candidate) => candidate.name == splitStep,
      );
      if (snnStageForPhase(splitPhase) != snnStageForPhase(phase)) {
        setState(() => _splitPipelineStep = null);
      }
    }
    ref.read(workspaceProvider.notifier).setActivePipelineStep(phase.name);
  }

  void _handleSplitLeft(String stepName) {
    final idx = kStudioPipelineStepNames.indexOf(stepName);
    if (idx > 0) {
      final adjacent = SnnWorkflowPhase.values[idx - 1];
      final active = SnnWorkflowPhase.values[idx];
      if (snnStageForPhase(adjacent) == snnStageForPhase(active)) {
        setState(() => _splitPipelineStep = adjacent.name);
      }
    }
  }

  void _handleSplitRight(String stepName) {
    final idx = kStudioPipelineStepNames.indexOf(stepName);
    if (idx < kStudioPipelineStepNames.length - 1) {
      final adjacent = SnnWorkflowPhase.values[idx + 1];
      final active = SnnWorkflowPhase.values[idx];
      if (snnStageForPhase(adjacent) == snnStageForPhase(active)) {
        setState(() => _splitPipelineStep = adjacent.name);
      }
    }
  }

  void _clearSplitPipelineStep(String keepStep) {
    setState(() => _splitPipelineStep = null);
    if (ref.read(unlockedStepsProvider).contains(keepStep)) {
      ref.read(workspaceProvider.notifier).setActivePipelineStep(keepStep);
    }
  }

  // ── D3 run/stop helper ────────────────────────────────────────────────────

  void _triggerRun() {
    final viewMode = ref.read(studioViewModeProvider).viewMode;
    if (viewMode == StudioViewMode.nir) return; // NIR tab has no run action.
    if (viewMode == StudioViewMode.canvas) {
      final simState = ref.read(canvas_sim.simulationProvider);
      if (simState.status != canvas_sim.SimulationStatus.running) {
        ref.read(canvas_sim.simulationProvider.notifier).runPreview();
      }
    } else {
      final pipeline = ref.read(pipelineProvider);
      if (pipeline.validateStatus == StepStatus.success &&
          pipeline.validateResult?.overall == true) {
        ref
            .read(pipelineProvider.notifier)
            .runGenerateAndSimulate(
              ref.read(specTextProvider),
              duration: _simulationDuration,
            );
      }
    }
  }

  Future<void> _loadInitialTemplate() async {
    final templateId = widget.initialTemplateId;
    if (templateId == null || templateId.isEmpty) {
      return;
    }

    final templatesAsync = ref.read(templateProvider);
    templatesAsync.whenData((templates) async {
      CnlTemplate? match;
      for (final template in templates) {
        if (template.id == templateId) {
          match = template;
          break;
        }
      }
      if (match == null) {
        return;
      }
      final selectedTemplate = match;
      final shouldReplace = await confirmTemplateReplacement(
        context,
        ref,
        selectedTemplate,
      );
      if (!mounted || !shouldReplace) {
        return;
      }
      await applyTemplateToWorkspace(ref, selectedTemplate);
    });
  }

  void _selectDeployTarget(String targetId) {
    ref.read(workspaceProvider.notifier).setSelectedDeployTarget(targetId);
    // NEW: trigger preflight for simulator targets, invalidate for others.
    _scheduleSimulatorPreflight(targetId);
  }

  static const _simulatorTargets = {
    'lava_sim',
    'snntorch_sim',
    'sc_neurocore_sim',
  };

  /// Schedule a simulator preflight check for [targetId], debounced by a
  /// content-keyed hash (mirrors [_scheduleDeployValidation]).
  ///
  /// Non-simulator targets invalidate any stale preflight state.
  /// For simulator targets, uses `addPostFrameCallback` so that provider reads
  /// happen after the current frame's build phase completes (Requirement 4.1).
  void _scheduleSimulatorPreflight(String targetId) {
    if (!_simulatorTargets.contains(targetId)) {
      // Hardware target — invalidate stale preflight state (Requirement 4.4).
      // Use addPostFrameCallback to avoid modifying provider during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(simulatorPreflightProvider.notifier).invalidate();
      });
      return;
    }

    final spec = ref.read(specTextProvider);
    final nirState = ref.read(nirImportProvider);
    final isNirFile =
        nirState.source == NirSource.file && nirState is NirImportLoaded;

    // Key-based debounce (mirrors _lastDeployValidationKeys).
    final key = isNirFile
        ? '$targetId:nir:${nirState.result.hashCode}'
        : '$targetId:cnl:${spec.hashCode}';
    if (_lastDeployValidationKeys[targetId] == key) return;
    _lastDeployValidationKeys[targetId] = key;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (isNirFile) {
        // Extract raw bytes stored during the .nir file upload.
        final nirBytes = _resolveNirBytes();
        if (nirBytes != null) {
          ref
              .read(simulatorPreflightProvider.notifier)
              .runPreflightNir(nirBytes, targetId);
          return;
        }
      }
      ref
          .read(simulatorPreflightProvider.notifier)
          .runPreflight(spec, targetId);
    });
  }

  /// Returns the raw NIR HDF5 bytes from [nirImportProvider] when a .nir file
  /// is loaded, or `null` if no bytes are available.
  Uint8List? _resolveNirBytes() {
    return ref.read(nirImportProvider).rawBytes;
  }

  Future<void> _loadDefaultHardwareTargets() async {
    final registry = ref.read(studioTargetRegistryServiceProvider);

    // Check Akida default
    try {
      final akidaHosts = await registry.fetchAkidaHosts();
      for (final host in akidaHosts) {
        if (host.isDefault) {
          final entry = SavedHardwareTargetEntry(
            id: host.id,
            title: host.displayName,
            subtitle: '${host.host} • ${host.state.label}',
            targetType: 'akida',
            isDefault: host.isDefault,
            targetData: host,
          );
          await _selectHardwareDevice('akida', entry);
          break;
        }
      }
    } catch (_) {
      // Ignore errors
    }

    // Check SC-NeuroCore FPGA synthesis target default.
    try {
      final scService = ref.read(scNeuroCoreTargetServiceProvider);
      final scTargets = await scService.fetchTargets();
      for (final target in scTargets) {
        if (target.isDefault) {
          final entry = SavedHardwareTargetEntry(
            id: target.id,
            title: target.displayName,
            subtitle: target.subtitle,
            targetType: 'sc_neurocore_fpga',
            isDefault: target.isDefault,
            targetData: target,
          );
          await _selectHardwareDevice('sc_neurocore_fpga', entry);
          break;
        }
      }
    } catch (_) {
      // Ignore errors — local prefs may be empty on first launch.
    }
  }

  Future<HardwareTargetDialogData> _loadHardwareTargetDialogData(
    String targetType,
  ) async {
    final registry = ref.read(studioTargetRegistryServiceProvider);
    switch (targetType) {
      case 'akida':
        final hosts = await registry.fetchAkidaHosts();
        return HardwareTargetDialogData(
          targetType: targetType,
          entries: hosts
              .map(
                (host) => SavedHardwareTargetEntry(
                  id: host.id,
                  title: host.displayName,
                  subtitle: '${host.host} • ${host.state.label}',
                  targetType: targetType,
                  isDefault: host.isDefault,
                  targetData: host,
                ),
              )
              .toList(growable: false),
        );
      case 'pynq':
        final boards = await registry.fetchPynqBoards();
        return HardwareTargetDialogData(
          targetType: targetType,
          entries: boards
              .map(
                (board) => SavedHardwareTargetEntry(
                  id: board.id,
                  title: board.displayName,
                  subtitle: '${board.host} • ${board.state.label}',
                  targetType: targetType,
                  isDefault: board.isDefault,
                  targetData: board,
                ),
              )
              .toList(growable: false),
        );
      case 'sc_neurocore_fpga':
        final scService = ref.read(scNeuroCoreTargetServiceProvider);
        final scTargets = await scService.fetchTargets();
        return HardwareTargetDialogData(
          targetType: targetType,
          entries: scTargets
              .map(
                (target) => SavedHardwareTargetEntry(
                  id: target.id,
                  title: target.displayName,
                  subtitle: target.subtitle,
                  targetType: targetType,
                  isDefault: target.isDefault,
                  targetData: target,
                ),
              )
              .toList(growable: false),
        );
      default:
        // Lava (Loihi2) has no pairable device; the manage-targets dialog
        // is never opened for it.
        return HardwareTargetDialogData(
          targetType: targetType,
          entries: const <SavedHardwareTargetEntry>[],
        );
    }
  }

  Future<SavedHardwareTargetEntry> _saveHardwareTarget(
    String targetType,
    HardwareTargetFormResult form,
  ) async {
    final registry = ref.read(studioTargetRegistryServiceProvider);
    switch (targetType) {
      case 'akida':
        final host = await registry.saveAkidaHost(
          hostId: form.editingEntryId,
          displayName: form.displayName,
          hostAddress: form.host,
          sshPort: form.sshPort,
          username: form.username,
          authMode: form.authMode,
          password: form.password,
          sshKeyPath: form.sshKeyPath,
          runtimeApiUrl: form.runtimeApiUrl,
          controlApiUrl: form.controlApiUrl,
          remoteInstallRoot: form.remoteInstallRoot,
          serviceUser: form.serviceUser,
          isDefault: form.isDefault,
          sameHostAsBackend: form.sameHostAsBackend,
        );
        return SavedHardwareTargetEntry(
          id: host.id,
          title: host.displayName,
          subtitle: '${host.host} • ${host.state.label}',
          targetType: targetType,
          isDefault: host.isDefault,
          targetData: host,
        );
      case 'pynq':
        final board = await registry.savePynqBoard(
          boardId: form.editingEntryId,
          displayName: form.displayName,
          hostAddress: form.host,
          sshPort: form.sshPort,
          username: form.username,
          authMode: form.authMode,
          // `savePynqBoard` takes a plain String, where `null` from the form
          // means "keep the stored password". Sending '' would clear it, so
          // collapse null to '' only after the service omits the key — which it
          // does for an empty value.
          password: form.password ?? '',
          sshKeyPath: form.sshKeyPath,
          runtimeApiUrlOverride: form.runtimeApiUrlOverride,
          overlayVersion: form.overlayVersion,
          isDefault: form.isDefault,
        );
        return SavedHardwareTargetEntry(
          id: board.id,
          title: board.displayName,
          subtitle: '${board.host} • ${board.state.label}',
          targetType: targetType,
          isDefault: board.isDefault,
          targetData: board,
        );
      case 'sc_neurocore_fpga':
        final scService = ref.read(scNeuroCoreTargetServiceProvider);
        final saved = await scService.saveTarget(
          ScNeuroCoreTarget(
            id: form.editingEntryId ?? '',
            displayName: form.displayName,
            family: form.scFamily,
            deviceSpec: form.scDeviceSpec,
            toolchain: form.scToolchain,
            deploymentMode: form.scDeploymentMode,
            host: form.scHost,
            sshPort: form.scSshPort,
            username: form.scUsername,
            sshKeyPath: form.scSshKeyPath,
            toolchainBinPath: form.scToolchainBinPath,
            outputDirectory: form.scOutputDirectory,
            isDefault: form.isDefault,
          ),
        );
        return SavedHardwareTargetEntry(
          id: saved.id,
          title: saved.displayName,
          subtitle: saved.subtitle,
          targetType: targetType,
          isDefault: saved.isDefault,
          targetData: saved,
        );
      default:
        // Akida, PYNQ and SC-NeuroCore FPGA are the pairable targets; Lava
        // (Loihi2) has no device to save.
        throw UnsupportedError(
          'No saveable hardware target for "$targetType".',
        );
    }
  }

  Future<bool> _selectHardwareDevice(
    String targetType,
    SavedHardwareTargetEntry entry,
  ) async {
    // Both remote targets persist the selection in launcher control, which is
    // what its own preflight and proxy routes act on — a selection kept only in
    // this screen would send deploys to a different device than the dot reports.
    final (
      String? selectionAction,
      Future<void> Function()? persistSelection,
    ) = switch (entry.targetData) {
      final AkidaPairedHost host => (
        'selecting the Akida target',
        () => ref
            .read(studioTargetRegistryServiceProvider)
            .selectAkidaHost(host.id),
      ),
      final PynqPairedBoard board => (
        'selecting the PYNQ-Z2 board',
        () => ref
            .read(studioTargetRegistryServiceProvider)
            .selectPynqBoard(board.id),
      ),
      _ => (null, null),
    };
    if (persistSelection != null) {
      try {
        await persistSelection();
      } catch (error) {
        if (mounted) {
          _showMessage(
            formatDeployError(
              error,
              serviceName: 'launcher control service',
              action: selectionAction!,
            ),
            isError: true,
          );
        }
        return false;
      }
    }
    _selectDeployTarget(targetType);
    setState(() {
      _selectedHardwareDeviceIds[targetType] = entry.id;
      _selectedHardwareDeviceLabels[targetType] = entry.title;
      if (entry.targetData != null) {
        _selectedHardwareDeviceData[targetType] = entry.targetData!;
      }
    });
    switch (entry.targetData) {
      case final AkidaPairedHost host:
        ref.read(studioAkidaDeployProvider.notifier).selectHost(host);
      case final PynqPairedBoard board:
        ref.read(studioPynqDeployProvider.notifier).selectBoard(board);
      case _:
        break;
    }
    return true;
  }

  void _syncSelectedHardwareProvider(String targetType) {
    final selected = _selectedHardwareDeviceData[targetType];
    switch ((targetType, selected)) {
      case ('akida', final AkidaPairedHost host):
        final akidaState = ref.read(studioAkidaDeployProvider);
        if (akidaState.selectedHost?.id != host.id) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            ref.read(studioAkidaDeployProvider.notifier).selectHost(host);
          });
        }
      case ('pynq', final PynqPairedBoard board):
        final pynqState = ref.read(studioPynqDeployProvider);
        if (pynqState.selectedBoard?.id != board.id) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            ref.read(studioPynqDeployProvider.notifier).selectBoard(board);
          });
        }
      case _:
        break;
    }
  }

  void _scheduleDeployValidation(String targetType) {
    // Hardware targets no longer run a pre-emptive deploy validation pass on
    // selection; each workspace validates on demand. Retained as a hook so
    // future targets can opt back in via [_lastDeployValidationKeys].
  }

  void _syncSpecFromWorkspace({required bool runPipeline}) {
    final activeFile = ref.read(workspaceProvider).activeFile;
    // Guard: if no file is active (transient state during init or all-files-
    // closed edge case), do nothing.
    if (activeFile == null) return;
    // specTextProvider derives from canonicalDocProvider directly now, so it
    // is already current the moment the active file changes — nothing to
    // re-sync here. Only the pipeline bootstrap below is still needed.
    final content = activeFile.canonicalDocument?.cnlText ?? '';
    if (content.isEmpty) return;
    if (runPipeline) {
      // Skip the parse/validate round-trip when results are already current for
      // this content — avoids a visible flicker and unnecessary API calls when
      // the user returns to a file they've already parsed.
      final pipeline = ref.read(pipelineProvider);
      final alreadyParsed =
          pipeline.parseStatus != StepStatus.idle &&
          pipeline.parseStatus != StepStatus.running;
      if (!alreadyParsed) {
        ref.read(pipelineProvider.notifier).runParseAndValidate(content);
      }
      ref
          .read(pipelineProvider.notifier)
          .hydrateCachedResultsForFile(activeFile);
    }
  }

  Uri _currentRouteUri() {
    try {
      return GoRouterState.of(context).uri;
    } on GoError {
      return Uri.parse(ref.read(workspaceBootstrapProvider).initialLocation);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspaceTabs = ref.watch(
      workspaceProvider.select(WorkspaceTabViewData.fromState),
    );
    final activeStep = ref.watch(
      workspaceProvider.select((workspace) => workspace.activePipelineStep),
    );
    final unlockedSteps = ref.watch(unlockedStepsProvider);
    final platformsReady = ref.watch(
      workspaceProvider.select(
        (workspace) => workspace.selectedPlatforms.isNotEmpty,
      ),
    );
    // Sync failures are visible after startup, but never before the user has
    // chosen whether to restore the previous workspace. Backend parser
    // payloads may be multi-line, so they never belong directly in a snackbar.
    ref.listen(canonicalDocProvider, (previous, next) {
      if (!next.hasError || previous?.error == next.error) return;
      if (!_modelSyncNotificationsReady) return;
      if (!mounted) return;
      NmtkSnackBars.error(
        context,
        'Model sync failed — CNL still shows the last good version. '
        'Review the Model canvas and correct or remove the unsupported node.',
      );
    });

    final routeUri = _currentRouteUri();
    final routeSyncKey = routeUri.toString();

    if (_lastRouteSyncKey != routeSyncKey) {
      _lastRouteSyncKey = routeSyncKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(workspaceProvider.notifier).applyRouteUri(routeUri);
      });
    }

    final content = StudioAssistantHost(
      isMobile: MediaQuery.sizeOf(context).width < 900,
      child: StudioKeyboardShortcutScope(
        onTriggerRun: _triggerRun,
        onSaveWorkspace: () =>
            _fileIo.runDesktopShortcutIfAllowed(_fileIo.saveWorkspace),
        onSaveWorkspaceAs: () =>
            _fileIo.runDesktopShortcutIfAllowed(_fileIo.saveWorkspaceAs),
        onOpenWorkspace: () =>
            _fileIo.runDesktopShortcutIfAllowed(_fileIo.openWorkspace),
        onNewFile: () => _fileIo.runDesktopShortcutIfAllowed(_fileIo.newFile),
        child: LayoutBuilder(
        builder: (context, layoutConstraints) {
          final metrics = StudioLayoutMetrics.forConstraints(
            layoutConstraints: layoutConstraints,
            tokens: context.nmtkTokens,
            activeStep: activeStep,
          );
          if (metrics.isMobile) {
            return StudioMobileShell(
              activeStep: activeStep,
              unlockedSteps: unlockedSteps,
              workspaceTabs: workspaceTabs,
              splitPipelineStep: _splitPipelineStep,
              metrics: metrics,
              stepBuilder: _buildStepContent,
              onPhaseSelected: (phase) => _handlePhaseSelected(
                phase,
                platformsReady: platformsReady,
                unlockedSteps: unlockedSteps,
              ),
              onCollapseSplit: _clearSplitPipelineStep,
              onSaveWorkspace: _fileIo.saveWorkspace,
              onShareToNeurohub: commitWorkspaceToNeurohub,
              onEditServer: widget.onEditServer,
            );
          }
          return StudioDesktopShell(
            layoutConstraints: layoutConstraints,
            activeStep: activeStep,
            unlockedSteps: unlockedSteps,
            workspaceTabs: workspaceTabs,
            splitPipelineStep: _splitPipelineStep,
            metrics: metrics,
            setupStepKey: _setupStepKey,
            stepBuilder: _buildStepContent,
            frameBuilder: _buildWorkspaceFrame,
            onPhaseSelected: (phase) => _handlePhaseSelected(
              phase,
              platformsReady: platformsReady,
              unlockedSteps: unlockedSteps,
            ),
            onSplitLeft: _handleSplitLeft,
            onSplitRight: _handleSplitRight,
            onCollapseSplit: _clearSplitPipelineStep,
            onActiveFileSelected: (id) =>
                ref.read(workspaceProvider.notifier).setActiveFile(id),
            onFileClosed: (id) =>
                ref.read(workspaceProvider.notifier).closeFile(id),
            onSaveWorkspace: _fileIo.saveWorkspace,
            onShareToNeurohub: commitWorkspaceToNeurohub,
            workspaceHeaderAction: widget.workspaceHeaderAction,
          );
        },
        ),
      ),
    );

    if (!_isOpeningWorkspace) return content;

    return Stack(
      children: [
        content,
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: _isOpeningWorkspace ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: const WorkspaceOpenOverlay(),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspaceFrame({required Widget child}) {
    final tokens = NmtkShellTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        border: Border.all(color: AppTheme.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        child: child,
      ),
    );
  }

  Future<void> _openInNeurosim(String spec) async {
    if (hasHostedModuleNavigator(context)) {
      if (spec.trim().isEmpty) {
        _showMessage('Write or load a spec first.', isError: true);
        return;
      }

      try {
        final importContract = await ref
            .read(apiClientProvider)
            .prepareNeurosimHandoff(spec);
        final deepLink = NeurosimHandoff.buildDeepLink(
          importContract: importContract,
        );
        if (!mounted) {
          return;
        }
        if (deepLink == null) {
          _showMessage('Write or load a spec first.', isError: true);
          return;
        }

        final encodedContract = Uri.parse(
          deepLink,
        ).queryParameters['import_contract'];
        if (encodedContract != null &&
            encodedContract.length > NeurosimHandoff.maxEncodedSpecLength) {
          ref
              .read(workspaceProvider.notifier)
              .recordActivity(
                kind: 'handoff',
                title: 'NeuroSim handoff blocked',
                detail:
                    'The canonical NeuroSim import contract exceeded the safe URL size for one-click handoff.',
                status: 'warning',
                panelId: 'deploy',
              );
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Spec is too large for one-click handoff'),
              content: const Text(
                'This spec is larger than the safe URL payload for automatic handoff. '
                'Save the .cnl file from the export workspace or copy the spec into NeuroSim manually.',
              ),
              actions: [
                ZetaButton.text(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  label: 'OK',
                ),
              ],
            ),
          );
          return;
        }

        final opened = await openModuleInHost(
          context,
          // Canvas is now part of the merged neurocnl module; the launcher's
          // 'Neurosim' alias still works but the canonical id is 'neurocnl'.
          moduleId: 'neurocnl',
          deepLink: deepLink,
        );
        if (!mounted) {
          return;
        }
        if (!opened) {
          ref
              .read(workspaceProvider.notifier)
              .recordActivity(
                kind: 'handoff',
                title: 'NeuroSim handoff failed',
                detail: 'Studio could not open the NeuroSim native surface.',
                status: 'error',
                panelId: 'deploy',
              );
          _showMessage(
            'Could not open NeuroSim automatically in this suite workspace. Try reopening the module and running the handoff again.',
            isError: true,
          );
        } else {
          ref
              .read(workspaceProvider.notifier)
              .recordActivity(
                kind: 'handoff',
                title: 'NeuroSim handoff opened',
                detail: 'Opened the normalized CNL handoff in the suite shell.',
                status: 'success',
                panelId: 'deploy',
              );
        }
      } catch (error) {
        ref
            .read(workspaceProvider.notifier)
            .recordActivity(
              kind: 'handoff',
              title: 'NeuroSim handoff failed',
              detail: _neurosimHandoffErrorMessage(error),
              status: 'error',
              panelId: 'deploy',
            );
        _showMessage(_neurosimHandoffErrorMessage(error), isError: true);
      }
      return;
    }

    final coordinator = NeurosimHandoffCoordinator(
      apiClient: ref.read(apiClientProvider),
    );

    try {
      final preparation = await coordinator.prepareTarget(spec: spec);
      if (!mounted) {
        return;
      }

      if (preparation.status == NeurosimHandoffPreparationStatus.unavailable) {
        ref
            .read(workspaceProvider.notifier)
            .recordActivity(
              kind: 'handoff',
              title: 'NeuroSim handoff unavailable',
              detail:
                  'This session does not expose a browser-capable handoff origin.',
              status: 'warning',
              panelId: 'deploy',
            );
        _showMessage(
          'One-click NeuroSim handoff needs a browser-capable suite workspace. Use export from this workspace if you need a saved artifact instead.',
          isError: true,
        );
        return;
      }

      if (preparation.status == NeurosimHandoffPreparationStatus.emptySpec) {
        _showMessage('Write or load a spec first.', isError: true);
        return;
      }

      final target = preparation.target!;
      if (NeurosimHandoff.exceedsSafePayload(target)) {
        ref
            .read(workspaceProvider.notifier)
            .recordActivity(
              kind: 'handoff',
              title: 'NeuroSim handoff blocked',
              detail:
                  'The normalized CNL payload exceeded the safe URL size for one-click handoff.',
              status: 'warning',
              panelId: 'deploy',
            );
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Spec is too large for one-click handoff'),
            content: const Text(
              'This spec is larger than the safe URL payload for automatic handoff. '
              'Save the .cnl file from the export workspace or copy the spec into NeuroSim manually.',
            ),
            actions: [
              ZetaButton.text(
                onPressed: () => Navigator.of(dialogContext).pop(),
                label: 'OK',
              ),
            ],
          ),
        );
        return;
      }

      final opened = await platform.openUrl(target.url.toString());
      if (!mounted) {
        return;
      }
      if (!opened) {
        ref
            .read(workspaceProvider.notifier)
            .recordActivity(
              kind: 'handoff',
              title: 'NeuroSim handoff failed',
              detail:
                  'Studio could not open the NeuroSim target automatically.',
              status: 'error',
              panelId: 'deploy',
            );
        _showMessage(
          'Could not open NeuroSim automatically from this workspace. Try again from a browser-capable suite workspace.',
          isError: true,
        );
      } else {
        ref
            .read(workspaceProvider.notifier)
            .recordActivity(
              kind: 'handoff',
              title: 'NeuroSim handoff opened',
              detail: 'Opened the normalized CNL handoff target.',
              status: 'success',
              panelId: 'deploy',
            );
      }
    } catch (error) {
      ref
          .read(workspaceProvider.notifier)
          .recordActivity(
            kind: 'handoff',
            title: 'NeuroSim handoff failed',
            detail: _neurosimHandoffErrorMessage(error),
            status: 'error',
            panelId: 'deploy',
          );
      _showMessage(_neurosimHandoffErrorMessage(error), isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    if (isError) {
      NmtkSnackBars.error(context, message);
    } else {
      NmtkSnackBars.success(context, message);
    }
  }

  void _notifyPlatformRequired(bool platformsReady) {
    if (platformsReady) return;
    _showMessage(
      'Select a target platform in Setup before continuing.',
      isError: true,
    );
  }

  Future<void> _handleManageHardwareTarget(
    BuildContext context,
    String targetId,
  ) async {
    HardwareTargetDialogData dialogData;
    try {
      dialogData = await _loadHardwareTargetDialogData(targetId);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      // Open the dialog anyway so the user can see the error and still
      // add a target manually (Bug 1 fix: dialog never silently returns).
      dialogData = HardwareTargetDialogData(
        targetType: targetId,
        entries: const <SavedHardwareTargetEntry>[],
        loadErrorMessage: formatDeployError(
          error,
          serviceName: 'launcher control service',
          action: 'loading ${targetLabel(targetId)} targets',
        ),
      );
    }
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => HardwareTargetDialog(
        data: dialogData,
        selectedEntryId: _selectedHardwareDeviceIds[targetId],
        onSelectTarget: (entry) async {
          final selected = await _selectHardwareDevice(targetId, entry);
          if (!selected) return;
          if (!dialogContext.mounted) return;
          Navigator.of(dialogContext).pop();
        },
        // Saves and selects, but deliberately does not close the dialog: the
        // dialog decides that, because "Save and test connection" has to keep it
        // open to show the verdict. This callback previously popped on success,
        // and returned silently when selection failed — which left the form
        // wedged behind a permanent "Saving..." after a save that had in fact
        // committed. `selected` is reported back so the dialog can say so.
        onSaveTarget: (form) async {
          final saved = await _saveHardwareTarget(targetId, form);
          final selected = await _selectHardwareDevice(targetId, saved);
          return (entry: saved, selected: selected);
        },
        // Every target type with a reachable-over-SSH check belongs here. The
        // dialog reads this one callback for both "Save and test connection" on
        // the form and the per-row Test icon, so a target missing from this
        // switch silently loses both — which is how a PYNQ board could be
        // paired but never contacted.
        onTestTarget: switch (targetId) {
          'akida' => (entryId) => _testAkidaHostConnection(entryId),
          'pynq' => (entryId) => _testPynqBoardConnection(entryId),
          _ => null,
        },
        onReloadEntries: () async {
          final refreshed = await _loadHardwareTargetDialogData(targetId);
          return refreshed.entries;
        },
        // Akida is the only chip type with a paired-host model today; PYNQ is
        // network-attached with no local scan (CEL-120), so it gets no action.
        onScanHardware: targetId == 'akida'
            ? () async {
                final result = await ref
                    .read(hardwareAutoAddScannerProvider)
                    .run();
                return result.describe();
              }
            : null,
      ),
    );
  }

  /// Verifies a saved Akida host, installs/starts its runtime service, and
  /// returns a one-line verdict for the dialog.
  ///
  /// `provisionAkidaHost` used to have no UI caller at all: saving a host only
  /// registered its connection details, so the Neurochip runtime service was
  /// never installed or started and every later use of the host failed with
  /// "Akida runtime service unreachable". The SSH check runs first — on the
  /// SSH path launcher control runs `python3 --version`, which works before
  /// the runtime is installed and needs no API token — so a bad host/username
  /// fails fast instead of attempting a multi-minute install.
  Future<String> _testAkidaHostConnection(String hostId) async {
    final registry = ref.read(studioTargetRegistryServiceProvider);
    await registry.testAkidaHostConnection(hostId);
    final host = await registry.provisionAkidaHost(hostId);
    final detail = host.lastReadinessMessage.trim();
    final verdict = detail.isEmpty ? host.state.label : detail;
    return '${host.displayName}: $verdict';
  }

  /// Verifies a saved PYNQ-Z2 board answers SSH, and returns a one-line verdict.
  ///
  /// Deliberately *not* the Akida shape: no provision follows. Launcher control
  /// runs `python3 --version` over SSH, which works before the board agent
  /// exists and needs no API token, so this is the right check to offer the
  /// moment a board is paired — a wrong address, user or password fails here in
  /// seconds instead of surfacing later as an unexplained grey status dot.
  /// Installing the runtime stays an explicit choice in the PYNQ workspace,
  /// because a cold provision needs 90–100 s.
  Future<String> _testPynqBoardConnection(String boardId) async {
    final registry = ref.read(studioTargetRegistryServiceProvider);
    final board = await registry.testPynqBoardConnection(boardId);
    final detail = board.lastPreflightMessage.trim();
    final verdict = detail.isEmpty ? board.state.label : detail;
    return '${board.displayName}: $verdict';
  }

  String _neurosimHandoffErrorMessage(Object error) {
    const fallback =
        'Could not prepare a NeuroSim handoff. Review the spec and try again.';

    if (error is! ApiException) {
      return fallback;
    }

    try {
      final decoded = jsonDecode(error.body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return detail;
        }
      }
    } catch (_) {
      return fallback;
    }

    return fallback;
  }
}
