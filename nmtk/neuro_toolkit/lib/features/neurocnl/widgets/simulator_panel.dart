/// Studio simulation panel — the CNL → NIR → Simulator UI surface.
///
/// Shows:
///   - Backend selector (Lava simulator / snnTorch simulator)
///   - Capability / preflight status badge
///   - Runtime settings: timesteps, seed
///   - Run button
///   - Result tabs: Activity | Report
///
/// The Activity tab shows animated spike raster + membrane potential traces
/// per population (when voltage data is available from the backend).
/// The Report tab merges Output Summary, Warnings, and NIR Support into a single
/// scrollable view with section headers at normal body font sizes.
library;

import 'dart:async';

import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/models/simulator.dart';
import 'package:neuro_toolkit/features/neurocnl/models/trained_nir_artifact.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/simulator_preflight_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/simulator_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/labeled_parameter_grid.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/animated_snn_playback.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/simulator/signals_metrics.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/simulator/signals_tab.dart';

// ---------------------------------------------------------------------------
// Panel entry point
// ---------------------------------------------------------------------------

/// Whether a simulation may start, and what to tell the user when it may not.
///
/// One predicate, two toolbars. The full panel and the compact deploy toolbar
/// gate the same Run button, and a second copy of this would drift the moment
/// either one gained a case.
@immutable
class SimulatorRunGate {
  const SimulatorRunGate({required this.blocked, this.message = ''});

  final bool blocked;

  /// Tooltip text. Empty for the cases that are worth no explanation.
  final String message;

  /// A network that was never trained carries the CNL spec's zeros, so running
  /// it can only ever produce an empty raster. Saying that up front beats
  /// rendering a blank chart the user has to interpret.
  static const String untrainedMessage =
      'This network has no trained weights yet — every weight would be 0.0, so '
      'no neuron can fire. Add a NIR Exporter node to your Training canvas and '
      'run the pipeline, then come back.';

  static SimulatorRunGate resolve({
    required SimulatorPreflightState preflight,
    required AsyncValue<TrainedNirArtifact?> trainedNir,
  }) {
    if (preflight.status == SimulatorPreflightStatus.running) {
      return const SimulatorRunGate(
        blocked: true,
        message: 'Preflight in progress — please wait.',
      );
    }
    if (preflight.level == 'unsupported' && !preflight.overrideMode) {
      return const SimulatorRunGate(
        blocked: true,
        message:
            'Unsupported node types detected. See preflight results above.',
      );
    }
    if (trainedNir.isLoading) {
      return const SimulatorRunGate(
        blocked: true,
        message: 'Looking for this network’s trained weights…',
      );
    }
    if (trainedNir.value == null) {
      return const SimulatorRunGate(blocked: true, message: untrainedMessage);
    }
    if (preflight.level == 'approximate') {
      return SimulatorRunGate(
        blocked: false,
        message: 'Approximate nodes: ${preflight.approximateNodes.join(", ")}',
      );
    }
    return const SimulatorRunGate(blocked: false);
  }
}

class SimulatorPanel extends ConsumerStatefulWidget {
  /// When [initialBackend] is supplied the backend selector is pre-set to that
  /// value.  Pass `'lava_sim'`, `'snntorch_sim'`, or `'sc_neurocore_sim'`
  /// when embedding the panel inside a Deploy pane target so the user lands
  /// directly on the right backend without having to select it manually.
  const SimulatorPanel({
    super.key,
    this.initialBackend,
    this.showResults = true,
    this.mobileActionBuilder,
  });

  final String? initialBackend;

  /// When false the Activity/Report result area is omitted — the Deploy step
  /// passes this because the run's results are shown in the Review step
  /// ([SimulatorResultsPanel]). Errors are still shown here: they are feedback
  /// on the run the user just started, not a result to review.
  final bool showResults;

  /// Lets the embedding Deploy workspace render the existing Run callback in
  /// its safe-area action dock without moving simulator form state upward.
  final Widget Function(VoidCallback? onRun, bool isRunning)?
  mobileActionBuilder;

  @override
  ConsumerState<SimulatorPanel> createState() => _SimulatorPanelState();
}

class _SimulatorPanelState extends ConsumerState<SimulatorPanel>
    with SingleTickerProviderStateMixin {
  late String _selectedBackend;
  int _timesteps = 100;
  int _seed = 1;
  double _dtMs = 1.0;
  double _firingRate = 0.3;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _selectedBackend = widget.initialBackend ?? 'lava_sim';
    _tabController = TabController(length: 2, vsync: this);
    if (widget.initialBackend != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(simulatorPreflightProvider.notifier).invalidate();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant SimulatorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialBackend != oldWidget.initialBackend &&
        widget.initialBackend != null) {
      setState(() => _selectedBackend = widget.initialBackend!);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildTabBar(ThemeData theme) {
    return TabBar(
      controller: _tabController,
      labelStyle: theme.textTheme.labelSmall,
      tabs: const [
        Tab(text: 'Activity'),
        Tab(text: 'Report'),
      ],
    );
  }

  Widget _buildTabViews(SimulatorRunResult result) {
    return TabBarView(
      controller: _tabController,
      children: [
        _ActivityTab(result: result),
        _ReportTab(result: result),
      ],
    );
  }

  /// The trained NIR graph for the workspace this panel is showing.
  ///
  /// The spec compiles to shape-only tensors, so this is what separates a run
  /// that computes something from one that runs a network of zeros.
  SimulatorTrainedNirProvider _trainedNirProvider(String workspaceName) =>
      simulatorTrainedNirProvider(workspaceName);

  void _run() {
    final spec = ref.read(specTextProvider);
    if (spec.trim().isEmpty) return;
    final workspaceName = ref.read(workspaceProvider).workspaceName;
    final trainedNir = ref.read(_trainedNirProvider(workspaceName)).value;
    ref
        .read(simulatorRunProvider(_selectedBackend).notifier)
        .run(
          SimulatorRunRequest(
            spec: spec,
            backendName: _selectedBackend,
            timesteps: _timesteps,
            seed: _seed,
            dtMs: _dtMs,
            firingRate: _firingRate,
            trainedNirBase64: trainedNir?.nirBase64,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final capabilitiesAsync = ref.watch(simulatorCapabilitiesProvider);
    final runState = ref.watch(simulatorRunProvider(_selectedBackend));
    final theme = Theme.of(context);
    final workspaceName = ref.watch(
      workspaceProvider.select((s) => s.workspaceName),
    );
    final gate = SimulatorRunGate.resolve(
      preflight: ref.watch(simulatorPreflightProvider),
      trainedNir: ref.watch(_trainedNirProvider(workspaceName)),
    );

    final locked = widget.initialBackend != null;

    if (locked) {
      // ── Compact deploy-pane layout ─────────────────────────────────────────
      // Single toolbar row: [availability chip] [timestep] [seed] [Run] [error]
      // The full remaining space goes to the result area.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Requirement 7.x / 8.x — preflight result area above toolbar.
          const _PreflightResultWidget(),
          _CompactToolbar(
            selectedBackend: _selectedBackend,
            capabilitiesAsync: capabilitiesAsync,
            timesteps: _timesteps,
            seed: _seed,
            dtMs: _dtMs,
            firingRate: _firingRate,
            runState: runState,
            gate: gate,
            onTimestepsChanged: (v) => setState(() => _timesteps = v),
            onSeedChanged: (v) => setState(() => _seed = v),
            onDtMsChanged: (v) => setState(() => _dtMs = v),
            onFiringRateChanged: (v) => setState(() => _firingRate = v),
            onRun: _run,
            onReset: () => ref
                .read(simulatorRunProvider(_selectedBackend).notifier)
                .reset(),
            onRefreshCapabilities: () =>
                ref.read(simulatorCapabilitiesProvider.notifier).refresh(),
            mobileActionBuilder: widget.mobileActionBuilder,
          ),
          const Divider(height: 1),
          ...switch (runState) {
            SimulatorRunIdle() || SimulatorRunLoading() => [
              const Expanded(child: _EmptyResultsPlaceholder()),
            ],
            SimulatorRunError err => [
              _SimulatorErrorDetails(error: err),
              const Expanded(child: _EmptyResultsPlaceholder()),
            ],
            SimulatorRunSuccess(:final result) =>
              widget.showResults
                  ? [
                      _buildTabBar(theme),
                      Expanded(child: _buildTabViews(result)),
                    ]
                  : [const Expanded(child: _ResultsMovedToReviewNote())],
          },
        ],
      );
    }

    // ── Standalone panel layout (separate Simulate tab) ──────────────────────
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          selectedBackend: _selectedBackend,
          lockedBackend: false,
          capabilitiesAsync: capabilitiesAsync,
          onBackendChanged: (name) {
            setState(() => _selectedBackend = name);
          },
          onRefreshCapabilities: () =>
              ref.read(simulatorCapabilitiesProvider.notifier).refresh(),
        ),
        const Divider(height: 1),
        _RuntimeSettings(
          timesteps: _timesteps,
          seed: _seed,
          dtMs: _dtMs,
          firingRate: _firingRate,
          onTimestepsChanged: (v) => setState(() => _timesteps = v),
          onSeedChanged: (v) => setState(() => _seed = v),
          onDtMsChanged: (v) => setState(() => _dtMs = v),
          onFiringRateChanged: (v) => setState(() => _firingRate = v),
        ),
        const Divider(height: 1),
        _RunBar(
          runState: runState,
          gate: gate,
          onRun: _run,
          onReset: () =>
              ref.read(simulatorRunProvider(_selectedBackend).notifier).reset(),
        ),
        ...switch (runState) {
          SimulatorRunIdle() || SimulatorRunLoading() => [
            const Expanded(child: _EmptyResultsPlaceholder()),
          ],
          SimulatorRunError err => [
            const Divider(height: 1),
            _SimulatorErrorDetails(error: err),
            const Expanded(child: _EmptyResultsPlaceholder()),
          ],
          SimulatorRunSuccess(:final result) => [
            const Divider(height: 1),
            _buildTabBar(theme),
            Expanded(child: _buildTabViews(result)),
          ],
        },
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _PanelHeader extends StatelessWidget {
  final String selectedBackend;

  /// When true the backend dropdown is hidden — the backend is fixed by the
  /// Deploy pane context (e.g. "Lava simulator" target always uses lava_sim).
  final bool lockedBackend;
  final AsyncValue<List<SimulatorCapability>> capabilitiesAsync;
  final ValueChanged<String> onBackendChanged;
  final VoidCallback onRefreshCapabilities;

  const _PanelHeader({
    required this.selectedBackend,
    required this.lockedBackend,
    required this.capabilitiesAsync,
    required this.onBackendChanged,
    required this.onRefreshCapabilities,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!lockedBackend)
            Text('Simulator', style: theme.textTheme.labelMedium),
          if (!lockedBackend) const SizedBox(height: 6),
          capabilitiesAsync.when(
            skipLoadingOnReload: true,
            skipLoadingOnRefresh: true,
            skipError: false,
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (e, _) => Row(
              children: [
                Icon(
                  ZetaIcons.warning_outline,
                  size: 14,
                  color: NmtkShellTokens.of(context).warningColor,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Could not load capabilities. Check backend.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(ZetaIcons.refresh, size: 14),
                  onPressed: onRefreshCapabilities,
                  tooltip: 'Retry',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            data: (caps) {
              // When locked, find only the capability for the active backend
              // and show just the availability chip — no dropdown.
              if (lockedBackend) {
                final cap = caps
                    .where((c) => c.backendName == selectedBackend)
                    .firstOrNull;
                if (cap == null) return const SizedBox.shrink();
                return _AvailabilityChip(capability: cap);
              }
              return _BackendSelector(
                capabilities: caps,
                selectedBackend: selectedBackend,
                onChanged: onBackendChanged,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BackendSelector extends StatelessWidget {
  final List<SimulatorCapability> capabilities;
  final String selectedBackend;
  final ValueChanged<String> onChanged;

  const _BackendSelector({
    required this.capabilities,
    required this.selectedBackend,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = capabilities
        .where((c) => c.backendName == selectedBackend)
        .firstOrNull;

    return Row(
      children: [
        DropdownButton<String>(
          value: selectedBackend,
          isDense: true,
          underline: const SizedBox.shrink(),
          items: capabilities
              .map(
                (c) => DropdownMenuItem(
                  value: c.backendName,
                  child: Text(c.displayName, style: theme.textTheme.bodySmall),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
        const SizedBox(width: 8),
        if (selected != null) _AvailabilityChip(capability: selected),
      ],
    );
  }
}

class SimulatorAvailabilityChip extends StatelessWidget {
  final SimulatorCapability capability;

  const SimulatorAvailabilityChip({super.key, required this.capability});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    if (capability.available) {
      return Chip(
        label: const Text('Ready'),
        labelStyle: theme.textTheme.labelSmall?.copyWith(
          color: tokens.healthyColor,
        ),
        backgroundColor: tokens.healthyColor.withValues(alpha: 0.10),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      );
    }
    return Tooltip(
      message: capability.unavailableReason ?? 'Dependency not installed.',
      child: Chip(
        avatar: const Icon(ZetaIcons.download, size: 12),
        label: Text(
          capability.requiresOptionalDependency != null
              ? 'Install ${capability.requiresOptionalDependency}'
              : 'Missing dependency',
        ),
        labelStyle: theme.textTheme.labelSmall?.copyWith(
          color: tokens.degradedColor,
        ),
        backgroundColor: tokens.degradedColor.withValues(alpha: 0.10),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

typedef _AvailabilityChip = SimulatorAvailabilityChip;

/// Runs [backend]'s simulator using its own current
/// [simulatorSettingsProvider] values. Shared by [SimulatorParametersSection]
/// and the Deploy step's simulator table's "Run all" action, so both trigger
/// a run the exact same way.
void runSimulatorBackend(WidgetRef ref, String backend) {
  final spec = ref.read(specTextProvider);
  if (spec.trim().isEmpty) return;
  final workspaceName = ref.read(
    workspaceProvider.select((s) => s.workspaceName),
  );
  final trainedNir = ref.read(simulatorTrainedNirProvider(workspaceName)).value;
  final settings = ref.read(simulatorSettingsProvider(backend));
  // Snapshot the settings this run is actually launched with, so the Deploy
  // step's simulator table can tell a completed run apart from a stale one
  // (settings changed afterwards) by comparing against the backend's live
  // settings later. See `simulatorLastRunSettingsProvider`.
  ref.read(simulatorLastRunSettingsProvider.notifier).record(backend, settings);
  ref
      .read(simulatorRunProvider(backend).notifier)
      .run(
        SimulatorRunRequest(
          spec: spec,
          backendName: backend,
          timesteps: settings.timesteps,
          seed: settings.seed,
          dtMs: settings.dtMs,
          firingRate: settings.firingRate,
          trainedNirBase64: trainedNir?.nirBase64,
        ),
      );
}

/// Reusable sidebar section holding runtime parameter inputs and Run/Clear
/// actions for simulator deployment panes.
class SimulatorParametersSection extends ConsumerWidget {
  const SimulatorParametersSection({
    super.key,
    required this.backend,
    this.showRunButton = true,
    this.runButtonLabel,
    this.mobileActionBuilder,
    this.onAnyFieldChanged,
  });

  final String backend;
  final bool showRunButton;
  final String? runButtonLabel;
  final Widget Function(VoidCallback? onRun, bool isRunning)?
  mobileActionBuilder;

  /// Called, in addition to the field's own setter, whenever any parameter
  /// below changes. The Deploy step's simulator table uses this to mark a
  /// target as individually overridden the moment its settings are hand-
  /// edited, so a later change to the shared settings card stops cascading
  /// into it.
  final VoidCallback? onAnyFieldChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textStyles = Zeta.of(context).textStyles;
    final colors = Zeta.of(context).colors;
    final settings = ref.watch(simulatorSettingsProvider(backend));
    final capabilitiesAsync = ref.watch(simulatorCapabilitiesProvider);
    final runState = ref.watch(simulatorRunProvider(backend));
    final workspaceName = ref.watch(
      workspaceProvider.select((s) => s.workspaceName),
    );
    final gate = SimulatorRunGate.resolve(
      preflight: ref.watch(simulatorPreflightProvider),
      trainedNir: ref.watch(simulatorTrainedNirProvider(workspaceName)),
    );

    final bool preflightBlocking = gate.blocked;
    final String tooltipMessage = gate.message;

    void handleRun() => runSimulatorBackend(ref, backend);

    final availabilityWidget = capabilitiesAsync.when(
      loading: () => const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, _) => IconButton(
        icon: Icon(
          ZetaIcons.warning_outline,
          size: 14,
          color: NmtkShellTokens.of(context).warningColor,
        ),
        onPressed: () =>
            ref.read(simulatorCapabilitiesProvider.notifier).refresh(),
        tooltip: 'Could not load capabilities — tap to retry',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
      data: (caps) {
        final cap = caps.where((c) => c.backendName == backend).firstOrNull;
        if (cap == null) return const SizedBox.shrink();
        return SimulatorAvailabilityChip(capability: cap);
      },
    );

    final runButton = Tooltip(
      message: tooltipMessage,
      child: ZetaButton(
        size: ZetaWidgetSize.small,
        onPressed: switch (runState) {
          SimulatorRunLoading() => null,
          _ => preflightBlocking ? null : handleRun,
        },
        label: switch (runState) {
          SimulatorRunLoading() => 'Running…',
          _ => runButtonLabel ?? 'Run',
        },
        leadingIcon: switch (runState) {
          SimulatorRunLoading() => null,
          _ => ZetaIcons.play,
        },
      ),
    );

    final effectiveRun = switch (runState) {
      SimulatorRunLoading() => null,
      _ => preflightBlocking ? null : handleRun,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Runtime parameters',
          style: textStyles.labelSmall.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.mainSubtle,
          ),
        ),
        const SizedBox(height: 8),
        LabeledParameterGrid(
          children: [
            LabeledIntField(
              label: 'Timesteps',
              value: settings.timesteps,
              min: 1,
              max: 10000,
              onChanged: (v) {
                ref
                    .read(simulatorSettingsProvider(backend).notifier)
                    .setTimesteps(v);
                onAnyFieldChanged?.call();
              },
            ),
            LabeledIntField(
              label: 'Seed',
              value: settings.seed,
              min: 0,
              max: 2147483647,
              onChanged: (v) {
                ref
                    .read(simulatorSettingsProvider(backend).notifier)
                    .setSeed(v);
                onAnyFieldChanged?.call();
              },
            ),
            LabeledFloatField(
              label: 'Firing Rate',
              value: settings.firingRate,
              min: 0.01,
              max: 1.0,
              decimals: 2,
              onChanged: (v) {
                ref
                    .read(simulatorSettingsProvider(backend).notifier)
                    .setFiringRate(v);
                onAnyFieldChanged?.call();
              },
            ),
            LabeledFloatField(
              label: 'Raster time scale (ms/step)',
              value: settings.dtMs,
              min: 0.1,
              max: 100.0,
              decimals: 1,
              onChanged: (v) {
                ref
                    .read(simulatorSettingsProvider(backend).notifier)
                    .setDtMs(v);
                onAnyFieldChanged?.call();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (showRunButton) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              availabilityWidget,
              if (runState is SimulatorRunSuccess)
                SimulatorSupportLevelBadge(level: runState.result.supportLevel),
              if (mobileActionBuilder == null) runButton,
              if (runState is SimulatorRunSuccess ||
                  runState is SimulatorRunError)
                ZetaButton.text(
                  size: ZetaWidgetSize.small,
                  onPressed: () =>
                      ref.read(simulatorRunProvider(backend).notifier).reset(),
                  label: 'Clear',
                ),
            ],
          ),
          if (preflightBlocking && tooltipMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                tooltipMessage,
                style: textStyles.bodySmall.copyWith(
                  color: NmtkShellTokens.of(context).warningColor,
                ),
              ),
            ),
          if (mobileActionBuilder != null)
            mobileActionBuilder!(effectiveRun, runState is SimulatorRunLoading),
        ],
      ],
    );
  }
}

class _RuntimeSettings extends StatelessWidget {
  final int timesteps;
  final int seed;
  final double dtMs;
  final double firingRate;
  final ValueChanged<int> onTimestepsChanged;
  final ValueChanged<int> onSeedChanged;
  final ValueChanged<double> onDtMsChanged;
  final ValueChanged<double> onFiringRateChanged;

  const _RuntimeSettings({
    required this.timesteps,
    required this.seed,
    required this.dtMs,
    required this.firingRate,
    required this.onTimestepsChanged,
    required this.onSeedChanged,
    required this.onDtMsChanged,
    required this.onFiringRateChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Runtime Settings', style: theme.textTheme.labelSmall),
          const SizedBox(height: 4),
          LabeledParameterGrid(
            children: [
              LabeledIntField(
                label: 'Timesteps',
                value: timesteps,
                min: 1,
                max: 10000,
                onChanged: onTimestepsChanged,
              ),
              LabeledIntField(
                label: 'Seed',
                value: seed,
                min: 0,
                max: 2147483647,
                onChanged: onSeedChanged,
              ),
              LabeledFloatField(
                label: 'Firing Rate',
                value: firingRate,
                min: 0.01,
                max: 1.0,
                decimals: 2,
                onChanged: onFiringRateChanged,
              ),
              LabeledFloatField(
                label: 'Raster time scale (ms/step)',
                value: dtMs,
                min: 0.1,
                max: 100.0,
                decimals: 1,
                onChanged: onDtMsChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class LabeledIntField extends StatefulWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final double labelWidth;

  const LabeledIntField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.labelWidth = 140,
  });

  @override
  State<LabeledIntField> createState() => LabeledIntFieldState();
}

class LabeledIntFieldState extends State<LabeledIntField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(covariant LabeledIntField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _ctrl.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LabeledParameterRow(
      label: widget.label,
      labelWidth: widget.labelWidth,
      child: NmtkTextInput(
        controller: _ctrl,
        keyboardType: TextInputType.number,
        onChange: (v) {
          final parsed = int.tryParse(v ?? '');
          if (parsed != null && parsed >= widget.min && parsed <= widget.max) {
            widget.onChanged(parsed);
          }
        },
      ),
    );
  }
}

class LabeledFloatField extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int decimals;
  final ValueChanged<double> onChanged;
  final double labelWidth;

  const LabeledFloatField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.decimals,
    required this.onChanged,
    this.labelWidth = 140,
  });

  @override
  State<LabeledFloatField> createState() => LabeledFloatFieldState();
}

class LabeledFloatFieldState extends State<LabeledFloatField> {
  late final TextEditingController _ctrl;

  String _fmt(double v) => v.toStringAsFixed(widget.decimals);

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
  }

  @override
  void didUpdateWidget(covariant LabeledFloatField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _ctrl.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LabeledParameterRow(
      label: widget.label,
      labelWidth: widget.labelWidth,
      child: NmtkTextInput(
        controller: _ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChange: (v) {
          final parsed = double.tryParse(v ?? '');
          if (parsed != null && parsed >= widget.min && parsed <= widget.max) {
            widget.onChanged(parsed);
          }
        },
      ),
    );
  }
}

class _RunBar extends StatelessWidget {
  final SimulatorRunState runState;
  final SimulatorRunGate gate;
  final VoidCallback onRun;
  final VoidCallback onReset;

  const _RunBar({
    required this.runState,
    required this.gate,
    required this.onRun,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final runButton = Tooltip(
      message: gate.message,
      child: ZetaButton(
        onPressed: gate.blocked ? null : onRun,
        label: 'Run Simulation',
        leadingIcon: ZetaIcons.play,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: switch (runState) {
          SimulatorRunLoading() => [
            const ZetaButton(onPressed: null, label: 'Running…'),
            const Spacer(),
          ],
          SimulatorRunIdle() => [runButton, const Spacer()],
          SimulatorRunSuccess(:final result) => [
            runButton,
            const SizedBox(width: 8),
            ZetaButton.text(onPressed: onReset, label: 'Clear'),
            const Spacer(),
            _SupportLevelBadge(level: result.supportLevel),
          ],
          SimulatorRunError err => [
            runButton,
            const SizedBox(width: 8),
            ZetaButton.text(onPressed: onReset, label: 'Clear'),
            const Spacer(),
            Flexible(child: _ErrorSummaryButton(error: err)),
          ],
        },
      ),
    );
  }
}

class _ErrorSummaryButton extends StatelessWidget {
  final SimulatorRunError error;

  const _ErrorSummaryButton({required this.error});

  @override
  Widget build(BuildContext context) {
    return ZetaButton.text(
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Simulator Error'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(child: Text(_errorText(error))),
          ),
          actions: [
            ZetaButton.text(
              onPressed: () => Navigator.of(context).pop(),
              label: 'Close',
            ),
          ],
        ),
      ),
      leadingIcon: ZetaIcons.error_outline,
      label: error.message,
    );
  }
}

class _SimulatorErrorDetails extends StatelessWidget {
  final SimulatorRunError error;

  const _SimulatorErrorDetails({required this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      padding: const EdgeInsets.all(10),
      color: tokens.errorColor.withValues(alpha: 0.08),
      child: SingleChildScrollView(
        child: Text(
          _errorText(error),
          style: theme.textTheme.bodySmall?.copyWith(color: tokens.errorColor),
        ),
      ),
    );
  }
}

String _errorText(SimulatorRunError error) {
  final lines = <String>[
    if (error.statusCode != null) 'HTTP ${error.statusCode}',
    error.message,
    ...error.details.where((detail) => detail != error.message),
  ];
  return lines.join('\n');
}

class SimulatorSupportLevelBadge extends StatelessWidget {
  final SupportLevel level;

  const SimulatorSupportLevelBadge({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final (color, bg, icon) = switch (level) {
      SupportLevel.exact => (
        tokens.healthyColor,
        tokens.healthyColor.withValues(alpha: 0.10),
        ZetaIcons.check_circle_outline,
      ),
      SupportLevel.approximate => (
        tokens.degradedColor, // ZETA-MIGRATION-TODO: verify degraded vs warning
        tokens.degradedColor.withValues(alpha: 0.10),
        ZetaIcons.warning_outline,
      ),
      SupportLevel.unsupported => (
        tokens.errorColor,
        tokens.errorColor.withValues(alpha: 0.10),
        ZetaIcons.cancel_outline,
      ),
    };

    return Chip(
      avatar: Icon(icon, size: 12, color: color),
      label: Text(level.toDisplayLabel()),
      labelStyle: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: color),
      backgroundColor: bg,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

typedef _SupportLevelBadge = SimulatorSupportLevelBadge;

class _EmptyResultsPlaceholder extends StatelessWidget {
  const _EmptyResultsPlaceholder();

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bolt_outlined,
            size: 32,
            color: tokens.metadataForeground,
          ), // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
          const SizedBox(height: 8),
          Text(
            'Select a backend and click Run Simulation.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.metadataForeground),
          ),
        ],
      ),
    );
  }
}

/// Shown in the Deploy step in place of the result tabs once a run succeeds.
class _ResultsMovedToReviewNote extends StatelessWidget {
  const _ResultsMovedToReviewNote();

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ZetaIcons.analytics,
              size: 32,
              color: tokens.metadataForeground,
            ),
            const SizedBox(height: 8),
            Text(
              'Run finished — activity and report are in the Review step.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.metadataForeground),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Result tab widgets
// ---------------------------------------------------------------------------

/// Execution pane for simulator deploy targets: renders the preflight status
/// banner above the simulation results (empty placeholder, error details, or
/// Activity / Report tabs with spike rasters & potential dynamics).
class SimulatorExecutionPane extends ConsumerStatefulWidget {
  const SimulatorExecutionPane({
    super.key,
    required this.backend,
    this.showResults = true,
  });

  final String backend;
  final bool showResults;

  @override
  ConsumerState<SimulatorExecutionPane> createState() =>
      _SimulatorExecutionPaneState();
}

class _SimulatorExecutionPaneState extends ConsumerState<SimulatorExecutionPane>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // ── Deploy-path status pane (`!widget.showResults`) clock tracking ──────
  // The provider carries no wall-clock timing (`durationSeconds` on the
  // result is *simulated* time, not how long the run took to execute), so
  // "how long has this been running" / "when did it finish" are tracked
  // locally rather than added to the model for a Deploy-only display.
  DateTime? _runStartedAt;
  DateTime? _completedAt;
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _onRunStateChanged(SimulatorRunState? previous, SimulatorRunState next) {
    if (next is SimulatorRunLoading) {
      setState(() {
        _runStartedAt = DateTime.now();
        _completedAt = null;
      });
      _tickTimer?.cancel();
      // Ticks the elapsed-time readout while running; the provider itself
      // never emits an intermediate state to rebuild on.
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _tickTimer?.cancel();
      _tickTimer = null;
      if (next is SimulatorRunSuccess || next is SimulatorRunError) {
        setState(() => _completedAt = DateTime.now());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    ref.listen<SimulatorRunState>(
      simulatorRunProvider(widget.backend),
      _onRunStateChanged,
    );
    final runState = ref.watch(simulatorRunProvider(widget.backend));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PreflightResultWidget(),
        Expanded(
          child: switch (runState) {
            SimulatorRunIdle() =>
              widget.showResults
                  ? const _EmptyResultsPlaceholder()
                  : _DeployRunStatusPane(
                      status: const _DeployRunStatus.idle(),
                      backend: widget.backend,
                    ),
            SimulatorRunLoading() =>
              widget.showResults
                  ? const _EmptyResultsPlaceholder()
                  : _DeployRunStatusPane(
                      status: _DeployRunStatus.running(
                        startedAt: _runStartedAt,
                      ),
                      backend: widget.backend,
                    ),
            SimulatorRunError err => _SimulatorErrorDetails(error: err),
            SimulatorRunSuccess(:final result) =>
              widget.showResults
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TabBar(
                          controller: _tabController,
                          labelStyle: theme.textTheme.labelSmall,
                          tabs: const [
                            Tab(text: 'Activity'),
                            Tab(text: 'Report'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _ActivityTab(result: result),
                              _ReportTab(result: result),
                            ],
                          ),
                        ),
                      ],
                    )
                  : _DeployRunStatusPane(
                      status: _DeployRunStatus.done(
                        result: result,
                        completedAt: _completedAt,
                      ),
                      backend: widget.backend,
                    ),
          },
        ),
      ],
    );
  }
}

/// What [_DeployRunStatusPane] shows — one summary card that replaces the
/// Deploy step's old Activity/Report tabs (now Review-only) with just enough
/// to know what happened, not a second copy of Review's detail.
sealed class _DeployRunStatus {
  const _DeployRunStatus();

  const factory _DeployRunStatus.idle() = _DeployRunStatusIdle;
  const factory _DeployRunStatus.running({DateTime? startedAt}) =
      _DeployRunStatusRunning;
  const factory _DeployRunStatus.done({
    required SimulatorRunResult result,
    DateTime? completedAt,
  }) = _DeployRunStatusDone;
}

class _DeployRunStatusIdle extends _DeployRunStatus {
  const _DeployRunStatusIdle();
}

class _DeployRunStatusRunning extends _DeployRunStatus {
  const _DeployRunStatusRunning({this.startedAt});
  final DateTime? startedAt;
}

class _DeployRunStatusDone extends _DeployRunStatus {
  const _DeployRunStatusDone({required this.result, this.completedAt});
  final SimulatorRunResult result;
  final DateTime? completedAt;
}

/// Deploy step's replacement for the space the Activity/Report tabs used to
/// fill: not the charts (those are Review's job now), but enough to know
/// what will run, that it's running, and — once done — whether [backend]'s
/// run worked.
class _DeployRunStatusPane extends StatelessWidget {
  const _DeployRunStatusPane({required this.status, required this.backend});

  final _DeployRunStatus status;
  final String backend;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      _DeployRunStatusIdle() => _DeployRunStatusCard(
        leading: Icon(
          ZetaIcons.flash_on,
          size: 28,
          color: NmtkShellTokens.of(context).metadataForeground,
        ),
        title: 'Ready to run $backend',
        footer:
            'A short status shows here while it runs; the full activity '
            'and report open in the Review step.',
      ),
      _DeployRunStatusRunning(:final startedAt) => _DeployRunStatusCard(
        leading: const SizedBox(
          width: 20,
          height: 20,
          // ZETA-MIGRATION-EXEMPT: ZetaProgressCircle is determinate-only
          // (needs a 0.0-1.0 progress value) — there's no indeterminate-spin
          // equivalent for a simulator run of unknown length.
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: startedAt == null
            ? 'Running $backend…'
            : 'Running $backend… '
                  '${_formatElapsed(DateTime.now().difference(startedAt))}',
      ),
      _DeployRunStatusDone(:final result, :final completedAt) => _buildDone(
        context,
        result,
        completedAt,
      ),
    };
  }

  Widget _buildDone(
    BuildContext context,
    SimulatorRunResult result,
    DateTime? completedAt,
  ) {
    final tokens = NmtkShellTokens.of(context);
    final totalSpikes = result.spikes.values.fold<int>(
      0,
      (sum, population) =>
          sum + population.values.fold<int>(0, (s, ts) => s + ts.length),
    );
    // Same three-icon vocabulary as `_PreflightBadge` elsewhere in this file
    // (`_buildExact`/`_buildApproximate`/`_buildUnsupported`) — a failed or
    // caveated run must not show the same checkmark a completed one does.
    // `SimulatorOutcome` (models/simulator.dart) is the single source for
    // which statuses count as which bucket — the Deploy step's simulator
    // table classifies the exact same way.
    final statusLabel = result.status.outcomeLabel;
    final (statusColor, statusIcon) = switch (result.status.outcome) {
      SimulatorOutcome.success => (
        tokens.healthyColor,
        ZetaIcons.check_circle_outline,
      ),
      SimulatorOutcome.failure => (tokens.errorColor, ZetaIcons.cancel_outline),
      SimulatorOutcome.caveat => (
        tokens.warningColor,
        ZetaIcons.warning_outline,
      ),
    };

    return _DeployRunStatusCard(
      leading: _PreflightBadge(
        label: statusLabel,
        color: statusColor,
        icon: statusIcon,
      ),
      title: result.backendName,
      rows: [
        MapEntry('Duration', '${result.durationSeconds.toStringAsFixed(3)} s'),
        MapEntry('Total spikes', totalSpikes.toString()),
        if (completedAt != null) MapEntry('Ran at', _formatClock(completedAt)),
      ],
      footer: 'Full activity and the output report are in the Review step.',
    );
  }
}

/// Shared layout for all three [_DeployRunStatusPane] states — a leading
/// icon/badge, a headline, optional key/value facts, and a caption. One
/// shape instead of three near-identical trees keeps padding and width
/// consistent across state changes instead of visibly jumping between them.
class _DeployRunStatusCard extends StatelessWidget {
  const _DeployRunStatusCard({
    required this.leading,
    required this.title,
    this.rows = const [],
    this.footer,
  });

  final Widget leading;
  final String title;
  final List<MapEntry<String, String>> rows;
  final String? footer;

  // A readable card width, not the pane's full available width: the pane can
  // be roughly half the screen, but stretching a handful of key/value rows
  // across that width wouldn't read any better than a compact, centered card.
  static const _maxWidth = 360.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    return Align(
      // Top-anchored, not `Center`'d in the full pane height — the old
      // full-`Center` produced three lines of text floating dead-center in a
      // pane sized for the charts this replaced, reading as unfinished.
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: leading),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              if (rows.isNotEmpty) ...[
                const SizedBox(height: 16),
                for (final row in rows)
                  NmtkKeyValueRow(label: row.key, value: row.value),
              ],
              if (footer != null) ...[
                const SizedBox(height: 8),
                Text(
                  footer!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.metadataForeground,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Matches `akida_execution_pane.dart`'s `_elapsedLabel` format exactly
// (zero-padded seconds) so the two deploy panes' elapsed-time readouts agree.
String _formatElapsed(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  if (minutes == 0) return '${seconds}s';
  return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
}

String _formatClock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}:'
    '${t.second.toString().padLeft(2, '0')}';

/// The Activity/Report half of [SimulatorPanel], mountable on its own so the
/// Review step can show a finished run without the run controls.
class SimulatorResultsPanel extends ConsumerStatefulWidget {
  const SimulatorResultsPanel({super.key, required this.backend});

  final String backend;

  @override
  ConsumerState<SimulatorResultsPanel> createState() =>
      _SimulatorResultsPanelState();
}

class _SimulatorResultsPanelState extends ConsumerState<SimulatorResultsPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final runState = ref.watch(simulatorRunProvider(widget.backend));
    return switch (runState) {
      SimulatorRunSuccess(:final result) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabController,
            labelStyle: theme.textTheme.labelSmall,
            tabs: const [
              Tab(text: 'Activity'),
              Tab(text: 'Signals'),
              Tab(text: 'Report'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _ActivityTab(result: result),
                SimulatorSignalsTab(result: result),
                _ReportTab(result: result),
              ],
            ),
          ),
        ],
      ),
      SimulatorRunError err => _SimulatorErrorDetails(error: err),
      _ => const _EmptyResultsPlaceholder(),
    };
  }
}

class _ActivityTab extends StatefulWidget {
  final SimulatorRunResult result;

  const _ActivityTab({required this.result});

  @override
  State<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<_ActivityTab> {
  late String _selectedPopulation;

  List<String> get _populations {
    final names = <String>{};
    names.addAll(widget.result.spikes.keys);
    if (widget.result.voltages.isNotEmpty) {
      names.addAll(widget.result.voltages.keys);
    }
    final sorted = names.toList()..sort();
    return sorted;
  }

  @override
  void initState() {
    super.initState();
    _selectedPopulation = _populations.isNotEmpty ? _populations.first : '';
  }

  @override
  void didUpdateWidget(covariant _ActivityTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_populations.contains(_selectedPopulation) &&
        _populations.isNotEmpty) {
      _selectedPopulation = _populations.first;
    }
  }

  Map<String, List<double>> _spikesForPopulation() {
    final raw = widget.result.spikes[_selectedPopulation];
    if (raw == null) return {};
    // Spike times arrive as timesteps; the axis is milliseconds.
    final dtMs = resolveDtMs(widget.result.metadata);
    return raw.map((k, v) => MapEntry(k, v.map((t) => t * dtMs).toList()));
  }

  Map<String, List<double>>? _voltagesForPopulation() {
    final raw = widget.result.voltages[_selectedPopulation];
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  /// Why this run recorded nothing, in the run's own words.
  ///
  /// The backend already knows — it warns when every weight is zero, and again
  /// when a population stayed silent — but those lines used to sit in the Report
  /// tab while the Activity tab showed a bare "No spikes recorded." next to a
  /// flat trace, which reads like a broken chart rather than an untrained
  /// network.
  String? get _emptyReason {
    final lines = <String>[
      ...widget.result.warnings,
      if (widget.result.trainedWeights?.isAllZero == true)
        widget.result.trainedWeights!.detail,
    ];
    if (lines.isEmpty) return null;
    return 'No spikes recorded.\n\n${lines.join('\n\n')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_populations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _emptyReason ?? 'No populations recorded.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    final hasVoltages =
        widget.result.voltages[_selectedPopulation]?.isNotEmpty ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: Row(
            children: [
              Text(
                'Population:',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              DropdownButton<String>(
                value: _selectedPopulation,
                isDense: true,
                underline: const SizedBox.shrink(),
                style: theme.textTheme.bodySmall,
                items: _populations
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedPopulation = v);
                },
              ),
              const Spacer(),
              if (hasVoltages)
                const Icon(
                  ZetaIcons.chart_bar,
                  size: 14,
                  color: AppTheme.textSecondary,
                ),
            ],
          ),
        ),
        Expanded(
          // Key on population so AnimationController resets when switching.
          child: KeyedSubtree(
            key: ValueKey(_selectedPopulation),
            child: AnimatedSnnPlayback(
              spikes: _spikesForPopulation(),
              voltages: _voltagesForPopulation(),
              // Timesteps are not milliseconds. Every run returns `dt_ms`, but
              // this axis used to be labelled "ms" while counting steps, so any
              // run with dt_ms != 1.0 read its own clock wrong.
              duration: runDurationMs(
                widget.result.metadata,
                widget.result.timesteps,
              ),
              populationName: _selectedPopulation,
              emptyReason: _emptyReason,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReportTab extends StatelessWidget {
  final SimulatorRunResult result;

  const _ReportTab({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    final meta = result.metadata;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionHeader(theme, 'Output Summary'),
        _kv(theme, 'Backend', result.backendName),
        _kv(theme, 'Status', result.status.name),
        _kv(theme, 'Support level', result.supportLevel.toDisplayLabel()),
        _kv(theme, 'Timesteps', result.timesteps.toString()),
        _kv(
          theme,
          'Duration',
          '${result.durationSeconds.toStringAsFixed(3)} s',
        ),
        _kv(theme, 'NIR nodes', result.nirSummary.nodeCount.toString()),
        _kv(theme, 'NIR edges', result.nirSummary.edgeCount.toString()),
        if (meta['seed'] != null) _kv(theme, 'Seed', meta['seed'].toString()),
        if (meta['dt_ms'] != null)
          _kv(theme, 'Raster time scale (ms/step)', meta['dt_ms'].toString()),
        if (meta['firing_rate'] != null)
          _kv(theme, 'Firing rate', meta['firing_rate'].toString()),
        if (meta['stimulus_population'] != null)
          _kv(
            theme,
            'Stimulus population',
            meta['stimulus_population'].toString(),
          ),
        if (result.spikes.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Spikes per population',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          for (final entry in result.spikes.entries)
            _kv(
              theme,
              entry.key,
              '${entry.value.values.fold(0, (s, ts) => s + ts.length)} total spikes',
            ),
        ],
        const Divider(height: 24),
        _sectionHeader(theme, 'Warnings'),
        if (result.warnings.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('No warnings.', style: theme.textTheme.bodyMedium),
          )
        else
          ...List.generate(result.warnings.length, (i) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 6),
                    child: Icon(
                      ZetaIcons.warning_outline,
                      size: 14,
                      color: tokens.warningColor,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      result.warnings[i],
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            );
          }),
        const Divider(height: 24),
        _sectionHeader(theme, 'NIR Support'),
        Text(
          '${result.nirSummary.nodeCount} nodes · ${result.nirSummary.edgeCount} edges',
          style: theme.textTheme.bodyMedium,
        ),
        if (result.nirSummary.unsupportedNodes.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Unsupported node types',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          for (final n in result.nirSummary.unsupportedNodes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(ZetaIcons.block, size: 12, color: tokens.errorColor),
                  const SizedBox(width: 4),
                  Text('nir.$n', style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
        ],
        const SizedBox(height: 4),
        Text(
          'Support level: ${result.supportLevel.toDisplayLabel()}',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }

  static Widget _sectionHeader(ThemeData theme, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static Widget _kv(ThemeData theme, String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              key,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact toolbar (deploy-pane context only)
// ---------------------------------------------------------------------------

/// A single-row toolbar combining availability status, timestep/seed inputs,
/// and the run button.  Used when [SimulatorPanel.initialBackend] is set so
/// the deploy pane doesn't waste vertical space on a multi-row header.
class _CompactToolbar extends ConsumerWidget {
  final String selectedBackend;
  final AsyncValue<List<SimulatorCapability>> capabilitiesAsync;
  final int timesteps;
  final int seed;
  final double dtMs;
  final double firingRate;
  final SimulatorRunState runState;
  final SimulatorRunGate gate;
  final ValueChanged<int> onTimestepsChanged;
  final ValueChanged<int> onSeedChanged;
  final ValueChanged<double> onDtMsChanged;
  final ValueChanged<double> onFiringRateChanged;
  final VoidCallback onRun;
  final VoidCallback onReset;
  final VoidCallback onRefreshCapabilities;
  final Widget Function(VoidCallback? onRun, bool isRunning)?
  mobileActionBuilder;

  const _CompactToolbar({
    required this.selectedBackend,
    required this.capabilitiesAsync,
    required this.timesteps,
    required this.seed,
    required this.dtMs,
    required this.firingRate,
    required this.runState,
    required this.gate,
    required this.onTimestepsChanged,
    required this.onSeedChanged,
    required this.onDtMsChanged,
    required this.onFiringRateChanged,
    required this.onRun,
    required this.onReset,
    required this.onRefreshCapabilities,
    this.mobileActionBuilder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Requirements 8.1–8.4 — the preflight gate, and the trained-weights
    // gate, both resolved by [SimulatorRunGate] so this toolbar and the full
    // panel's run bar cannot disagree about whether Run is available.
    final bool preflightBlocking = gate.blocked;
    final String tooltipMessage = gate.message;

    final availabilityWidget = capabilitiesAsync.when(
      loading: () => const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, _) => IconButton(
        icon: Icon(
          ZetaIcons.warning_outline,
          size: 14,
          color: NmtkShellTokens.of(context).warningColor,
        ),
        onPressed: onRefreshCapabilities,
        tooltip: 'Could not load capabilities — tap to retry',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
      data: (caps) {
        final cap = caps
            .where((c) => c.backendName == selectedBackend)
            .firstOrNull;
        if (cap == null) return const SizedBox.shrink();
        return _AvailabilityChip(capability: cap);
      },
    );

    final runButton = Tooltip(
      message: tooltipMessage,
      child: ZetaButton(
        size: ZetaWidgetSize.small,
        onPressed: switch (runState) {
          SimulatorRunLoading() => null,
          _ => preflightBlocking ? null : onRun,
        },
        label: switch (runState) {
          SimulatorRunLoading() => 'Running\u2026',
          _ => 'Run',
        },
        leadingIcon: switch (runState) {
          SimulatorRunLoading() => null,
          _ => ZetaIcons.play,
        },
      ),
    );
    final effectiveRun = switch (runState) {
      SimulatorRunLoading() => null,
      _ => preflightBlocking ? null : onRun,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top row: backend readiness status + result badge + Run / Clear.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left anchor: backend readiness status
              availabilityWidget,
              const Spacer(),
              // Fixed-width badge slot so Run never jumps when state changes.
              SizedBox(
                width: 116,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: switch (runState) {
                    SimulatorRunSuccess(:final result) => _SupportLevelBadge(
                      level: result.supportLevel,
                    ),
                    _ => null,
                  },
                ),
              ),
              const SizedBox(width: 8),
              if (mobileActionBuilder == null) runButton,
              // Clear — always takes the same space; invisible until there's
              // something to clear, so the Run button never jumps.
              Visibility(
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                visible: switch (runState) {
                  SimulatorRunSuccess() || SimulatorRunError() => true,
                  _ => false,
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 6),
                    ZetaButton.text(
                      size: ZetaWidgetSize.small,
                      onPressed: switch (runState) {
                        SimulatorRunSuccess() || SimulatorRunError() => onReset,
                        _ => null,
                      },
                      label: 'Clear',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Bottom row: simulation parameter text fields.
          LabeledParameterGrid(
            children: [
              LabeledIntField(
                label: 'Timesteps',
                value: timesteps,
                min: 1,
                max: 10000,
                onChanged: onTimestepsChanged,
              ),
              LabeledIntField(
                label: 'Seed',
                value: seed,
                min: 0,
                max: 2147483647,
                onChanged: onSeedChanged,
              ),
              LabeledFloatField(
                label: 'Firing Rate',
                value: firingRate,
                min: 0.01,
                max: 1.0,
                decimals: 2,
                onChanged: onFiringRateChanged,
              ),
              LabeledFloatField(
                label: 'Raster time scale (ms/step)',
                value: dtMs,
                min: 0.1,
                max: 100.0,
                decimals: 1,
                onChanged: onDtMsChanged,
              ),
            ],
          ),
          if (mobileActionBuilder != null)
            mobileActionBuilder!(effectiveRun, runState is SimulatorRunLoading),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Playback tab
// ---------------------------------------------------------------------------

/// Animated playback tab showing a time-sweeping cursor over the simulation
/// data for a selected population.  Uses [AnimatedSnnPlayback] which provides
/// play/pause controls, speed selector, and a scrubber.
// ---------------------------------------------------------------------------
// Preflight result widget (task 5.1 — not yet inserted into layout)
// ---------------------------------------------------------------------------

/// Reads [simulatorPreflightProvider] and renders the appropriate preflight
/// state in the compact Deploy-pane layout.
///
/// States:
/// - **idle** → [SizedBox.shrink] (region absent, not blank).
/// - **running** → compact spinner row with "Checking compatibility…" label.
/// - **success / exact** → green badge + supported-node list.
/// - **success / approximate** → amber badge + approximate-node list (caution)
///   + supported-node list.
/// - **success / unsupported** → red badge + unsupported-node list with
///   diagnostics + optional supported / approximate lists + override toggle.
/// - **error** → red icon + error message text.
///
/// Uses [NmtkShellTokens] for status colours and 12 px compact padding
/// throughout (Requirements 7.1–7.6, 8.5).
class _PreflightResultWidget extends ConsumerWidget {
  const _PreflightResultWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preflight = ref.watch(simulatorPreflightProvider);
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);

    switch (preflight.status) {
      case SimulatorPreflightStatus.idle:
        return const SizedBox.shrink();

      case SimulatorPreflightStatus.running:
        // Requirement 7.1 — compact spinner row.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                'Checking compatibility\u2026',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        );

      case SimulatorPreflightStatus.success:
        final level = preflight.level ?? '';
        return switch (level) {
          'exact' => _buildExact(context, preflight),
          'approximate' => _buildApproximate(context, preflight),
          'unsupported' => _buildUnsupported(context, preflight, ref, tokens),
          _ => const SizedBox.shrink(),
        };

      case SimulatorPreflightStatus.error:
        // Requirement 7.5 — inline error, run button area stays visible.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                ZetaIcons.error_outline,
                size: 14,
                color: AppTheme.errorColorOf(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  preflight.errorMessage ?? 'Preflight error',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.errorColorOf(context),
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }

  // ── exact ───────────────────────────────────────────────────────────────

  /// Requirement 7.2 — green badge only when fully supported; node list is
  /// available on demand in the NIR Support tab.
  Widget _buildExact(BuildContext context, SimulatorPreflightState preflight) {
    final tokens = NmtkShellTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: _PreflightBadge(
        label: 'Fully supported',
        color: tokens.healthyColor,
        icon: ZetaIcons.check_circle_outline,
      ),
    );
  }

  // ── approximate ─────────────────────────────────────────────────────────

  /// Requirement 7.3 — amber badge + approximate-node list (caution)
  /// + supported-node list.
  Widget _buildApproximate(
    BuildContext context,
    SimulatorPreflightState preflight,
  ) {
    final tokens = NmtkShellTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PreflightBadge(
            label: 'Approximate',
            color: tokens.warningColor,
            icon: ZetaIcons.warning_outline,
          ),
          if (preflight.approximateNodes.isNotEmpty) ...[
            const SizedBox(height: 6),
            _NodeList(
              title: 'Approximate',
              nodes: preflight.approximateNodes,
              caution: true,
            ),
          ],
          if (preflight.supportedNodes.isNotEmpty) ...[
            const SizedBox(height: 4),
            _NodeList(title: 'Supported', nodes: preflight.supportedNodes),
          ],
        ],
      ),
    );
  }

  // ── unsupported ─────────────────────────────────────────────────────────

  /// Requirement 7.4 — red badge + unsupported-node list with diagnostics
  /// + optional supported / approximate lists + override toggle (Req. 8.5).
  Widget _buildUnsupported(
    BuildContext context,
    SimulatorPreflightState preflight,
    WidgetRef ref,
    NmtkShellTokens tokens,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PreflightBadge(
            label: 'Unsupported',
            color: tokens.errorColor,
            icon: ZetaIcons.cancel_outline,
          ),
          if (preflight.unsupportedNodes.isNotEmpty) ...[
            const SizedBox(height: 6),
            _NodeList(
              title: 'Unsupported',
              nodes: preflight.unsupportedNodes,
              diagnostics: preflight.diagnostics,
            ),
          ],
          if (preflight.supportedNodes.isNotEmpty) ...[
            const SizedBox(height: 4),
            _NodeList(title: 'Supported', nodes: preflight.supportedNodes),
          ],
          if (preflight.approximateNodes.isNotEmpty) ...[
            const SizedBox(height: 4),
            _NodeList(
              title: 'Approximate',
              nodes: preflight.approximateNodes,
              caution: true,
            ),
          ],
          const SizedBox(height: 8),
          _OverrideToggle(
            active: preflight.overrideMode,
            onChanged: (v) => ref
                .read(simulatorPreflightProvider.notifier)
                .setOverrideMode(v),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PreflightBadge — coloured status pill (Requirements 7.2, 7.3, 7.4)
// ---------------------------------------------------------------------------

/// A compact pill-shaped status badge that visually communicates the overall
/// preflight classification result.  Uses [NmtkShellTokens.chipRadius] (999)
/// for the pill shape per the design-system border-radius rules.
class _PreflightBadge extends StatelessWidget {
  const _PreflightBadge({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // chipRadius (999) is the sanctioned value for pill badges per
    // CODING_STYLE_GUIDE.md § Border radius.
    const chipRadius = 999.0;
    final bg = color.withValues(alpha: 0.12);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _NodeList — labelled list of NIR node type names (Requirements 7.2–7.4)
// ---------------------------------------------------------------------------

/// Renders a titled list of NIR node-type names.
///
/// When [caution] is `true`, each row shows an amber warning icon (used for
/// approximate-mode node lists per Requirement 7.3).
///
/// When [diagnostics] is non-empty, each node row shows its diagnostic
/// message below the node name (used for unsupported-mode lists per
/// Requirement 7.4).  Diagnostics are matched positionally to [nodes]; any
/// extra diagnostics beyond the node count are shown as a trailing group.
class _NodeList extends StatelessWidget {
  const _NodeList({
    required this.title,
    required this.nodes,
    this.caution = false,
    this.diagnostics = const [],
  });

  final String title;
  final List<String> nodes;

  /// When true renders amber caution icons instead of the default bullet.
  final bool caution;

  /// Optional per-node (or trailing) diagnostic messages.
  final List<String> diagnostics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        for (int i = 0; i < nodes.length; i++) ...[
          _NodeRow(
            name: nodes[i],
            caution: caution,
            diagnostic: i < diagnostics.length ? diagnostics[i] : null,
          ),
        ],
        // Any diagnostics that exceed the node count are shown as-is.
        if (diagnostics.length > nodes.length)
          for (int i = nodes.length; i < diagnostics.length; i++)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 2),
              child: Text(
                diagnostics[i],
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 10,
                ),
              ),
            ),
      ],
    );
  }
}

/// A single row in a [_NodeList]: leading icon + node name + optional
/// diagnostic sub-text.
class _NodeRow extends StatelessWidget {
  const _NodeRow({required this.name, required this.caution, this.diagnostic});

  final String name;
  final bool caution;
  final String? diagnostic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = caution
        ? NmtkShellTokens.of(context).warningColor
        : AppTheme.textSecondary;
    final icon = caution
        ? ZetaIcons.warning_outline
        : ZetaIcons.radio_button_checked;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: caution ? 12 : 6, color: iconColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text('nir.$name', style: theme.textTheme.bodySmall),
              ),
            ],
          ),
          if (diagnostic != null)
            Padding(
              padding: const EdgeInsets.only(left: 18, top: 1),
              child: Text(
                diagnostic!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _OverrideToggle — re-enable Run for unsupported graphs (Requirement 8.5)
// ---------------------------------------------------------------------------

/// A compact row with a [Switch] that lets the user acknowledge an
/// `unsupported` preflight result and re-enable the Run button.
///
/// When [active] is `true` an amber "Override active" label is shown to give
/// a persistent visual signal that the safeguard has been bypassed.
class _OverrideToggle extends StatelessWidget {
  const _OverrideToggle({required this.active, required this.onChanged});

  final bool active;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.warningColor.withValues(alpha: 0.08),
        border: Border.all(color: tokens.warningColor.withValues(alpha: 0.30)),
        // radiusSm (12) is the sanctioned value for inline/compact containers
        // per CODING_STYLE_GUIDE.md § Border radius.
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Override \u2014 run anyway',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: tokens.warningColor,
                  ),
                ),
                if (active)
                  Text(
                    'Override active',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.warningColor,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: active,
            onChanged: onChanged,
            activeThumbColor: tokens.warningColor,
          ),
        ],
      ),
    );
  }
}
