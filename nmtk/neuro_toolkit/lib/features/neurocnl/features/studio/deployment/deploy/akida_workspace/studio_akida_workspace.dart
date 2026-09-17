library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/hardware_reachability_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_akida_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/open_external_url.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_akida_deploy_service.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/akida_execution_pane/akida_execution_controls.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/akida_setup_pane/akida_setup_pane.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/studio_standard_deploy_page/studio_standard_deploy_page.dart';

class StudioAkidaWorkspace extends ConsumerStatefulWidget {
  const StudioAkidaWorkspace({
    super.key,
    required this.selectedDeviceLabel,
    required this.selectedDeviceData,
    required this.isCompact,
    this.onManageHardwareTarget,
  });

  final String? selectedDeviceLabel;
  final Object? selectedDeviceData;
  final bool isCompact;
  final ValueChanged<String>? onManageHardwareTarget;

  @override
  ConsumerState<StudioAkidaWorkspace> createState() =>
      _StudioAkidaWorkspaceState();
}

class _StudioAkidaWorkspaceState extends ConsumerState<StudioAkidaWorkspace> {
  String? _scheduledPreparationKey;

  void _scheduleAutomaticPreparation(
    AkidaPairedHost host,
    String workspaceName,
  ) {
    final key = '${host.id}::$workspaceName';
    if (_scheduledPreparationKey == key) return;
    _scheduledPreparationKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final notifier = ref.read(studioAkidaDeployProvider.notifier);
      if (ref.read(studioAkidaDeployProvider).selectedHost?.id != host.id) {
        notifier.selectHost(host);
      }
      await notifier.checkReadiness(ref.read(specTextProvider));
      if (!mounted ||
          ref.read(studioAkidaDeployProvider).errorMessage != null) {
        return;
      }
      await notifier.discoverLatestBundle(workspaceName);
    });
  }

  Future<void> _chooseBundle(AkidaPairedHost host) async {
    final notifier = ref.read(studioAkidaDeployProvider.notifier);
    final selection = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
      withData: true,
    );
    final file = selection?.files.single;
    if (file == null) return;
    if (!file.name.endsWith('.akida-bundle.zip')) {
      notifier.reportBundleRejected(
        '"${file.name}" is not an Akida deploy bundle. Rename it so it ends '
        'with ".akida-bundle.zip", then choose it again.',
      );
      return;
    }
    final bytes = file.bytes ?? await file.xFile.readAsBytes();
    notifier.selectHost(host);
    notifier.selectBundle(
      StudioAkidaBundleArtifact(
        filename: file.name,
        bundleBase64: base64Encode(bytes),
        sha256: sha256.convert(bytes).toString(),
      ),
    );
  }

  Future<void> _createDemo(String workspaceName) async {
    final url = await ref
        .read(studioAkidaDeployProvider.notifier)
        .createMnistCompanion(workspaceName);
    if (url != null && url.isNotEmpty) unawaited(openExternalUrl(url));
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(studioAkidaDeployProvider);
    final readinessHost = ref.watch(akidaHostReadinessProvider).value;
    final selectedHost =
        provider.selectedHost ??
        (widget.selectedDeviceData is AkidaPairedHost
            ? widget.selectedDeviceData as AkidaPairedHost
            : null) ??
        readinessHost;
    final workspaceName = ref.watch(workspaceProvider).workspaceName;
    if (selectedHost != null) {
      _scheduleAutomaticPreparation(selectedHost, workspaceName);
    }

    return StudioStandardDeployPage(
      title: widget.isCompact && selectedHost != null
          ? 'Akida · ${selectedHost.displayName}'
          : 'Akida Runtime',
      isCompact: widget.isCompact,
      setup: AkidaSetupPane(
        provider: provider,
        selectedHost: selectedHost,
        workspaceName: workspaceName,
        onManageHardwareTarget: widget.onManageHardwareTarget,
        onChooseBundle: selectedHost == null
            ? null
            : () => _chooseBundle(selectedHost),
        onCreateDemo: () => _createDemo(workspaceName),
        isCompact: widget.isCompact,
      ),
      inference: AkidaExecutionControls(
        provider: provider,
        isCompact: widget.isCompact,
      ),
    );
  }
}
