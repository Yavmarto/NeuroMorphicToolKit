import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/src/features/environment/domain/environment_state.dart';
import 'package:neuro_toolkit/services/environment_api_service.dart';

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
      Future<void> Function() action, String success) async {
    final stateAsync = ref.read(environmentProvider);
    ref.read(environmentProvider);
    try {
      await action();
      if (!mounted) return;
      NmtkToasts.success(context, success);
    } catch (_) {
      if (!mounted) return;
      NmtkToasts.error(
          context, stateAsync.error?.toString() ?? 'Operation failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final providerAsync = ref.watch(environmentProvider);
    final provider = providerAsync.value;

    if (provider == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Python Environments'),
        actions: [
          Padding(
            padding:
                EdgeInsets.symmetric(horizontal: context.nmtkTokens.compactGap),
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
      AsyncValue<EnvironmentState> providerAsync, EnvironmentState provider) {
    if (providerAsync.isLoading && provider.environments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
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
    final name =
        await _promptForName('Clone NeuroStudio', 'New environment name');
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
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${env.displayName}"?'),
        content: const Text(
          'This removes the environment and its Jupyter kernel. '
          'Notebooks using it will need a different kernel.',
        ),
        actions: [
          ZetaButton.text(
            onPressed: () => Navigator.pop(ctx, false),
            label: 'Cancel',
          ),
          ZetaButton.negative(
            onPressed: () => Navigator.pop(ctx, true),
            label: 'Delete',
          ),
        ],
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
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: ZetaTextInput(
          controller: controller,
          placeholder: placeholder,
        ),
        actions: [
          ZetaButton.text(
            onPressed: () => Navigator.pop(ctx),
            label: 'Cancel',
          ),
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

class _BusyBanner extends StatelessWidget {
  const _BusyBanner({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final zeta = Zeta.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      color: zeta.colors.surfaceInfoSubtle,
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: context.nmtkTokens.compactGap),
          Text(label, style: Zeta.of(context).textStyles.bodyMedium),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _EnvironmentCard — one card per environment, expandable to manage packages.
//
// Package state is owned by [environmentPackageProvider] (family by slug),
// eliminating the four setState calls that tracked loading/packages/error.
// ---------------------------------------------------------------------------
class _EnvironmentCard extends ConsumerStatefulWidget {
  const _EnvironmentCard({
    required this.env,
    required this.busy,
    required this.onDelete,
    required this.onExport,
  });

  final EnvironmentInfo env;
  final bool busy;
  final VoidCallback onDelete;
  final VoidCallback onExport;

  @override
  ConsumerState<_EnvironmentCard> createState() => _EnvironmentCardState();
}

class _EnvironmentCardState extends ConsumerState<_EnvironmentCard> {
  /// Local boolean — tracks panel open/close only, no async data, no side
  /// effects. Per the architecture skill, local ephemeral UI state that drives
  /// exactly one build path without crossing a widget boundary is acceptable.
  bool _expanded = false;
  final TextEditingController _addController = TextEditingController();

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      // Load packages into the provider on first expand (or reload on re-open).
      await ref
          .read(environmentPackageProvider(widget.env.slug).notifier)
          .load();
    }
  }

  Future<void> _addPackage() async {
    final spec = _addController.text.trim();
    if (spec.isEmpty) return;
    final stateAsync = ref.read(environmentProvider);
    try {
      await ref
          .read(environmentProvider.notifier)
          .installPackages(widget.env.slug, [spec]);
      _addController.clear();
      if (!mounted) return;
      NmtkToasts.success(context, 'Installed $spec');
      await ref
          .read(environmentPackageProvider(widget.env.slug).notifier)
          .load();
    } catch (_) {
      if (!mounted) return;
      NmtkToasts.error(
          context, stateAsync.error?.toString() ?? 'Install failed.');
    }
  }

  Future<void> _removePackage(String name) async {
    final stateAsync = ref.read(environmentProvider);
    try {
      await ref
          .read(environmentProvider.notifier)
          .uninstallPackages(widget.env.slug, [name]);
      if (!mounted) return;
      NmtkToasts.success(context, 'Removed $name');
      await ref
          .read(environmentPackageProvider(widget.env.slug).notifier)
          .load();
    } catch (_) {
      if (!mounted) return;
      NmtkToasts.error(
          context, stateAsync.error?.toString() ?? 'Uninstall failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final env = widget.env;
    final zeta = Zeta.of(context);
    // Watch the provider so the card rebuilds when packages are loaded.
    final pkgState = ref.watch(environmentPackageProvider(env.slug));

    return NmtkSurfaceCard(
      title: env.displayName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (env.immutable)
                const NmtkStatusBadge(label: 'Immutable', tone: NmtkTone.info)
              else
                const NmtkStatusBadge(label: 'Custom', tone: NmtkTone.success),
              NmtkStatusBadge(label: 'Python ${env.pythonVersion}'),
              NmtkStatusBadge(label: '${env.packageCount} packages'),
            ],
          ),
          SizedBox(height: context.nmtkTokens.compactGap),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ZetaButton.outline(
                label: _expanded ? 'Hide packages' : 'Packages',
                onPressed: _toggle,
              ),
              ZetaButton.outline(
                label: 'Export…',
                onPressed: widget.onExport,
              ),
              if (!env.immutable)
                ZetaButton.outline(
                  label: 'Delete',
                  onPressed: widget.busy ? null : widget.onDelete,
                ),
            ],
          ),
          if (_expanded) ...[
            const Divider(height: 24),
            if (!env.immutable) ...[
              Row(
                children: [
                  Expanded(
                    child: ZetaTextInput(
                      controller: _addController,
                      placeholder: 'Package (e.g. cowsay or numpy==1.26)',
                      onFieldSubmitted: (_) =>
                          widget.busy ? null : _addPackage(),
                    ),
                  ),
                  SizedBox(width: context.nmtkTokens.compactGap),
                  ZetaButton.primary(
                    label: 'Add',
                    onPressed: widget.busy ? null : _addPackage,
                  ),
                ],
              ),
              SizedBox(height: context.nmtkTokens.compactGap),
            ],
            _buildPackages(env, zeta, pkgState),
          ],
        ],
      ),
    );
  }

  Widget _buildPackages(
    EnvironmentInfo env,
    Zeta zeta,
    EnvironmentPackageState pkgState,
  ) {
    if (pkgState.loading) {
      return Padding(
        padding: EdgeInsets.all(context.nmtkTokens.compactGap),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (pkgState.error != null) {
      return Text(
        pkgState.error!,
        style: Zeta.of(context)
            .textStyles
            .bodySmall
            .apply(color: zeta.colors.mainNegative),
      );
    }
    final pkgs = pkgState.packages;
    if (pkgs.isEmpty) {
      return Text(
        'No packages found.',
        style: Zeta.of(context)
            .textStyles
            .bodySmall
            .apply(color: zeta.colors.mainSubtle),
      );
    }
    return Column(
      children: [
        for (final pkg in pkgs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text('${pkg.name}  ${pkg.version}',
                      style: Zeta.of(context).textStyles.bodySmall),
                ),
                if (!env.immutable)
                  ZetaButton.text(
                    label: 'Remove',
                    onPressed:
                        widget.busy ? null : () => _removePackage(pkg.name),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _ExportDialog — show the requirements.txt, copy or save to share.
//
// All async state (loading, body, mode, error) is owned by
// [environmentExportProvider] — no setState calls remain.
// ---------------------------------------------------------------------------
class _ExportDialog extends ConsumerWidget {
  const _ExportDialog({required this.env});
  final EnvironmentInfo env;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exportAsync = ref.watch(environmentExportProvider(env.slug));

    return exportAsync.when(
      loading: () => const AlertDialog(
        content: SizedBox(
          width: 420,
          height: 420,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => AlertDialog(
        title: Text('Export "${env.displayName}"'),
        content: Text(e.toString()),
        actions: [
          ZetaButton.text(
            onPressed: () => Navigator.pop(context),
            label: 'Close',
          ),
        ],
      ),
      data: (exportState) => _ExportDialogContent(
        env: env,
        exportState: exportState,
        onModeChanged: (mode) =>
            ref.read(environmentExportProvider(env.slug).notifier).reload(mode),
      ),
    );
  }
}

class _ExportDialogContent extends StatelessWidget {
  const _ExportDialogContent({
    required this.env,
    required this.exportState,
    required this.onModeChanged,
  });

  final EnvironmentInfo env;
  final EnvironmentExportState exportState;
  final ValueChanged<String> onModeChanged;

  Future<void> _save(BuildContext context) async {
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: exportState.body));
      if (!context.mounted) return;
      NmtkToasts.success(
          context, 'Copied to clipboard (file save unsupported on web).');
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${env.slug}-requirements.txt');
      await file.writeAsString(exportState.body);
      if (!context.mounted) return;
      NmtkToasts.success(context, 'Saved to ${file.path}');
    } catch (e) {
      if (!context.mounted) return;
      NmtkToasts.error(context, 'Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Export "${env.displayName}"'),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Contents',
                    style: Zeta.of(context).textStyles.labelMedium),
                const Spacer(),
                if (!env.immutable)
                  DropdownButton<String>(
                    value: exportState.mode,
                    onChanged: exportState.loading
                        ? null
                        : (v) {
                            if (v != null) onModeChanged(v);
                          },
                    items: const [
                      DropdownMenuItem(
                          value: 'delta', child: Text('Added packages only')),
                      DropdownMenuItem(
                          value: 'full', child: Text('Full environment')),
                    ],
                  ),
              ],
            ),
            SizedBox(height: context.nmtkTokens.compactGap),
            Expanded(
              child: exportState.loading
                  ? const Center(child: CircularProgressIndicator())
                  : exportState.error != null
                      ? Text(exportState.error!)
                      : Scrollbar(
                          child: SingleChildScrollView(
                            child: SelectableText(
                              exportState.body.isEmpty
                                  ? '(no packages)'
                                  : exportState.body,
                              style: Zeta.of(context)
                                  .textStyles
                                  .bodySmall
                                  .copyWith(
                                    fontFamily: 'JetBrainsMono',
                                    fontSize: 12,
                                  ),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
      actions: [
        ZetaButton.text(
          onPressed: () => Navigator.pop(context),
          label: 'Close',
        ),
        ZetaButton.outline(
          onPressed: exportState.body.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(
                      ClipboardData(text: exportState.body));
                  if (!context.mounted) return;
                  NmtkToasts.success(context, 'Copied to clipboard');
                },
          label: 'Copy',
        ),
        ZetaButton(
          onPressed: exportState.body.isEmpty ? null : () => _save(context),
          label: 'Save file',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _ImportDialog — paste a requirements.txt + name to create a new environment.
// ---------------------------------------------------------------------------
class _ImportResult {
  const _ImportResult(this.name, this.requirements);
  final String name;
  final String requirements;
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _reqController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _reqController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import requirements'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Environment name',
                style: Zeta.of(context).textStyles.labelMedium),
            SizedBox(height: context.nmtkTokens.compactGap),
            ZetaTextInput(
              controller: _nameController,
              placeholder: 'e.g. Shared experiment',
            ),
            SizedBox(height: context.nmtkTokens.sectionGap),
            Text('requirements.txt',
                style: Zeta.of(context).textStyles.labelMedium),
            SizedBox(height: context.nmtkTokens.compactGap),
            TextField(
              controller: _reqController,
              minLines: 6,
              maxLines: 12,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'numpy==1.26.0\ncowsay==6.1\n…',
              ),
              style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        ZetaButton.text(
          onPressed: () => Navigator.pop(context),
          label: 'Cancel',
        ),
        ZetaButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              _ImportResult(name, _reqController.text),
            );
          },
          label: 'Import',
        ),
      ],
    );
  }
}
