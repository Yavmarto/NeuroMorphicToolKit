part of '../environment_editor.dart';

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
      await ref.read(environmentProvider.notifier).installPackages(
        widget.env.slug,
        [spec],
      );
      _addController.clear();
      if (!mounted) return;
      NmtkToasts.success(context, 'Installed $spec');
      await ref
          .read(environmentPackageProvider(widget.env.slug).notifier)
          .load();
    } catch (_) {
      if (!mounted) return;
      NmtkToasts.error(
        context,
        stateAsync.error?.toString() ?? 'Install failed.',
      );
    }
  }

  Future<void> _removePackage(String name) async {
    final stateAsync = ref.read(environmentProvider);
    try {
      await ref.read(environmentProvider.notifier).uninstallPackages(
        widget.env.slug,
        [name],
      );
      if (!mounted) return;
      NmtkToasts.success(context, 'Removed $name');
      await ref
          .read(environmentPackageProvider(widget.env.slug).notifier)
          .load();
    } catch (_) {
      if (!mounted) return;
      NmtkToasts.error(
        context,
        stateAsync.error?.toString() ?? 'Uninstall failed.',
      );
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
              ZetaButton.outline(label: 'Export…', onPressed: widget.onExport),
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
                    child: NmtkTextInput(
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
        child: const Center(child: ZetaProgressCircle(size: ZetaCircleSizes.s)),
      );
    }
    if (pkgState.error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pkgState.error!,
            style: Zeta.of(
              context,
            ).textStyles.bodySmall.apply(color: zeta.colors.mainNegative),
          ),
          SizedBox(height: context.nmtkTokens.compactGap),
          ZetaButton.outline(
            label: 'Retry',
            onPressed: () =>
                ref.read(environmentPackageProvider(env.slug).notifier).load(),
          ),
        ],
      );
    }
    final pkgs = pkgState.packages;
    if (pkgs.isEmpty) {
      return Text(
        'No packages found.',
        style: Zeta.of(
          context,
        ).textStyles.bodySmall.apply(color: zeta.colors.mainSubtle),
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
                  child: Text(
                    '${pkg.name}  ${pkg.version}',
                    style: Zeta.of(context).textStyles.bodySmall,
                  ),
                ),
                if (!env.immutable)
                  ZetaButton.text(
                    label: 'Remove',
                    onPressed: widget.busy
                        ? null
                        : () => _removePackage(pkg.name),
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
