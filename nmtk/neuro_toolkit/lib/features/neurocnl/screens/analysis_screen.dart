import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart' hide AppTheme;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/analysis_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/host_module_navigation.dart';
import 'package:neuro_toolkit/features/neurocnl/services/platform_helper.dart' as platform;
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/energy_bar_chart.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/quantization_curve_chart.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/loading_shimmer.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/ownership_boundary_card.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/shell_surface.dart';

/// Analysis screen with Energy Profiling, Quantization, and Fault Injection tabs.
class AnalysisScreen extends ConsumerWidget {
  const AnalysisScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const content = DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.bolt, size: 18),
                text: 'Energy',
              ), // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
              Tab(
                icon: Icon(Icons.compress, size: 18),
                text: 'Quantization',
              ), // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
              Tab(
                icon: Icon(
                  Icons.bug_report,
                  size: 18,
                ), // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                text: 'Fault Injection',
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _EnergyTab(),
                _QuantizationTab(),
                _FaultInjectionTab(),
              ],
            ),
          ),
        ],
      ),
    );

    if (embedded) {
      return content;
    }

    return const Column(
      children: [
        NeurocnlScreenHeader(
          eyebrow: 'Diagnostics',
          title: 'Analysis',
          subtitle:
              'Review energy, quantization, and fault diagnostics inside the Studio workflow shell.',
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _AnalysisOwnershipCard(),
        ),
        Expanded(child: content),
      ],
    );
  }
}

class _AnalysisOwnershipCard extends ConsumerWidget {
  const _AnalysisOwnershipCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTarget = ref.watch(
      workspaceProvider.select((workspace) => workspace.selectedDeployTarget),
    );
    final neurochipTarget = StudioNeurochipHandoffContract.fromStudioTargetId(
      selectedTarget,
    );

    return NeurocnlOwnershipBoundaryCard(
      summary:
          'Use Analysis for pre-handoff review inside Studio. Execution-specific diagnostics and runtime verification continue in Neurochip after target selection.',
      details: const [
        'Keep energy, quantization, and fault results here focused on authoring-stage readiness rather than target runtime behavior.',
      ],
      actions: ZetaButton.outline(
        onPressed: () => _openNeurochipExecution(context, neurochipTarget),
        leadingIcon: ZetaIcons.open_in_new_window,
        label: 'Open ${neurochipTarget.targetLabel} diagnostics in Neurochip',
      ),
    );
  }

  Future<void> _openNeurochipExecution(
    BuildContext context,
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

    if (!context.mounted || opened) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      NmtkSnackBars.error(
        context,
        'Could not open Neurochip automatically from this workspace.',
      ),
    );
  }
}

// ─── Energy Profiling Tab ────────────────────────────────────────────────────

class _EnergyTab extends ConsumerWidget {
  const _EnergyTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysis = ref.watch(analysisProvider);
    final spec = ref.watch(specTextProvider);
    final isLoading = analysis.energyStatus == AnalysisStatus.loading;

    return _AnalysisTabScrollLayout(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ZetaButton(
            onPressed: isLoading || spec.isEmpty
                ? null
                : () => ref
                      .read(analysisProvider.notifier)
                      .runEnergyProfile(spec),
            label: isLoading ? 'Running…' : 'Run Energy Profile',
            leadingIcon: isLoading ? null : ZetaIcons.play,
          ),
          if (spec.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Load a spec in the Studio tab first.',
              style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                color: Zeta.of(context).colors.mainSubtle,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          _buildResults(context, analysis),
        ],
      ),
    );
  }

  Widget _buildResults(BuildContext context, AnalysisState analysis) {
    if (analysis.energyStatus == AnalysisStatus.loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: LoadingShimmer.panel(height: 300),
      );
    }
    if (analysis.energyStatus == AnalysisStatus.error) {
      final errorColor = Zeta.of(context).colors.mainNegative;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ZetaIcons.error_outline, size: 48, color: errorColor),
            const SizedBox(height: 8),
            Text(
              analysis.energyError ?? 'Unknown error',
              style: Zeta.of(
                context,
              ).textStyles.bodyMedium.copyWith(color: errorColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    if (analysis.energyReport != null) {
      return EnergyBarChart(report: analysis.energyReport!);
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bolt,
            size: 48,
            color: Zeta.of(context).colors.mainSubtle,
          ), // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
          const SizedBox(height: 8),
          Text(
            'Run energy profiling to see per-ensemble\nenergy consumption.',
            style: Zeta.of(context).textStyles.bodyMedium.copyWith(
              color: Zeta.of(context).colors.mainSubtle,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Quantization Tab ────────────────────────────────────────────────────────

class _QuantizationTab extends ConsumerStatefulWidget {
  const _QuantizationTab();

  @override
  ConsumerState<_QuantizationTab> createState() => _QuantizationTabState();
}

class _QuantizationTabState extends ConsumerState<_QuantizationTab> {
  final Map<int, bool> _selectedBits = {4: true, 6: true, 8: true};

  @override
  Widget build(BuildContext context) {
    final analysis = ref.watch(analysisProvider);
    final spec = ref.watch(specTextProvider);
    final isLoading = analysis.quantizationStatus == AnalysisStatus.loading;
    final enabledBits =
        _selectedBits.entries.where((e) => e.value).map((e) => e.key).toList()
          ..sort();

    return _AnalysisTabScrollLayout(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(
                NmtkShellTokens.of(context).radiusSm,
              ),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Text(
                  'Bit widths:',
                  style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                    color: Zeta.of(context).colors.mainSubtle,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 12),
                for (final bits in [4, 6, 8]) ...[
                  FilterChip(
                    label: Text('$bits-bit'),
                    selected: _selectedBits[bits]!,
                    onSelected: (v) => setState(() => _selectedBits[bits] = v),
                    selectedColor: AppTheme.primaryDim.withValues(alpha: 0.3),
                    checkmarkColor: Zeta.of(context).colors.mainPrimary,
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          ZetaButton(
            onPressed: isLoading || spec.isEmpty || enabledBits.isEmpty
                ? null
                : () => ref
                      .read(analysisProvider.notifier)
                      .runQuantization(spec, enabledBits),
            label: isLoading ? 'Running…' : 'Run Analysis',
            leadingIcon: isLoading ? null : ZetaIcons.play,
          ),
          const SizedBox(height: 16),
          _buildResults(analysis),
        ],
      ),
    );
  }

  Widget _buildResults(AnalysisState analysis) {
    if (analysis.quantizationStatus == AnalysisStatus.loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: LoadingShimmer.panel(height: 300),
      );
    }
    if (analysis.quantizationStatus == AnalysisStatus.error) {
      final errorColor = Zeta.of(context).colors.mainNegative;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ZetaIcons.error_outline, size: 48, color: errorColor),
            const SizedBox(height: 8),
            Text(
              analysis.quantizationError ?? 'Unknown error',
              style: Zeta.of(
                context,
              ).textStyles.bodyMedium.copyWith(color: errorColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    if (analysis.quantizationReport != null) {
      return SingleChildScrollView(
        child: QuantizationCurveChart(report: analysis.quantizationReport!),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.compress, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
            size: 48,
            color: Zeta.of(context).colors.mainSubtle,
          ),
          const SizedBox(height: 8),
          Text(
            'Select bit widths and run analysis to see\naccuracy and sparsity trade-offs.',
            style: Zeta.of(context).textStyles.bodyMedium.copyWith(
              color: Zeta.of(context).colors.mainSubtle,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Fault Injection Tab ─────────────────────────────────────────────────────

class _FaultInjectionTab extends ConsumerStatefulWidget {
  const _FaultInjectionTab();

  @override
  ConsumerState<_FaultInjectionTab> createState() => _FaultInjectionTabState();
}

class _FaultInjectionTabState extends ConsumerState<_FaultInjectionTab> {
  double _errorRate = 0.1;

  @override
  Widget build(BuildContext context) {
    final analysis = ref.watch(analysisProvider);
    final spec = ref.watch(specTextProvider);
    final isLoading = analysis.faultInjectionStatus == AnalysisStatus.loading;

    return _AnalysisTabScrollLayout(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(
                NmtkShellTokens.of(context).radiusSm,
              ),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Error Rate:',
                      style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                        color: Zeta.of(context).colors.mainSubtle,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${(_errorRate * 100).toStringAsFixed(0)}%',
                      style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                        color: Zeta.of(context).colors.mainDefault,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _errorRate,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  label: '${(_errorRate * 100).toStringAsFixed(0)}%',
                  activeColor: Zeta.of(context).colors.mainPrimary,
                  inactiveColor: AppTheme.border,
                  onChanged: isLoading
                      ? null
                      : (v) => setState(() => _errorRate = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ZetaButton(
            onPressed: isLoading || spec.isEmpty
                ? null
                : () => ref
                      .read(analysisProvider.notifier)
                      .runFaultInjection(spec, _errorRate),
            label: isLoading ? 'Running…' : 'Run Fault Injection',
            leadingIcon: isLoading ? null : ZetaIcons.play,
          ),
          if (spec.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Load a spec in the Studio tab first.',
              style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                color: Zeta.of(context).colors.mainSubtle,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          _buildResults(analysis),
        ],
      ),
    );
  }

  Widget _buildResults(AnalysisState analysis) {
    if (analysis.faultInjectionStatus == AnalysisStatus.loading) {
      return SingleChildScrollView(child: LoadingShimmer.panel(height: 300));
    }
    if (analysis.faultInjectionStatus == AnalysisStatus.error) {
      final errorColor = Zeta.of(context).colors.mainNegative;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ZetaIcons.error_outline, size: 48, color: errorColor),
            const SizedBox(height: 8),
            Text(
              analysis.faultInjectionError ?? 'Unknown error',
              style: Zeta.of(
                context,
              ).textStyles.bodyMedium.copyWith(color: errorColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    if (analysis.faultInjectionReport != null) {
      final report = analysis.faultInjectionReport!;
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _ResultCard(
                    title: 'Baseline Accuracy',
                    value:
                        '${(report.baselineAccuracy * 100).toStringAsFixed(1)}%',
                    icon: ZetaIcons.check_circle_outline,
                    color: Zeta.of(context).colors.mainPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ResultCard(
                    title: 'Degraded Accuracy',
                    value:
                        '${(report.degradedAccuracy * 100).toStringAsFixed(1)}%',
                    icon: ZetaIcons.warning_outline,
                    color: AppTheme.edgeInhibitory,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ResultCard(
              title: 'Resilience Score',
              value: '${(report.resilienceScore * 100).toStringAsFixed(1)}%',
              icon: Icons
                  .shield_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
              color: AppTheme.edgeExcitatory,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed Nodes',
              style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                color: Zeta.of(context).colors.mainDefault,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            if (report.failedNodes.isEmpty)
              Text(
                'No nodes failed.',
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                  color: Zeta.of(context).colors.mainSubtle,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: report.failedNodes
                    .map(
                      (node) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Text(
                          node,
                          style: Zeta.of(context).textStyles.bodyMedium
                              .copyWith(
                                color: Zeta.of(context).colors.mainDefault,
                                fontSize: 13,
                              ),
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bug_report, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
            size: 48,
            color: Zeta.of(context).colors.mainSubtle,
          ),
          const SizedBox(height: 8),
          Text(
            'Set an error rate and run analysis to measure\nnetwork resilience under fault conditions.',
            style: Zeta.of(context).textStyles.bodyMedium.copyWith(
              color: Zeta.of(context).colors.mainSubtle,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _ResultCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(
          NmtkShellTokens.of(context).radiusSm,
        ),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                    color: Zeta.of(context).colors.mainSubtle,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: Zeta.of(context).textStyles.bodyMedium.copyWith(
              color: Zeta.of(context).colors.mainDefault,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisTabScrollLayout extends StatelessWidget {
  const _AnalysisTabScrollLayout({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        );
      },
    );
  }
}
