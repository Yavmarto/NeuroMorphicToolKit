import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/environment_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
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
      ref.read(environmentStateProvider).refresh();
    });
  }

  Future<void> _runGuarded(
      Future<void> Function() action, String success) async {
    final provider = ref.read(environmentStateProvider);
    try {
      await action();
      if (!mounted) return;
      NmtkToasts.success(context, success);
    } catch (_) {
      if (!mounted) return;
      NmtkToasts.error(context, provider.error ?? 'Operation failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(environmentStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Python Environments'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ZetaButton.text(
              label: 'Refresh',
              onPressed: provider.busy ? null : () => provider.refresh(),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (provider.busy)
            _BusyBanner(label: provider.activeOperation ?? 'Working…'),
          Expanded(child: _buildBody(provider)),
        ],
      ),
    );
  }

  Widget _buildBody(EnvironmentProvider provider) {
    if (provider.isLoading && provider.environments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.error != null && provider.environments.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: NmtkSurfaceCard(
            tone: NmtkTone.danger,
            title: 'Environments unavailable',
            subtitle: provider.error!,
            child: Align(
              alignment: Alignment.centerLeft,
              child: NmtkPrimaryButton(
                label: 'Retry',
                onPressed: () => provider.refresh(),
              ),
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(24),
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
              NmtkPrimaryButton(
                label: 'Clone NeuroStudio',
                onPressed: provider.busy ? null : _promptClone,
              ),
              NmtkOutlinedButton(
                label: 'Import requirements…',
                onPressed: provider.busy ? null : _promptImport,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final env in provider.environments) ...[
          _EnvironmentCard(
            env: env,
            busy: provider.busy,
            onDelete: () => _confirmDelete(env),
            onExport: () => _showExport(env),
          ),
          const SizedBox(height: 16),
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
      () => ref.read(environmentStateProvider).createEnvironment(name.trim()),
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
          .read(environmentStateProvider)
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
      () => ref.read(environmentStateProvider).deleteEnvironment(env.slug),
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
    );
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
          const SizedBox(width: 12),
          Text(label, style: Zeta.of(context).textStyles.bodyMedium),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _EnvironmentCard — one card per environment, expandable to manage packages.
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
  bool _expanded = false;
  bool _loadingPackages = false;
  List<PackageInfo>? _packages;
  String? _packagesError;
  final TextEditingController _addController = TextEditingController();

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  Future<void> _loadPackages() async {
    setState(() {
      _loadingPackages = true;
      _packagesError = null;
    });
    try {
      final pkgs =
          await ref.read(environmentStateProvider).packages(widget.env.slug);
      if (!mounted) return;
      setState(() => _packages = pkgs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _packagesError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingPackages = false);
    }
  }

  Future<void> _toggle() async {
    setState(() => _expanded = !_expanded);
    if (_expanded && _packages == null && !_loadingPackages) {
      await _loadPackages();
    }
  }

  Future<void> _addPackage() async {
    final spec = _addController.text.trim();
    if (spec.isEmpty) return;
    final provider = ref.read(environmentStateProvider);
    try {
      await provider.installPackages(widget.env.slug, [spec]);
      _addController.clear();
      if (!mounted) return;
      NmtkToasts.success(context, 'Installed $spec');
      await _loadPackages();
    } catch (_) {
      if (!mounted) return;
      NmtkToasts.error(context, provider.error ?? 'Install failed.');
    }
  }

  Future<void> _removePackage(String name) async {
    final provider = ref.read(environmentStateProvider);
    try {
      await provider.uninstallPackages(widget.env.slug, [name]);
      if (!mounted) return;
      NmtkToasts.success(context, 'Removed $name');
      await _loadPackages();
    } catch (_) {
      if (!mounted) return;
      NmtkToasts.error(context, provider.error ?? 'Uninstall failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final env = widget.env;
    final zeta = Zeta.of(context);

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
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              NmtkOutlinedButton(
                label: _expanded ? 'Hide packages' : 'Packages',
                onPressed: _toggle,
              ),
              NmtkOutlinedButton(
                label: 'Export…',
                onPressed: widget.onExport,
              ),
              if (!env.immutable)
                NmtkOutlinedButton(
                  label: 'Delete',
                  tone: NmtkTone.danger,
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
                  const SizedBox(width: 8),
                  NmtkPrimaryButton(
                    label: 'Add',
                    onPressed: widget.busy ? null : _addPackage,
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            _buildPackages(env, zeta),
          ],
        ],
      ),
    );
  }

  Widget _buildPackages(EnvironmentInfo env, Zeta zeta) {
    if (_loadingPackages) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_packagesError != null) {
      return Text(
        _packagesError!,
        style: Zeta.of(context)
            .textStyles
            .bodySmall
            .apply(color: zeta.colors.mainNegative),
      );
    }
    final pkgs = _packages ?? const <PackageInfo>[];
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
// ---------------------------------------------------------------------------
class _ExportDialog extends ConsumerStatefulWidget {
  const _ExportDialog({required this.env});
  final EnvironmentInfo env;

  @override
  ConsumerState<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends ConsumerState<_ExportDialog> {
  String _mode = 'delta';
  bool _loading = true;
  String _body = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final body = await ref
          .read(environmentStateProvider)
          .exportRequirements(widget.env.slug, mode: _mode);
      if (!mounted) return;
      setState(() => _body = body);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: _body));
      if (!mounted) return;
      NmtkToasts.success(
          context, 'Copied to clipboard (file save unsupported on web).');
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${widget.env.slug}-requirements.txt');
      await file.writeAsString(_body);
      if (!mounted) return;
      NmtkToasts.success(context, 'Saved to ${file.path}');
    } catch (e) {
      if (!mounted) return;
      NmtkToasts.error(context, 'Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Export "${widget.env.displayName}"'),
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
                if (!widget.env.immutable)
                  DropdownButton<String>(
                    value: _mode,
                    onChanged: _loading
                        ? null
                        : (v) {
                            if (v != null) {
                              setState(() => _mode = v);
                              _load();
                            }
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
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Text(_error!)
                      : Scrollbar(
                          child: SingleChildScrollView(
                            child: SelectableText(
                              _body.isEmpty ? '(no packages)' : _body,
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
          onPressed: _body.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: _body));
                  if (!context.mounted) return;
                  NmtkToasts.success(context, 'Copied to clipboard');
                },
          label: 'Copy',
        ),
        ZetaButton(
          onPressed: _body.isEmpty ? null : _save,
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
            const SizedBox(height: 6),
            ZetaTextInput(
              controller: _nameController,
              placeholder: 'e.g. Shared experiment',
            ),
            const SizedBox(height: 16),
            Text('requirements.txt',
                style: Zeta.of(context).textStyles.labelMedium),
            const SizedBox(height: 6),
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
