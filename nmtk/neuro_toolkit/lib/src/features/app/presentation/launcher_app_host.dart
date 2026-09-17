import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zeta_flutter/zeta_flutter.dart' show ZetaDialog;

import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/tool_view.dart';
import 'package:neuro_toolkit/src/features/module/domain/module_state.dart';

/// Hosts the launcher's single workspace surface and global lifecycle dialogs.
class LauncherAppHost extends ConsumerStatefulWidget {
  const LauncherAppHost({super.key});

  @override
  ConsumerState<LauncherAppHost> createState() => _LauncherAppHostState();
}

class _LauncherAppHostState extends ConsumerState<LauncherAppHost> {
  bool _updateDialogQueued = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      moduleProvider,
      (previous, next) => _handleModuleChange(next.value),
      fireImmediately: true,
    );
  }

  void _handleModuleChange(ModuleState? moduleState) {
    if (moduleState?.pendingLauncherUpdate != null && !_updateDialogQueued) {
      _updateDialogQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showLauncherUpdateDialog(context);
        }
      });
    }
    if (moduleState?.pendingLauncherUpdate == null) {
      _updateDialogQueued = false;
    }
  }

  @override
  Widget build(BuildContext context) =>
      const SelectionArea(child: ToolViewScreen());

  void _showLauncherUpdateDialog(BuildContext context) {
    final moduleState = ref.read(moduleProvider).value;
    final update = moduleState?.pendingLauncherUpdate;
    if (update == null) return;
    final releaseNotes = update.releaseNotes.trim().isEmpty
        ? 'No published release notes were found for this version.'
        : update.releaseNotes;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ZetaDialog(
        title: 'Launcher Update Available',
        message:
            'A new version of NeuroToolkit (${update.version}) is '
            'available.\n\nRelease Notes:\n$releaseNotes',
        primaryButtonLabel: 'Download Now',
        onPrimaryButtonPressed: () async {
          final url = Uri.parse(update.url);
          if (await canLaunchUrl(url)) {
            await launchUrl(url);
          }
        },
        secondaryButtonLabel: 'Later',
        onSecondaryButtonPressed: () {
          ref.read(moduleProvider.notifier).dismissLauncherUpdate();
          Navigator.of(dialogContext).pop();
        },
      ),
    );
  }
}
