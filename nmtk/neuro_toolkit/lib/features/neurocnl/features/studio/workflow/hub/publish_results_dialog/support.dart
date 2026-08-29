import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/hub/publish_results_dialog/publish_results_dialog.dart';

/// Publish-to-Hub popup opened from the Review step's "Publish" action.
///
/// Replaces the old flow, which opened the full multi-tab [HubPopup] browser
/// just to reach [HubShareDialog]. This is a single-purpose dialog: a short
/// results summary on the left, the same three workspace-preview minimaps
/// used on Setup ([WorkspaceCanvasPreview]) on the right, and one visibility
/// choice before publishing.
Future<void> showPublishResultsDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => const PublishResultsDialog(),
);

/// Short, deduplicated summary of the workspace's latest result. The three
/// minimaps on the other side of the dialog already state each canvas's node
/// and edge counts, so this list sticks to run-level facts instead of
/// repeating them.

String publishResultTitleCase(String key) {
  final normalized = key.replaceAll('_', ' ').trim();
  if (normalized.isEmpty) return normalized;
  return normalized
      .split(' ')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}
