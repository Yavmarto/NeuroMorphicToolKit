# Interfaces

## workspace_models.dart

```dart
class CachedSimulationResult {
  const CachedSimulationResult({
    required this.status,
    required this.savedAtIso8601,
    required this.durationSeconds,
    this.errorMessage,
    this.resultPayload,
  });

  final String status;
  final String savedAtIso8601;
  final double durationSeconds;
  final String? errorMessage;
  final Map<String, Object?>? resultPayload;

  factory CachedSimulationResult.fromJson(Map<String, Object?> json) {
    throw UnimplementedError();
  }

  Map<String, Object?> toJson() {
    throw UnimplementedError();
  }
}

class WorkspaceEntry {
  const WorkspaceEntry({
    required this.id,
    required this.name,
    required this.content,
    this.path,
    this.isDirty = false,
    this.isUntitled = true,
    this.cursorOffset = 0,
    this.selectionBase = 0,
    this.selectionExtent = 0,
    this.scrollOffset = 0,
    this.simulationCache,
  });

  final String id;
  final String name;
  final String content;
  final String? path;
  final bool isDirty;
  final bool isUntitled;
  final int cursorOffset;
  final int selectionBase;
  final int selectionExtent;
  final double scrollOffset;
  final CachedSimulationResult? simulationCache;

  factory WorkspaceEntry.fromJson(Map<String, Object?> json) {
    throw UnimplementedError();
  }

  Map<String, Object?> toJson() {
    throw UnimplementedError();
  }
}

class WorkspaceDocument {
  const WorkspaceDocument({
    required this.version,
    required this.savedAtIso8601,
    required this.files,
    required this.activeFileId,
    this.activePanel = 'parsed_specs',
    this.selectedTarget = 'teensy',
  });

  final int version;
  final String savedAtIso8601;
  final List<WorkspaceEntry> files;
  final String activeFileId;
  final String activePanel;
  final String selectedTarget;

  factory WorkspaceDocument.fromJson(Map<String, Object?> json) {
    throw UnimplementedError();
  }

  Map<String, Object?> toJson() {
    throw UnimplementedError();
  }
}
```

## workspace_models_test.dart

```dart
import 'package:test/test.dart';

import 'workspace_models.dart';

void main() {
  // Add tests for the examples in examples.md.
}
```

## Reference Notes

- Preserve file-scoped simulation ownership by nesting `simulationCache` inside `WorkspaceEntry`.
- JSON field names should be:
  - `savedAt`
  - `activeFileId`
  - `activePanel`
  - `selectedTarget`
  - `isDirty`
  - `isUntitled`
  - `cursorOffset`
  - `selectionBase`
  - `selectionExtent`
  - `scrollOffset`
  - `simulationCache`
