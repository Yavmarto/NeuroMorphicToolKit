import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/neurohub_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/neurohub_sign_in_dialog.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/share_workspace_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurohub_client.dart';

/// One selectable row in the "My workspace repos" list.
///
/// The repo set is already filtered server-side (topic `neurohub-workspace`
/// or a `workspace-` name prefix), so the client renders it as-is.
class WorkspaceRepoCard extends StatelessWidget {
  const WorkspaceRepoCard({super.key, required this.workspace, this.onTap});

  final NeurohubWorkspaceSummary workspace;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final textStyles = Zeta.of(context).textStyles;
    final permission = switch (workspace.permission) {
      'admin' => 'Owner',
      'write' => 'Can edit',
      _ => 'Read only',
    };

    return Semantics(
      button: true,
      label: 'Open workspace ${workspace.displayName}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // Allowed: single-topic surface — one selectable workspace row.
          child: NmtkSurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.folder_copy_outlined,
                    size: 20,
                    color: colors.mainSubtle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        workspace.displayName,
                        style: textStyles.titleMedium.copyWith(
                          color: colors.mainDefault,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${workspace.owner}/${workspace.slug}',
                        style: textStyles.bodySmall.copyWith(
                          color: colors.mainSubtle,
                        ),
                      ),
                      if (workspace.description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          workspace.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textStyles.bodyMedium.copyWith(
                            color: colors.mainSubtle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                NmtkStatusBadge(label: permission),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "My workspace repos" — the GitHub-backed workspace repositories visible to
/// the signed-in user.
///
/// Renders the already-server-filtered repo list, an empty state when the user
/// has none yet, and an error state with a retry action. A primary action opens
/// the "Share as new workspace repo" form; a newly created repo is then shown
/// in the refreshed list.
class WorkspaceReposScreen extends ConsumerStatefulWidget {
  const WorkspaceReposScreen({super.key, this.onWorkspaceSelected});

  /// Called when the user selects a repo. CEL-131c wires this to the "Commit
  /// workspace" screen.
  final ValueChanged<NeurohubWorkspaceSummary>? onWorkspaceSelected;

  @override
  ConsumerState<WorkspaceReposScreen> createState() =>
      _WorkspaceReposScreenState();
}

class _WorkspaceReposScreenState extends ConsumerState<WorkspaceReposScreen> {
  Future<void> _openShareScreen() async {
    final created = await Navigator.of(context).push<NeurohubWorkspace>(
      MaterialPageRoute<NeurohubWorkspace>(
        builder: (context) => const ShareWorkspaceScreen(),
      ),
    );
    if (created == null) return;
    // Refresh so the newly shared repo appears in the list.
    ref.invalidate(neurohubWorkspacesProvider);
  }

  Future<void> _connectGitHub() async {
    await showNeurohubSignInDialog(context);
    if (!mounted) return;
    ref.invalidate(neurohubWorkspacesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(neurohubSessionProvider);
    final workspaces = ref.watch(neurohubWorkspacesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'My workspace repos',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Repositories on your GitHub account that are shared '
                      'as Neurohub workspaces.',
                      style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                        color: Zeta.of(context).colors.mainSubtle,
                      ),
                    ),
                  ],
                ),
              ),
              NmtkPrimaryButton(
                key: const Key('share-new-workspace-repo-button'),
                label: 'Share new workspace repo',
                icon: Icons.add,
                onPressed: session.isSignedIn ? _openShareScreen : null,
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody(session, workspaces)),
      ],
    );
  }

  Widget _buildBody(
    NeurohubSessionState session,
    AsyncValue<List<NeurohubWorkspaceSummary>> workspaces,
  ) {
    if (!session.isSignedIn) {
      return NmtkEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Connect GitHub to share workspaces',
        message:
            'Sign in with your GitHub account to see and create your '
            'workspace repositories.',
        action: NmtkPrimaryButton(
          key: const Key('workspace-repos-connect-github'),
          label: 'Connect GitHub',
          onPressed: _connectGitHub,
        ),
      );
    }
    return workspaces.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Padding(
        padding: const EdgeInsets.all(24),
        child: NmtkErrorCard(
          key: const Key('workspace-repos-error'),
          title: 'Could not load your workspace repos',
          subtitle: 'Neurohub could not list your GitHub repositories.',
          message: error is NeurohubException
              ? neurohubWorkspaceErrorMessage(error)
              : 'Check your connection and try again.',
          action: NmtkPrimaryButton(
            key: const Key('workspace-repos-retry'),
            label: 'Retry',
            onPressed: () => ref.invalidate(neurohubWorkspacesProvider),
          ),
        ),
      ),
      data: (repos) {
        if (repos.isEmpty) {
          return NmtkEmptyState(
            key: const Key('workspace-repos-empty'),
            icon: Icons.folder_open_outlined,
            title: 'No workspace repos yet',
            message:
                'Share this workspace as a new repository to keep it in '
                'sync with GitHub.',
            action: NmtkPrimaryButton(
              key: const Key('workspace-repos-empty-share'),
              label: 'Share as new workspace repo',
              icon: Icons.add,
              onPressed: _openShareScreen,
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          itemCount: repos.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final repo = repos[index];
            return WorkspaceRepoCard(
              key: Key('workspace-repo-${repo.slug}'),
              workspace: repo,
              onTap: widget.onWorkspaceSelected == null
                  ? null
                  : () => widget.onWorkspaceSelected!(repo),
            );
          },
        );
      },
    );
  }
}
