import 'package:flutter/foundation.dart';

import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/workspace_file.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/presentation/workspace_tab_file_view_data.dart';

/// Immutable workspace data rendered by the Studio tab strip.

class WorkspaceTabViewData {
  const WorkspaceTabViewData({
    required this.files,
    required this.activeFileId,
    required this.workspaceName,
  });

  factory WorkspaceTabViewData.fromState(WorkspaceState state) {
    return WorkspaceTabViewData(
      files: state.files
          .map(
            (file) => WorkspaceTabFileViewData(
              id: file.id,
              name: file.name,
              dirty: file.dirty,
            ),
          )
          .toList(growable: false),
      activeFileId: state.activeFileId,
      workspaceName: state.workspaceName,
    );
  }

  final List<WorkspaceTabFileViewData> files;
  final String activeFileId;
  final String workspaceName;

  @override
  bool operator ==(Object other) {
    return other is WorkspaceTabViewData &&
        other.activeFileId == activeFileId &&
        other.workspaceName == workspaceName &&
        listEquals(other.files, files);
  }

  @override
  int get hashCode =>
      Object.hash(activeFileId, workspaceName, Object.hashAll(files));
}
