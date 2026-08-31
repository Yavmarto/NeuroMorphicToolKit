import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/src/features/environment/domain/environment_state.dart';
import 'package:neuro_toolkit/services/environment_api_service.dart';

part 'environment_editor/busy_banner.dart';
part 'environment_editor/environment_card.dart';
part 'environment_editor/export_dialog.dart';
part 'environment_editor/export_dialog_content.dart';
part 'environment_editor/import_dialog.dart';

/// Python Environment Editor.
///
/// Lists the immutable NeuroStudio base kernel plus any user clones, and lets
/// the user clone the base, install/remove packages in a clone, export/import a
/// requirements.txt to share, and delete clones. New environments register
/// Jupyter kernels and appear automatically in the embedded JupyterLab.
///
/// Note: this screen deliberately uses text labels rather than icons — the
/// package's icon set is still mid-migration to ZetaIcons (see the T-ICON
/// governance audit), so no new Material `Icons.*` references are introduced.
class EnvironmentEditorScreen extends ConsumerStatefulWidget {
  const EnvironmentEditorScreen({super.key});

  @override
  ConsumerState<EnvironmentEditorScreen> createState() =>
      _EnvironmentEditorScreenState();
}

class _EnvironmentEditorScreenState
    extends ConsumerState<EnvironmentEditorScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(environmentProvider.notifier).refresh();
    });
  }

  Future<void> _runGuarded(
    Future<void> Function() action,
    String success,
  ) async {
    final stateAsync = ref.read(environmentProvider);
    ref.read(environmentProvider);
    try {
      await action();
      if (!mounted) return;
      NmtkToasts.success(context, success);
    } catch (_) {
      if (!mounted) return;
      NmtkToasts.error(
        context,
        stateAsync.error?.toString() ?? 'Operation failed.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final providerAsync = ref.watch(environmentProvider);
    final provider = providerAsync.value;

    if (provider == null) {
      return const Scaffold(
        body: Center(child: ZetaProgressCircle(size: ZetaCircleSizes.s)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Python Environments'),
        actions: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: context.nmtkTokens.compactGap,
            ),
            child: ZetaButton.text(
              label: 'Refresh',
              onPressed: provider.busy
                  ? null
                  : () => ref.read(environmentProvider.notifier).refresh(),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (provider.busy)
            _BusyBanner(label: provider.activeOperation ?? 'Working…'),
          Expanded(child: _buildBody(providerAsync, provider)),
        ],
      ),
    );
  }

  Widget _buildBody(
    AsyncValue<EnvironmentState> providerAsync,
    EnvironmentState provider,
  ) {
    if (providerAsync.isLoading && provider.environments.isEmpty) {
      return const Center(child: ZetaProgressCircle(size: ZetaCircleSizes.s));
    }
    if (providerAsync.hasError && provider.environments.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: NmtkSurfaceCard(
            tone: NmtkTone.danger,
            title: 'Environments unavailable',
            subtitle: providerAsync.error.toString(),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ZetaButton.primary(
                label: 'Retry',
                onPressed: () =>
                    ref.read(environmentProvider.notifier).refresh(),
              ),
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.all(context.nmtkTokens.sectionGap * 1.5),
      children: [
        NmtkSurfaceCard(
          title: 'Manage Python environments',
          subtitle:
              'Clone the immutable "Python (NeuroStudio)" environment to add your '
              'own packages. New environments appear as kernels in Notebooks.',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ZetaButton.primary(
                label: 'Clone NeuroStudio',
                onPressed: provider.busy ? null : _promptClone,
              ),
              ZetaButton.outline(
                label: 'Import requirements…',
                onPressed: provider.busy ? null : _promptImport,
              ),
            ],
          ),
        ),
        SizedBox(height: context.nmtkTokens.sectionGap),
        for (final env in provider.environments) ...[
          _EnvironmentCard(
            env: env,
            busy: provider.busy,
            onDelete: () => _confirmDelete(env),
            onExport: () => _showExport(env),
          ),
          SizedBox(height: context.nmtkTokens.sectionGap),
        ],
      ],
    );
  }

  // ── clone / import ───────────────────────────────────────────────────────--
  Future<void> _promptClone() async {
    final name = await _promptForName(
      'Clone NeuroStudio',
      'New environment name',
    );
    if (name == null || name.trim().isEmpty) return;
    await _runGuarded(
      () =>
          ref.read(environmentProvider.notifier).createEnvironment(name.trim()),
      'Environment "$name" created.',
    );
  }

  Future<void> _promptImport() async {
    final result = await showDialog<_ImportResult>(
      context: context,
      builder: (_) => const _ImportDialog(),
    );
    if (result == null) return;
    await _runGuarded(
      () => ref
          .read(environmentProvider.notifier)
          .importEnvironment(result.name, result.requirements),
      'Environment "${result.name}" imported.',
    );
  }

  Future<void> _confirmDelete(EnvironmentInfo env) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => ZetaDialog(
        title: 'Delete "${env.displayName}"?',
        message:
            'This removes the environment and its Jupyter kernel. '
            'Notebooks using it will need a different kernel.',
        primaryButtonLabel: 'Delete',
        onPrimaryButtonPressed: () => Navigator.pop(ctx, true),
        secondaryButtonLabel: 'Cancel',
        onSecondaryButtonPressed: () => Navigator.pop(ctx, false),
      ),
    );
    if (ok != true) return;
    await _runGuarded(
      () => ref.read(environmentProvider.notifier).deleteEnvironment(env.slug),
      'Environment "${env.displayName}" deleted.',
    );
  }

  Future<String?> _promptForName(String title, String placeholder) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => NmtkContentDialog(
        title: title,
        content: NmtkTextInput(
          controller: controller,
          placeholder: placeholder,
        ),
        actions: [
          ZetaButton.text(onPressed: () => Navigator.pop(ctx), label: 'Cancel'),
          ZetaButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            label: 'Create',
          ),
        ],
      ),
    ).whenComplete(() {
      // Defer disposal a frame: the dialog's exit transition is still
      // rebuilding widgets that reference this controller when this future
      // resolves, so disposing synchronously here throws.
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    });
  }

  // ── export / share ─────────────────────────────────────────────────────---
  Future<void> _showExport(EnvironmentInfo env) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ExportDialog(env: env),
    );
  }
}
