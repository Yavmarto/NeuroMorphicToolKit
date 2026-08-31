import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/neurohub_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurohub_client.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/workspace_slug.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/neurohub_sign_in_dialog.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/neurohub_workspace_preview.dart';

Future<void> saveCurrentWorkspaceToNeurohub(
  BuildContext context,
  WidgetRef ref, {
  required Map<String, dynamic> payload,
  required String workspaceName,
  required Future<void> Function(NeurohubWorkspace workspace) reloadWorkspace,
}) async {
  if (!ref.read(neurohubSessionProvider).isSignedIn) {
    final signedIn = await showNeurohubSignInDialog(context);
    if (!signedIn || !context.mounted) return;
  }

  final binding = ref.read(neurohubWorkspaceBindingProvider);
  if (binding == null) {
    await _createWorkspace(
      context,
      ref,
      payload: payload,
      initialName: workspaceName,
    );
    return;
  }
  if (!binding.canEdit) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      NmtkSnackBars.error(
        context,
        'You can preview this workspace, but you cannot save changes to it. Fork a private copy instead.',
      ),
    );
    return;
  }

  try {
    final saved = await ref
        .read(neurohubClientProvider)
        .updateWorkspace(
          binding.owner,
          binding.slug,
          baseCommit: binding.headRevision,
          workspace: payload,
          displayName: workspaceName,
        );
    _afterSave(ref, saved);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(NmtkSnackBars.success(context, 'Saved to Neurohub.'));
  } on NeurohubConflictException catch (conflict) {
    if (!context.mounted) return;
    await _resolveConflict(
      context,
      ref,
      binding: binding,
      conflict: conflict,
      localPayload: payload,
      workspaceName: workspaceName,
      reloadWorkspace: reloadWorkspace,
    );
  } on NeurohubException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(NmtkSnackBars.error(context, workspaceErrorMessage(error)));
  }
}

Future<void> _createWorkspace(
  BuildContext context,
  WidgetRef ref, {
  required Map<String, dynamic> payload,
  required String initialName,
}) async {
  final details = await showDialog<_WorkspaceCreateDetails>(
    context: context,
    builder: (context) => _CreateWorkspaceDialog(initialName: initialName),
  );
  if (details == null || !context.mounted) return;
  try {
    final saved = await ref
        .read(neurohubClientProvider)
        .createWorkspace(
          slug: details.slug,
          displayName: details.name,
          description: details.description,
          tags: details.tags,
          private: !details.isPublic,
          workspace: payload,
        );
    _afterSave(ref, saved);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      NmtkSnackBars.success(
        context,
        details.isPublic
            ? 'Published to Neurohub.'
            : 'Saved privately to Neurohub.',
      ),
    );
  } on NeurohubException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(NmtkSnackBars.error(context, workspaceErrorMessage(error)));
  }
}

void _afterSave(WidgetRef ref, NeurohubWorkspace saved) {
  ref.read(neurohubWorkspaceBindingProvider.notifier).bind(saved);
  ref.invalidate(neurohubWorkspacesProvider);
  ref.invalidate(
    neurohubWorkspaceProvider((owner: saved.owner, slug: saved.slug)),
  );
}

enum _ConflictChoice { reload, saveCopy, compare, keepEditing }

Future<void> _resolveConflict(
  BuildContext context,
  WidgetRef ref, {
  required NeurohubWorkspaceBinding binding,
  required NeurohubConflictException conflict,
  required Map<String, dynamic> localPayload,
  required String workspaceName,
  required Future<void> Function(NeurohubWorkspace workspace) reloadWorkspace,
}) async {
  NeurohubWorkspace remote;
  try {
    remote = await ref
        .read(neurohubClientProvider)
        .getWorkspace(binding.owner, binding.slug);
  } on NeurohubException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        NmtkSnackBars.error(context, workspaceErrorMessage(error)),
      );
    }
    return;
  }
  if (!context.mounted) return;

  var choice = await showDialog<_ConflictChoice>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _ConflictDialog(),
  );
  if (!context.mounted || choice == null) return;
  if (choice == _ConflictChoice.compare) {
    choice = await showDialog<_ConflictChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _WorkspaceCompareDialog(
        localPayload: localPayload,
        remotePayload: remote.workspace,
      ),
    );
  }
  if (!context.mounted ||
      choice == null ||
      choice == _ConflictChoice.keepEditing) {
    return;
  }
  if (choice == _ConflictChoice.reload) {
    await reloadWorkspace(remote);
    _afterSave(ref, remote);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        NmtkSnackBars.success(context, 'Loaded the latest saved version.'),
      );
    }
    return;
  }
  if (choice == _ConflictChoice.saveCopy) {
    await _createWorkspace(
      context,
      ref,
      payload: localPayload,
      initialName: '$workspaceName copy',
    );
  }
}

class _ConflictDialog extends StatelessWidget {
  const _ConflictDialog();

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('This workspace changed elsewhere'),
    content: const SizedBox(
      width: 520,
      child: Text(
        'Your work is still safe in Studio. Choose whether to load the latest saved version, keep your work as a new workspace, or compare both first.',
      ),
    ),
    actions: <Widget>[
      NmtkOutlinedButton(
        label: 'Keep editing',
        onPressed: () => Navigator.of(context).pop(_ConflictChoice.keepEditing),
      ),
      NmtkOutlinedButton(
        label: 'Compare changes',
        onPressed: () => Navigator.of(context).pop(_ConflictChoice.compare),
      ),
      NmtkOutlinedButton(
        label: 'Save as new workspace',
        onPressed: () => Navigator.of(context).pop(_ConflictChoice.saveCopy),
      ),
      NmtkPrimaryButton(
        label: 'Reload saved version',
        onPressed: () => Navigator.of(context).pop(_ConflictChoice.reload),
      ),
    ],
  );
}

class _WorkspaceCompareDialog extends StatelessWidget {
  const _WorkspaceCompareDialog({
    required this.localPayload,
    required this.remotePayload,
  });

  final Map<String, dynamic> localPayload;
  final Map<String, dynamic> remotePayload;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 900;
    final local = _ComparisonPane(
      title: 'Your Studio workspace',
      payload: localPayload,
    );
    final saved = _ComparisonPane(
      title: 'Latest saved workspace',
      payload: remotePayload,
    );
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: NmtkDesignTokens.dialogShape),
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 1180,
        height: 720,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Compare workspace changes',
                style: Zeta.of(context).textStyles.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Both previews are read-only. Nothing changes until you choose an action.',
              ),
              const SizedBox(height: 16),
              Expanded(
                child: compact
                    ? Column(
                        children: <Widget>[
                          Expanded(child: local),
                          const SizedBox(height: 16),
                          Expanded(child: saved),
                        ],
                      )
                    : Row(
                        children: <Widget>[
                          Expanded(child: local),
                          const SizedBox(width: 16),
                          Expanded(child: saved),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  NmtkOutlinedButton(
                    label: 'Keep editing',
                    onPressed: () =>
                        Navigator.of(context).pop(_ConflictChoice.keepEditing),
                  ),
                  NmtkOutlinedButton(
                    label: 'Save as new workspace',
                    onPressed: () =>
                        Navigator.of(context).pop(_ConflictChoice.saveCopy),
                  ),
                  NmtkPrimaryButton(
                    label: 'Reload saved version',
                    onPressed: () =>
                        Navigator.of(context).pop(_ConflictChoice.reload),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComparisonPane extends StatelessWidget {
  const _ComparisonPane({required this.title, required this.payload});

  final String title;
  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text(title, style: Zeta.of(context).textStyles.titleMedium),
      const SizedBox(height: 8),
      Expanded(
        child: NeurohubWorkspacePreview(payload: payload, compact: true),
      ),
    ],
  );
}

class _WorkspaceCreateDetails {
  const _WorkspaceCreateDetails({
    required this.name,
    required this.slug,
    required this.description,
    required this.tags,
    required this.isPublic,
  });

  final String name;
  final String slug;
  final String description;
  final List<String> tags;
  final bool isPublic;
}

class _CreateWorkspaceDialog extends StatefulWidget {
  const _CreateWorkspaceDialog({required this.initialName});

  final String initialName;

  @override
  State<_CreateWorkspaceDialog> createState() => _CreateWorkspaceDialogState();
}

class _CreateWorkspaceDialogState extends State<_CreateWorkspaceDialog> {
  late final TextEditingController _name;
  final _description = TextEditingController();
  final _tags = TextEditingController();
  bool _public = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    final slug = slugifyWorkspaceName(name);
    return AlertDialog(
      title: const Text('Save to Neurohub'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Workspaces start private. You can publish or invite collaborators later.',
              ),
              const SizedBox(height: 16),
              ZetaTextInput(
                key: const Key('neurohub-create-name'),
                controller: _name,
                label: 'Workspace name',
                onChange: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              ZetaTextInput(
                controller: _description,
                label: 'Description (optional)',
              ),
              const SizedBox(height: 12),
              ZetaTextInput(
                controller: _tags,
                label: 'Tags (optional)',
                placeholder: 'vision, akida, tutorial',
              ),
              const SizedBox(height: 16),
              ZetaCheckbox(
                value: _public,
                label: 'Publish for others to discover',
                onChanged: (value) => setState(() => _public = value),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        NmtkOutlinedButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        NmtkPrimaryButton(
          key: const Key('neurohub-create-save'),
          label: _public ? 'Publish' : 'Save privately',
          onPressed: name.isEmpty || slug.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  _WorkspaceCreateDetails(
                    name: name,
                    slug: slug,
                    description: _description.text.trim(),
                    tags: _tags.text
                        .split(',')
                        .map((tag) => tag.trim().toLowerCase())
                        .where((tag) => tag.isNotEmpty)
                        .toSet()
                        .take(20)
                        .toList(),
                    isPublic: _public,
                  ),
                ),
        ),
      ],
    );
  }
}

/// Turns a Neurohub API failure into a sentence naming the next step. The raw
/// exception only carries an HTTP status, which tells the user nothing about
/// what to do about it.
String workspaceErrorMessage(NeurohubException error) {
  switch (error.statusCode) {
    case 401:
    case 403:
      return 'Neurohub rejected your sign-in. Sign in again, then retry the save.';
    case 404:
      return 'That workspace is no longer on Neurohub. Save it as a new workspace instead.';
    case 413:
      return 'This workspace is too large for Neurohub. Remove unused datasets or exports, then retry.';
    case 429:
      return 'Neurohub is rate limiting this account. Wait a minute, then retry the save.';
    default:
      if (error.statusCode >= 500) {
        return 'Neurohub is unavailable right now. Your work is still saved locally — retry in a moment.';
      }
      return error.message.isEmpty
          ? 'Saving to Neurohub failed (HTTP ${error.statusCode}).'
          : 'Saving to Neurohub failed: ${error.message}';
  }
}
