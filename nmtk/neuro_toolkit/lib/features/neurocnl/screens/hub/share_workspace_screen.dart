import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/neurohub_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurohub_client.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/workspace_slug.dart';

/// Minimal fresh workspace document written to a newly shared repository.
///
/// The GitHub-backed store validates only that the payload is a JSON object
/// within size limits; a real canvas/CNL payload is committed later by the
/// "Commit workspace" surface (CEL-131c).
const Map<String, dynamic> kEmptyNeurohubWorkspacePayload = <String, dynamic>{
  'revision': 1,
  'nodes': <dynamic>[],
};

/// Maps a [NeurohubException] from the workspace endpoints to an actionable
/// message for the share form and repo list.
String neurohubWorkspaceErrorMessage(NeurohubException error) {
  switch (error.statusCode) {
    case 401:
    case 403:
      return 'Neurohub rejected your GitHub sign-in. Sign in again, then retry.';
    case 422:
      return 'A workspace with this name already exists or the name is not '
          'valid for GitHub. Try a different name.';
    case 413:
      return 'This workspace is too large for Neurohub (10 MB limit).';
    case 429:
      return 'Neurohub is rate limiting this account. Wait a minute, then retry.';
    default:
      if (error.statusCode >= 500) {
        return 'Neurohub is unavailable right now. Retry in a moment.';
      }
      return error.message.isEmpty
          ? 'The request failed (HTTP ${error.statusCode}).'
          : 'The request failed: ${error.message}';
  }
}

/// "Share as new workspace repo" — a form that creates a new private GitHub
/// repository through the Neurohub workspace API.
///
/// The user only supplies a name: the repo name/slug and the
/// `neurohub-workspace` topic tagging are decided server-side by the GitHub
/// workspace store. On success this screen pops with the created
/// [NeurohubWorkspace] so the caller can show it in the repo list.
class ShareWorkspaceScreen extends ConsumerStatefulWidget {
  const ShareWorkspaceScreen({super.key, this.initialName});

  /// Pre-filled workspace name, e.g. when forking a copy of an existing one.
  final String? initialName;

  @override
  ConsumerState<ShareWorkspaceScreen> createState() =>
      _ShareWorkspaceScreenState();
}

class _ShareWorkspaceScreenState extends ConsumerState<ShareWorkspaceScreen> {
  late final TextEditingController _nameController;
  bool _submitting = false;
  String? _errorMessage;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String? _validateName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'Enter a name for this workspace repo.';
    }
    if (slugifyWorkspaceName(trimmed).isEmpty) {
      return 'Name must contain at least one letter or number.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    final nameError = _validateName(_nameController.text);
    if (nameError != null) {
      setState(() => _nameError = nameError);
      return;
    }
    final name = _nameController.text.trim();
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final created = await ref
          .read(neurohubClientProvider)
          .createWorkspace(
            slug: slugifyWorkspaceName(name),
            displayName: name,
            workspace: kEmptyNeurohubWorkspacePayload,
            private: true,
          );
      if (!mounted) return;
      context.pop(created);
    } on NeurohubException catch (error) {
      if (error.statusCode == 401) {
        await ref
            .read(neurohubSessionProvider.notifier)
            .signOut(message: 'Your Neurohub sign-in expired. Sign in again.');
      }
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = neurohubWorkspaceErrorMessage(error);
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage =
            'Could not reach Neurohub. Check your connection and '
            'retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textStyles = Zeta.of(context).textStyles;
    final colors = Zeta.of(context).colors;
    final name = _nameController.text.trim();
    final slugPreview = slugifyWorkspaceName(name);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Share as new workspace repo'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Publish this workspace as a private GitHub repository '
                  'on your connected GitHub account.',
                  style: textStyles.bodyLarge.copyWith(
                    color: colors.mainSubtle,
                  ),
                ),
                const SizedBox(height: 20),
                NmtkTextInput(
                  key: const Key('share-workspace-name-field'),
                  controller: _nameController,
                  label: 'Workspace name',
                  placeholder: 'e.g. Gesture model',
                  errorText: _nameError,
                  onChange: (_) => setState(() {
                    _nameError = null;
                  }),
                ),
                  const SizedBox(height: 8),
                  Text(
                    slugPreview.isEmpty
                        ? 'Repo name is created from your workspace name.'
                        : 'Repo name: $slugPreview',
                    key: const Key('share-workspace-slug-preview'),
                    style: textStyles.bodySmall.copyWith(
                      color: colors.mainSubtle,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'The repository is private and tagged as a Neurohub '
                    'workspace automatically.',
                    style: textStyles.bodySmall.copyWith(
                      color: colors.mainSubtle,
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    NmtkErrorCard(
                      key: const Key('share-workspace-error'),
                      title: 'Could not share this workspace',
                      subtitle: 'The repository was not created.',
                      message: _errorMessage!,
                    ),
                  ],
                  const SizedBox(height: 24),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: NmtkOutlinedButton(
                        label: 'Cancel',
                        onPressed: _submitting ? null : () => context.pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: NmtkPrimaryButton(
                        key: const Key('share-workspace-submit'),
                        label: _submitting
                            ? 'Sharing…'
                            : 'Share as new workspace repo',
                        onPressed: _submitting ? null : _submit,
                      ),
                    ),
                  ],
                ),
                if (_submitting) ...[
                  const SizedBox(height: 16),
                  const Center(
                    child: ZetaProgressCircle(size: ZetaCircleSizes.s),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
