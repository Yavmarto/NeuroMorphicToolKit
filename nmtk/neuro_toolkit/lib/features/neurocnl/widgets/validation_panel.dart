import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/deploy_readiness_result.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/workspace_file.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';

typedef ValidationPanelSnapshot = ({
  ParseResult? parseResult,
  StepStatus parseStatus,
  ValidationResult? validationResult,
  ValidationFocus? focus,
  StepStatus deployReadinessStatus,
  DeployReadinessResult? deployReadinessResult,
  String selectedDeployTarget,
  bool overallReady,
  bool deployReadinessFailed,
});

final validationPanelSnapshotProvider = Provider<ValidationPanelSnapshot>((
  ref,
) {
  final parseResult = ref.watch(pipelineProvider.select((p) => p.parseResult));
  final parseStatus = ref.watch(pipelineProvider.select((p) => p.parseStatus));
  final validationResult = ref.watch(
    pipelineProvider.select((p) => p.validateResult),
  );
  final focus = ref.watch(
    workspaceProvider.select((state) => state.validationFocus),
  );
  final deployReadinessStatus = ref.watch(
    pipelineProvider.select((p) => p.deployReadinessStatus),
  );
  final deployReadinessResult = ref.watch(
    pipelineProvider.select((p) => p.deployReadinessResult),
  );
  final selectedDeployTarget = ref.watch(
    workspaceProvider.select((state) => state.selectedDeployTarget),
  );
  final overallReady = ref.watch(
    pipelineProvider.select((p) => p.overallReady),
  );
  final deployReadinessFailed = ref.watch(
    pipelineProvider.select((p) => p.deployReadinessFailed),
  );
  return (
    parseResult: parseResult,
    parseStatus: parseStatus,
    validationResult: validationResult,
    focus: focus,
    deployReadinessStatus: deployReadinessStatus,
    deployReadinessResult: deployReadinessResult,
    selectedDeployTarget: selectedDeployTarget,
    overallReady: overallReady,
    deployReadinessFailed: deployReadinessFailed,
  );
});

class ValidationPanel extends ConsumerStatefulWidget {
  const ValidationPanel({super.key});

  @override
  ConsumerState<ValidationPanel> createState() => _ValidationPanelState();
}

class _ValidationPanelState extends ConsumerState<ValidationPanel> {
  final Map<String, GlobalKey> _focusKeys = <String, GlobalKey>{};

  GlobalKey _keyFor(String id) {
    return _focusKeys.putIfAbsent(id, () => GlobalKey(debugLabel: id));
  }

  void _ensureVisible(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _focusKeys[id]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(workspaceProvider.select((state) => state.validationFocus), (
      _,
      next,
    ) {
      if (next == null) {
        return;
      }
      _ensureVisible(
        next.itemId == null ? next.section : '${next.section}:${next.itemId}',
      );
    });

    final snapshot = ref.watch(validationPanelSnapshotProvider);
    final parseResult = snapshot.parseResult;
    final parseStatus = snapshot.parseStatus;
    final validationResult = snapshot.validationResult;
    final l10n = AppLocalizations.of(context)!;
    final focus = snapshot.focus;
    final deployReadinessStatus = snapshot.deployReadinessStatus;
    final deployReadinessResult = snapshot.deployReadinessResult;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (validationResult != null) ...[
            _SelectableContainer(
              key: _keyFor('overall'),
              selected: focus?.section == 'overall',
              onTap: () => ref
                  .read(workspaceProvider.notifier)
                  .setValidationFocus('overall'),
              child: _OverallStatus(
                overall: snapshot.overallReady,
                parseHasErrors: (parseResult?.errors ?? 0) > 0,
                layer1Failed: !validationResult.layer1.overall,
                layer2Failed: !validationResult.layer2.overall,
                deployReadinessFailed: snapshot.deployReadinessFailed,
              ),
            ),
            const SizedBox(height: 16),
            if (validationResult.backendSupport?.verdict == 'unsupported') ...[
              _BackendSupportBanner(
                backendSupport: validationResult.backendSupport!,
              ),
              const SizedBox(height: 16),
            ],
            if (deployReadinessStatus != StepStatus.idle) ...[
              _SelectableContainer(
                key: _keyFor('deploy-readiness'),
                selected: focus?.section == 'deploy-readiness',
                onTap: () => ref
                    .read(workspaceProvider.notifier)
                    .setValidationFocus('deploy-readiness'),
                child: _DeployReadinessSection(
                  status: deployReadinessStatus,
                  result: deployReadinessResult,
                  target: snapshot.selectedDeployTarget,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],
          ZetaAccordion(
            inCard: false,
            expandMultiple: true,
            children: [
              ZetaAccordionItem(
                key: _keyFor('parsing'),
                title: _parsingTitle(parseResult),
                isExpanded: false,
                child: _ParsingBody(
                  parseStatus: parseStatus,
                  parseResult: parseResult,
                ),
              ),
              if (validationResult != null) ...[
                ZetaAccordionItem(
                  key: _keyFor('layer1'),
                  title:
                      '${l10n.layer1}'
                      ' — ${validationResult.layer1.passed.length}'
                      '/${validationResult.layer1.passed.length + validationResult.layer1.failed.length}',
                  isExpanded: false,
                  child: _Layer1Body(
                    result: validationResult.layer1,
                    focus: focus,
                    onFocus: (itemId) => ref
                        .read(workspaceProvider.notifier)
                        .setValidationFocus('layer1', itemId: itemId),
                  ),
                ),
                ZetaAccordionItem(
                  key: _keyFor('layer2'),
                  title:
                      '${l10n.layer2}'
                      ' — ${validationResult.layer2.checksPassed.length}'
                      '/${validationResult.layer2.checksPassed.length + validationResult.layer2.checksFailed.length}',
                  isExpanded: false,
                  child: _Layer2Body(
                    result: validationResult.layer2,
                    focus: focus,
                    onFocus: (itemId) => ref
                        .read(workspaceProvider.notifier)
                        .setValidationFocus('layer2', itemId: itemId),
                    neuronsLabel: l10n.neuronsFound,
                  ),
                ),
              ],
            ],
          ),
          if (validationResult == null)
            const _ValidationSectionNote(
              message:
                  'Validation results will appear here once parsing completes.',
            ),
        ],
      ),
    );
  }

  String _parsingTitle(ParseResult? result) {
    if (result == null) {
      return 'Parsing';
    }
    final passed = result.total - result.errors;
    return 'Parsing — $passed/${result.total}';
  }
}

class _ParsingBody extends StatelessWidget {
  const _ParsingBody({required this.parseStatus, required this.parseResult});

  final StepStatus parseStatus;
  final ParseResult? parseResult;

  @override
  Widget build(BuildContext context) {
    if (parseStatus == StepStatus.running) {
      return const _ValidationSectionNote(message: 'Parsing is running...');
    }
    if (parseResult == null) {
      return const _ValidationSectionNote(
        message:
            'Parse results will appear here once you write or load a spec.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final sentence in parseResult!.sentences)
          _ParseSentenceListItem(sentence: sentence),
      ],
    );
  }
}

class _ParseSentenceListItem extends StatelessWidget {
  const _ParseSentenceListItem({required this.sentence});

  final ParseSentence sentence;

  @override
  Widget build(BuildContext context) {
    final tone = sentence.valid ? NmtkTone.success : NmtkTone.danger;
    final palette = resolveNmtkTonePalette(context, tone);
    final parsed = sentence.parsed;

    final details = <String>['Line ${sentence.line}'];
    if (parsed != null) {
      details.add('Subject: ${parsed.subject}');
      details.add('Concept: ${parsed.concept}');
      details.add('Action: ${parsed.action}');
      if (parsed.condition != null && parsed.condition!.trim().isNotEmpty) {
        details.add('Condition: ${parsed.condition}');
      }
      if (parsed.negated) {
        details.add('Negated');
      }
    } else if (sentence.errorDetail?.primaryMessage case final String message
        when message.trim().isNotEmpty) {
      details.add(message);
    } else if (sentence.error case final String error
        when error.trim().isNotEmpty) {
      details.add(error);
    }

    if (sentence.errorDetail?.hint case final String hint
        when hint.trim().isNotEmpty) {
      details.add('Hint: $hint');
    }

    return ZetaListItem(
      leading: Icon(
        sentence.valid
            ? ZetaIcons.check_circle_outline
            : ZetaIcons.cancel_outline,
        size: 18,
        color: palette.foreground,
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sentence.raw,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            details.join(' • '),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

String _slug(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

String _rowId(String group, String value, int index) =>
    '$group:${_slug(value)}:$index';

String _displayLabel(String value) => value
    .replaceAll('_', ' ')
    .replaceAll('-', ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

// NIR-native Layer 1 invariant names use compiler-facing prefixes
// (nir_lif_*, nir_cubalif_*) that don't read well underscore-split; these
// are the 7 surviving invariants after the 2026-07-04 hardware-invariant
// cleanup (see current tasks/2026-07-04/validation-deploy-readiness/audit.md).
const Map<String, String> _nirInvariantLabels = {
  'nir_lif_time_constant_positive': 'LIF time constant positive',
  'nir_lif_resistance_positive': 'LIF resistance positive',
  'nir_lif_threshold_above_leak': 'LIF threshold above leak',
  'nir_cubalif_synaptic_time_constant_positive':
      'CUBA-LIF synaptic time constant positive',
  'nir_cubalif_membrane_time_constant_positive':
      'CUBA-LIF membrane time constant positive',
  'nir_cubalif_resistance_positive': 'CUBA-LIF resistance positive',
  'nir_cubalif_threshold_above_leak': 'CUBA-LIF threshold above leak',
};

String _displayInvariantName(String value) =>
    _nirInvariantLabels[value] ?? _displayLabel(value);

String _displayInvariantMessage(String value) {
  return value
      .replaceAllMapped(RegExp(r"'([^']+)'"), (match) {
        final raw = match.group(1);
        if (raw == null) {
          return match.group(0) ?? '';
        }
        return "'${_displayInvariantName(raw)}'";
      })
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _SelectableContainer extends StatelessWidget {
  const _SelectableContainer({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : // ZETA-MIGRATION-EXEMPT: transparent (no fill) — Zeta has no transparent token
                  Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(
            NmtkShellTokens.of(context).radiusMd,
          ),
        ),
        child: child,
      ),
    );
  }
}

class _OverallStatus extends StatelessWidget {
  const _OverallStatus({
    required this.overall,
    this.parseHasErrors = false,
    this.layer1Failed = false,
    this.layer2Failed = false,
    this.deployReadinessFailed = false,
  });

  final bool overall;
  final bool parseHasErrors;
  final bool layer1Failed;
  final bool layer2Failed;
  final bool deployReadinessFailed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final String title;
    if (overall) {
      title = l10n.allInvariantsPassed;
    } else {
      final failed = <String>[
        if (parseHasErrors) 'Parsing',
        if (layer1Failed) 'Layer 1',
        if (layer2Failed) 'Layer 2',
        if (deployReadinessFailed) 'Deploy readiness',
      ];
      title = failed.isEmpty
          ? l10n.validationFailed
          : '${l10n.validationFailed} — ${failed.join(', ')}';
    }
    return NmtkStatusBanner(
      title: title,
      tone: overall ? NmtkTone.success : NmtkTone.danger,
      icon: overall ? ZetaIcons.check_circle_outline : ZetaIcons.cancel_outline,
    );
  }
}

/// Body of the Layer 1 accordion item — list of invariant rows.
class _Layer1Body extends StatelessWidget {
  const _Layer1Body({
    required this.result,
    required this.focus,
    required this.onFocus,
  });

  final Layer1Result result;
  final dynamic focus;
  final void Function(String itemId) onFocus;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (result.passed.isEmpty &&
        result.warnings.isEmpty &&
        result.failed.isEmpty) {
      rows.add(const _ValidationSectionNote(message: 'No issues reported.'));
    }
    for (final entry in result.failed.asMap().entries) {
      final inv = entry.value;
      final itemId = _rowId('failed', inv.name, entry.key);
      rows.add(_invariantListItem(context, inv, itemId, isWarning: false));
    }
    for (final entry in result.warnings.asMap().entries) {
      final inv = entry.value;
      final itemId = _rowId('warning', inv.name, entry.key);
      rows.add(_invariantListItem(context, inv, itemId, isWarning: true));
    }
    for (final entry in result.passed.asMap().entries) {
      final inv = entry.value;
      final itemId = _rowId('passed', inv.name, entry.key);
      rows.add(_invariantListItem(context, inv, itemId, isWarning: false));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _invariantListItem(
    BuildContext context,
    InvariantResult inv,
    String itemId, {
    required bool isWarning,
  }) {
    final showWarning = isWarning || inv.severity == 'warning';
    final showInlineSuccessMessage = inv.result && !showWarning;
    final tone = showWarning
        ? NmtkTone.warning
        : (inv.result ? NmtkTone.success : NmtkTone.danger);
    final palette = resolveNmtkTonePalette(context, tone);

    return ZetaListItem(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            showInlineSuccessMessage
                ? _displayInvariantMessage(inv.description)
                : _displayInvariantName(inv.name),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (!showInlineSuccessMessage) ...[
            const SizedBox(height: 4),
            Text(
              _displayInvariantMessage(inv.description),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
      leading: Icon(
        showWarning
            ? ZetaIcons.warning_outline
            : (inv.result
                  ? ZetaIcons.check_circle_outline
                  : ZetaIcons.cancel_outline),
        size: 18,
        color: palette.foreground,
      ),
      onTap: () => onFocus(itemId),
    );
  }
}

/// Body of the Layer 2 accordion item — list of check rows + inline
/// "Neurons found" block (replaces the previous nested NeurocnlSectionCard
/// per zeta-card-reduction Task 6).
class _Layer2Body extends StatelessWidget {
  const _Layer2Body({
    required this.result,
    required this.focus,
    required this.onFocus,
    required this.neuronsLabel,
  });

  final Layer2Result result;
  final dynamic focus;
  final void Function(String itemId) onFocus;
  final String neuronsLabel;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (result.checksPassed.isEmpty && result.checksFailed.isEmpty) {
      rows.add(const _ValidationSectionNote(message: 'No issues reported.'));
    }
    for (final entry in result.checksFailed.asMap().entries) {
      final check = entry.value;
      final name =
          check.code ?? check.name ?? check.primaryName ?? 'Validation issue';
      final itemId = _rowId('failed', name, entry.key);
      rows.add(
        _l2ListItem(
          context,
          name: name,
          passed: false,
          reason: check.primaryMessage,
          lines: check.lines,
          itemId: itemId,
        ),
      );
    }
    for (final entry in result.checksPassed.asMap().entries) {
      final name = entry.value;
      final itemId = _rowId('passed', name, entry.key);
      rows.add(_l2ListItem(context, name: name, passed: true, itemId: itemId));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...rows,
        if (result.neuronsFound.isNotEmpty) ...[
          const SizedBox(height: 12),
          // Inline "Neurons found" — was a NESTED NeurocnlSectionCard, now
          // a flat typography + chip row inside the Layer 2 body
          // (zeta-card-reduction Task 6 — removes the only nested-card
          // offender visible in screenshot 2).
          Text(
            neuronsLabel,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: result.neuronsFound
                .map((neuron) => ZetaAssistChip(label: neuron))
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _l2ListItem(
    BuildContext context, {
    required String name,
    required bool passed,
    required String itemId,
    String? reason,
    List<int> lines = const <int>[],
  }) {
    final tone = passed ? NmtkTone.success : NmtkTone.danger;
    final palette = resolveNmtkTonePalette(context, tone);
    return ZetaListItem(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _displayLabel(name),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (reason != null) ...[
            const SizedBox(height: 4),
            Text(
              lines.isEmpty ? reason : '$reason (lines ${lines.join(', ')})',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
      leading: Icon(
        passed ? ZetaIcons.check_circle_outline : ZetaIcons.cancel_outline,
        size: 18,
        color: palette.foreground,
      ),
      onTap: () => onFocus(itemId),
    );
  }
}

class _BackendSupportBanner extends StatelessWidget {
  const _BackendSupportBanner({required this.backendSupport});

  final BackendSupportResult backendSupport;

  @override
  Widget build(BuildContext context) {
    final title = backendSupport.warnings.isNotEmpty
        ? 'Deploy Blocked — ${backendSupport.warnings.first}'
        : 'Deploy Blocked — topology is not supported by the '
              '${backendSupport.backend} backend';
    return NmtkStatusBanner(
      title: title,
      tone: NmtkTone.danger,
      icon: ZetaIcons.cancel_outline,
    );
  }
}

/// Renders the auto-triggered deploy-readiness check that runs after a
/// passing validate — mirrors either a simulator preflight or a hardware
/// codegen preview (see `pipeline_provider.dart`'s `_mirrorSimulatorReadiness`
/// / `_runHardwareReadiness`). Renders nothing while idle.
class _DeployReadinessSection extends StatelessWidget {
  const _DeployReadinessSection({
    required this.status,
    required this.result,
    required this.target,
  });

  final StepStatus status;
  final DeployReadinessResult? result;
  final String target;

  @override
  Widget build(BuildContext context) {
    if (status == StepStatus.running) {
      return NmtkStatusBanner(
        title: 'Checking deploy readiness for $target…',
        tone: NmtkTone.info,
      );
    }

    return switch (result) {
      null => const SizedBox.shrink(),
      DeployReadinessOk() => NmtkStatusBanner(
        title: 'Ready to deploy on $target',
        tone: NmtkTone.success,
        icon: ZetaIcons.check_circle_outline,
      ),
      DeployReadinessUnsupported(
        level: final level,
        unsupportedNodes: final nodes,
        diagnostics: final diagnostics,
      ) =>
        NmtkStatusBanner(
          title: level == 'unsupported'
              ? 'Deploy Blocked — $target does not support this topology'
              : 'Deploy Warning — $target approximates part of this topology',
          tone: level == 'unsupported' ? NmtkTone.danger : NmtkTone.warning,
          icon: level == 'unsupported'
              ? ZetaIcons.cancel_outline
              : ZetaIcons.warning_outline,
          content: (nodes.isEmpty && diagnostics.isEmpty)
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (nodes.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: nodes
                            .map((node) => ZetaAssistChip(label: node))
                            .toList(),
                      ),
                    for (final diagnostic in diagnostics) ...[
                      const SizedBox(height: 4),
                      Text(
                        _displayInvariantMessage(diagnostic),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
        ),
      DeployReadinessError(message: final message) => NmtkStatusBanner(
        title: 'Deploy readiness check failed',
        tone: NmtkTone.danger,
        icon: ZetaIcons.cancel_outline,
        content: Text(
          _displayInvariantMessage(message),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    };
  }
}

class _ValidationSectionNote extends StatelessWidget {
  const _ValidationSectionNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
      ),
    );
  }
}
