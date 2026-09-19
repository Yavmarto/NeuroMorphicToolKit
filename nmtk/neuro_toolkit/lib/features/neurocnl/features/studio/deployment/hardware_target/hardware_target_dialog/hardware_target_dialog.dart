import 'dart:async';

import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/services/deploy_error_formatter.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_target_catalog/support.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/hardware_target/add_hardware_target_form/add_hardware_target_form.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/hardware_target/add_hardware_target_form/hardware_target_form_result.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/hardware_target/hardware_target_dialog/dialog_target_tile.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/hardware_target/hardware_target_dialog/hardware_target_dialog_data.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/hardware_target/hardware_target_dialog/saved_hardware_target_entry.dart';

class HardwareTargetDialog extends StatefulWidget {
  const HardwareTargetDialog({
    super.key,
    required this.data,
    required this.selectedEntryId,
    required this.onSelectTarget,
    required this.onSaveTarget,
    this.onTestTarget,
    this.onReloadEntries,
    this.onScanHardware,
  });

  final HardwareTargetDialogData data;
  final String? selectedEntryId;
  final Future<void> Function(SavedHardwareTargetEntry) onSelectTarget;

  /// Saves, selects, and returns what happened — or throws if the save failed.
  ///
  /// Returning the stored entry lets the dialog test the freshly-saved host,
  /// which needs its server-assigned id. `selected` is false when the save
  /// committed but the target could not be made active, which must be reported
  /// as such rather than as a failed save.
  final Future<({SavedHardwareTargetEntry entry, bool selected})> Function(
    HardwareTargetFormResult form,
  )
  onSaveTarget;

  /// Runs the host's connectivity test and returns a human-readable verdict.
  /// `null` for target types that have no such check.
  final Future<String> Function(String entryId)? onTestTarget;

  /// Re-reads the saved targets so `hasPassword`, `state`, and subtitles are
  /// current after a save. Without this the dialog kept its immutable initial
  /// list, and a second Edit in the same session worked off stale data.
  final Future<List<SavedHardwareTargetEntry>> Function()? onReloadEntries;

  /// Runs a backend hardware scan and auto-adds detected targets, returning a
  /// human-readable summary to show as the dialog's status message. Absent for
  /// target types with no auto-scan (e.g. PYNQ).
  final Future<String> Function()? onScanHardware;

  @override
  State<HardwareTargetDialog> createState() => _HardwareTargetDialogState();
}

class _HardwareTargetDialogState extends State<HardwareTargetDialog> {
  SavedHardwareTargetEntry? _activeFormEntry;
  String? _saveErrorMessage;
  String? _statusMessage;
  bool _isSaving = false;
  List<SavedHardwareTargetEntry>? _entries;
  String? _testingEntryId;
  bool _scanningHardware = false;

  List<SavedHardwareTargetEntry> get _currentEntries =>
      _entries ?? widget.data.entries;

  Future<void> _reloadEntries() async {
    final reload = widget.onReloadEntries;
    if (reload == null) return;
    try {
      final entries = await reload();
      if (!mounted) return;
      setState(() => _entries = entries);
    } catch (_) {
      // A failed refresh must not mask a save that succeeded; the list simply
      // stays as it was.
    }
  }

  /// Runs [action] with the busy flag set, clearing it on **every** exit path.
  ///
  /// The previous version reset `_isSaving` only in `catch`, so a save that
  /// succeeded without closing the dialog left the form stuck behind a
  /// permanent "Saving..." — which read as a failed save and made users retype
  /// their password and try again.
  Future<void> _runBusy(Future<void> Function() action) async {
    setState(() {
      _saveErrorMessage = null;
      _statusMessage = null;
      _isSaving = true;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _saveErrorMessage = formatDeployError(
          error,
          serviceName: 'launcher control service',
          action: 'saving the ${targetLabel(widget.data.targetType)} target',
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _testEntry(String entryId) async {
    final test = widget.onTestTarget;
    if (test == null) return;
    setState(() {
      _testingEntryId = entryId;
      _saveErrorMessage = null;
      _statusMessage = null;
    });
    try {
      final verdict = await test(entryId);
      if (!mounted) return;
      setState(() => _statusMessage = verdict);
      await _reloadEntries();
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _saveErrorMessage = formatDeployError(
          error,
          serviceName: 'launcher control service',
          action:
              'testing the ${targetLabel(widget.data.targetType)} connection',
        ),
      );
    } finally {
      if (mounted) setState(() => _testingEntryId = null);
    }
  }

  Future<void> _scanHardware() async {
    final scan = widget.onScanHardware;
    if (scan == null) return;
    setState(() {
      _scanningHardware = true;
      _saveErrorMessage = null;
      _statusMessage = null;
    });
    try {
      final message = await scan();
      await _reloadEntries();
      if (!mounted) return;
      setState(() => _statusMessage = message);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _saveErrorMessage = formatDeployError(
          error,
          serviceName: 'neurochip backend',
          action: 'scanning for hardware on this server',
        ),
      );
    } finally {
      if (mounted) setState(() => _scanningHardware = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showForm = _activeFormEntry != null;
    return SafeArea(
      child: AlertDialog(
        insetPadding: NmtkDialogSurface.insetPadding(context),
        shape: RoundedRectangleBorder(
          borderRadius: NmtkDesignTokens.dialogShape,
        ),
        backgroundColor: AppTheme.surface,
        title: Text(
          showForm
              ? (_activeFormEntry!.id.isEmpty
                    ? 'Add ${targetLabel(widget.data.targetType)} target'
                    : 'Edit ${targetLabel(widget.data.targetType)} target')
              : 'Manage ${targetLabel(widget.data.targetType)} targets',
        ),
        content: ConstrainedBox(
          constraints: NmtkDialogSurface.constraints(context, maxWidth: 560),
          child: SizedBox(
            width: 560,
            child: showForm
                ? AddHardwareTargetForm(
                    targetType: widget.data.targetType,
                    initialEntry: _activeFormEntry,
                    errorMessage: _saveErrorMessage,
                    statusMessage: _statusMessage,
                    isSaving: _isSaving,
                    onCancel: () => setState(() {
                      _activeFormEntry = null;
                      _saveErrorMessage = null;
                      _statusMessage = null;
                    }),
                    onSave: (form) {
                      // Resolved before the first await so the closure never reaches
                      // for `context` across an async gap.
                      final navigator = Navigator.of(context);
                      return _runBusy(() async {
                        final result = await widget.onSaveTarget(form);
                        await _reloadEntries();
                        if (!mounted) return;
                        if (result.selected) {
                          navigator.pop();
                          return;
                        }
                        setState(() {
                          _activeFormEntry = result.entry;
                          _statusMessage =
                              'Saved. It could not be made the active target — it '
                              'is stored and can be selected from this list.';
                        });
                      });
                    },
                    onSaveAndTest: widget.onTestTarget == null
                        ? null
                        : (form) => _runBusy(() async {
                            // Save first: the connectivity-test route is keyed by
                            // host id, which a host being created does not have yet.
                            final result = await widget.onSaveTarget(form);
                            await _reloadEntries();
                            final verdict = await widget.onTestTarget!(
                              result.entry.id,
                            );
                            if (!mounted) return;
                            setState(() {
                              _activeFormEntry = result.entry;
                              _statusMessage = verdict;
                            });
                          }),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.data.loadErrorMessage != null) ...[
                        NmtkStatusBanner(
                          title: widget.data.loadErrorMessage!,
                          tone: NmtkTone.warning,
                          icon: ZetaIcons.warning_outline,
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        'Saved targets',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_currentEntries.isEmpty)
                        Text(
                          'No saved ${targetLabel(widget.data.targetType).toLowerCase()} devices yet.',
                          style: Zeta.of(context).textStyles.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                        )
                      else
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final entry in _currentEntries) ...[
                                  DialogTargetTile(
                                    entry: entry,
                                    selected:
                                        entry.id == widget.selectedEntryId,
                                    testing: _testingEntryId == entry.id,
                                    onTap: () => widget.onSelectTarget(entry),
                                    onEdit: () => setState(() {
                                      _activeFormEntry = entry;
                                      _saveErrorMessage = null;
                                      _statusMessage = null;
                                    }),
                                    onTest: widget.onTestTarget == null
                                        ? null
                                        : () => _testEntry(entry.id),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ],
                            ),
                          ),
                        ),
                      if (_statusMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _statusMessage!,
                          key: const Key('hardware-target-list-status'),
                          style: Zeta.of(context).textStyles.bodyXSmall
                              .copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                      if (_saveErrorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _saveErrorMessage!,
                          style: Zeta.of(context).textStyles.bodyXSmall
                              .copyWith(color: AppTheme.error),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
        actions: [
          if (!showForm && widget.onScanHardware != null)
            ZetaButton.text(
              key: const Key('hardware-scan-button'),
              onPressed: _scanningHardware
                  ? null
                  : () => unawaited(_scanHardware()),
              label: _scanningHardware
                  ? 'Scanning for hardware…'
                  : 'Scan for hardware',
            ),
          if (!showForm)
            ZetaButton.text(
              onPressed: () => setState(() {
                _activeFormEntry = SavedHardwareTargetEntry(
                  id: '',
                  title: '',
                  targetType: widget.data.targetType,
                );
              }),
              label: 'Add new target',
            ),
          if (!showForm)
            ZetaButton.text(
              onPressed: () => Navigator.of(context).pop(),
              label: 'Close',
            ),
        ],
      ),
    );
  }
}
