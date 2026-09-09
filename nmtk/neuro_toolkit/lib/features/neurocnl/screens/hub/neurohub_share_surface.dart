import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/neurohub_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/neurohub_sign_in_dialog.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/neurohub_workspace_preview.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurohub_client.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Launcher-hosted "Share" surface for the Neurohub module.
///
/// Browsing and managing the signed-in user's GitHub-backed workspaces. The
/// commit of the *current* Studio workspace stays inside NeuroStudio (its
/// "Save to Neurohub" action), because that flow needs the live canvas/CNL
/// state; this surface is the standalone module face for the same backend,
/// registered through the same native-surface pattern NeuroCNL uses.
class NeurohubShareSurface extends ConsumerStatefulWidget {
  const NeurohubShareSurface({super.key, required this.launchContext});

  /// Root-owned launch inputs for this embedded feature surface.
  final NmtkFeatureLaunchContext launchContext;

  @override
  ConsumerState<NeurohubShareSurface> createState() =>
      _NeurohubShareSurfaceState();
}

class _NeurohubShareSurfaceState extends ConsumerState<NeurohubShareSurface> {
  String? _selectedOwner;
  String? _selectedSlug;

  Future<void> _signIn() async {
    await showNeurohubSignInDialog(context);
    if (!mounted) return;
    setState(() {
      _selectedOwner = null;
      _selectedSlug = null;
    });
  }

  void _select(NeurohubWorkspaceSummary workspace) {
    ref.read(neurohubWorkspaceBindingProvider.notifier).bind(workspace);
    setState(() {
      _selectedOwner = workspace.owner;
      _selectedSlug = workspace.slug;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(neurohubSessionProvider);
    return Scaffold(
      key: const Key('neurohub-share-surface'),
      backgroundColor: NmtkShellTokens.of(context).shellBackground,
      appBar: AppBar(
        title: const Text('Neurohub · Share'),
        actions: <Widget>[
          if (session.isSignedIn)
            IconButton(
              key: const Key('neurohub-share-sign-out'),
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () =>
                  ref.read(neurohubSessionProvider.notifier).signOut(),
            ),
        ],
      ),
      body: switch (session.status) {
        NeurohubSessionStatus.restoring => const Center(
          child: ZetaProgressCircle(size: ZetaCircleSizes.s),
        ),
        NeurohubSessionStatus.error => _signInPrompt(
          message: session.message ?? 'Neurohub is unavailable right now.',
        ),
        NeurohubSessionStatus.signedOut => _signInPrompt(
          message: 'Connect your GitHub account to share Studio workspaces.',
        ),
        NeurohubSessionStatus.signedIn => _workspacesBody(),
      },
    );
  }

  Widget _signInPrompt({required String message}) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: NmtkEmptyState(
          title: 'Share workspaces from GitHub',
          message: message,
          icon: ZetaIcons.share,
          action: NmtkPrimaryButton(
            key: const Key('neurohub-share-sign-in'),
            label: 'Sign in to Neurohub',
            onPressed: _signIn,
          ),
        ),
      ),
    );
  }

  Widget _workspacesBody() {
    final workspacesAsync = ref.watch(neurohubWorkspacesProvider);
    return workspacesAsync.when(
      data: (workspaces) {
        final selectedOwner = _selectedOwner;
        final selectedSlug = _selectedSlug;
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 960;
            final list = _WorkspaceList(
              workspaces: workspaces,
              selectedOwner: selectedOwner,
              selectedSlug: selectedSlug,
              onSelect: _select,
            );
            final detail = _WorkspaceDetail(
              owner: selectedOwner,
              slug: selectedSlug,
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(width: 340, child: list),
                  const VerticalDivider(width: 1),
                  Expanded(child: detail),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(height: 260, child: list),
                const Divider(height: 1),
                Expanded(child: detail),
              ],
            );
          },
        );
      },
      loading: () =>
          const Center(child: ZetaProgressCircle(size: ZetaCircleSizes.s)),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: NmtkEmptyState(
            title: 'Could not load workspaces',
            message: error.toString(),
            icon: ZetaIcons.cloud_off,
            tone: NmtkTone.danger,
          ),
        ),
      ),
    );
  }
}

class _WorkspaceList extends StatelessWidget {
  const _WorkspaceList({
    required this.workspaces,
    required this.selectedOwner,
    required this.selectedSlug,
    required this.onSelect,
  });

  final List<NeurohubWorkspaceSummary> workspaces;
  final String? selectedOwner;
  final String? selectedSlug;
  final ValueChanged<NeurohubWorkspaceSummary> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        for (final workspace in workspaces)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              key: ValueKey<String>(
                'neurohub-share-workspace-${workspace.owner}-${workspace.slug}',
              ),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              onTap: () => onSelect(workspace),
              // Allowed: single-topic surface — one selectable workspace row.
              child: NmtkSurfaceCard(
                title: workspace.displayName,
                subtitle:
                    '${workspace.owner}/${workspace.slug} · '
                    '${_permissionLabel(workspace.permission)}',
                tone:
                    selectedOwner == workspace.owner &&
                        selectedSlug == workspace.slug
                    ? NmtkTone.info
                    : NmtkTone.neutral,
                child: const SizedBox.shrink(),
              ),
            ),
          ),
      ],
    );
  }

  static String _permissionLabel(String permission) {
    return switch (permission) {
      'admin' => 'Manage',
      'write' => 'Can save',
      _ => 'Read only',
    };
  }
}

class _WorkspaceDetail extends ConsumerWidget {
  const _WorkspaceDetail({required this.owner, required this.slug});

  final String? owner;
  final String? slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedOwner = owner;
    final selectedSlug = slug;
    if (selectedOwner == null || selectedSlug == null) {
      return const NmtkEmptyState(
        title: 'Select a workspace',
        message:
            'Choose a shared workspace on the left to preview its model, '
            'train, and evaluate stages.',
        icon: ZetaIcons.layers,
      );
    }
    final workspaceAsync = ref.watch(
      neurohubWorkspaceProvider((owner: selectedOwner, slug: selectedSlug)),
    );
    return workspaceAsync.when(
      data: (workspace) => _WorkspaceDetailContent(workspace: workspace),
      loading: () =>
          const Center(child: ZetaProgressCircle(size: ZetaCircleSizes.s)),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: NmtkEmptyState(
            title: 'Could not open workspace',
            message: error.toString(),
            icon: ZetaIcons.cloud_off,
            tone: NmtkTone.danger,
          ),
        ),
      ),
    );
  }
}

class _WorkspaceDetailContent extends ConsumerWidget {
  const _WorkspaceDetailContent({required this.workspace});

  final NeurohubWorkspace workspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit =
        workspace.permission == 'write' || workspace.permission == 'admin';
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Text(
          workspace.displayName,
          style: Zeta.of(context).textStyles.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          '${workspace.owner}/${workspace.slug}'
          '${workspace.private ? ' · private' : ' · public'}'
          ' · updated ${workspace.updatedAt}',
          style: Zeta.of(context).textStyles.bodyMedium,
        ),
        if (workspace.description.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(workspace.description),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            NmtkPrimaryButton(
              key: const Key('neurohub-share-preview'),
              label: 'Preview',
              icon: ZetaIcons.visibility,
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => Dialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: NmtkDesignTokens.dialogShape,
                  ),
                  child: SizedBox(
                    width: 960,
                    height: 640,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            workspace.displayName,
                            style: Zeta.of(context).textStyles.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: NeurohubWorkspacePreview(
                              payload: workspace.workspace,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            NmtkOutlinedButton(
              key: const Key('neurohub-share-open-repo'),
              label: 'Open on GitHub',
              icon: Icons.open_in_new,
              onPressed: () => ref
                  .read(neurohubExternalLinkLauncherProvider)
                  .open(workspace.repositoryUrl),
            ),
          ],
        ),
        if (!canEdit) ...<Widget>[
          const SizedBox(height: 16),
          const Text(
            'You can preview this workspace, but you cannot save changes to '
            'it. Ask its owner to add you as a collaborator, or save a copy '
            'from the Studio.',
          ),
        ],
      ],
    );
  }
}
