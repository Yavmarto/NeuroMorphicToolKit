# Design Document: Studio Target-First Workflow

## Overview

This feature promotes deploy-target selection to a first-class, always-visible element in the Studio workspace. Instead of discovering target incompatibility after running the full pipeline, users see the currently-selected target at all times via a compact **`TargetChip`** in the pipeline-bar row. A live **`CompatibilityDot`** surfaces preflight results from the existing `nir-target-aware-preflight` spec without requiring navigation to the Deploy tab.

**Key design decisions:**

- `workspaceProvider.selectedDeployTarget` (already persisted) is the single source of truth. No new state field is introduced.
- `TargetChip` and `TargetPopover` are new widgets placed in `neurocnl/frontend/lib/widgets/target_chip.dart` and `neurocnl/frontend/lib/widgets/target_popover.dart`.
- `PipelineBar` (`pipeline_bar.dart`) is extended to read `selectedDeployTarget` and override the Deploy step's detail/status when no target is set.
- `_BackendSupportCard` in `validation_panel.dart` gains a single `Consumer` read of `workspaceProvider.selectedDeployTarget` to enrich its subtitle label.
- `_PipelineWorkspaceHeader` in `studio_screen.dart` adds the `TargetChip` to its existing `Row`, between the play-stop button and the `PipelineBar`.
- No hardware deploy panels, hardware providers, or `_HardwareTargetRow` are modified.

---

## Architecture

### Component Relationship

```
workspaceProvider.selectedDeployTarget  (single source of truth)
        │
        ├── TargetChip (reads + triggers setSelectedDeployTarget)
        │       └── CompatibilityDot (reads preflightProvider)
        │       └── TargetPopover (writes setSelectedDeployTarget)
        │
        ├── _PipelineWorkspaceHeader → PipelineBar (reads for Deploy step detail)
        │
        ├── _HardwareTargetRow in Deploy tab (already reads, unchanged)
        │
        └── _BackendSupportCard in ValidationPanel (reads for subtitle label)
```

### State Flow

```
User taps TargetChip / TargetPopover row
  → workspaceProvider.notifier.setSelectedDeployTarget(targetId)
  → workspaceProvider state rebuild (persisted to ServerConfigService)
  → All consumers rebuild via ref.watch(workspaceProvider.select(...))

preflightProvider (from nir-target-aware-preflight spec)
  → CompatibilityDot reads preflightProvider.status / level
  → Rebuilds independently of workspace state changes
```

No new providers are introduced. The `preflightProvider` lifecycle (when to run preflight for simulator targets) is owned by the `nir-target-aware-preflight` spec and is not duplicated here.

### File Plan

| File | Action |
|------|--------|
| `lib/widgets/target_chip.dart` | **New** — `TargetChip`, `CompatibilityDot` |
| `lib/widgets/target_popover.dart` | **New** — `TargetPopover` |
| `lib/screens/studio_screen.dart` | **Modify** — `_PipelineWorkspaceHeader` adds `TargetChip`; `PipelineBar` tap handler for Deploy step |
| `lib/widgets/pipeline_bar.dart` | **Modify** — Deploy step detail/status when no target |
| `lib/widgets/validation_panel.dart` | **Modify** — `_BackendSupportCard` subtitle enrichment |
| `test/widgets/target_chip_test.dart` | **New** — widget tests |
| `test/widgets/target_popover_test.dart` | **New** — popover tests |
| `test/screens/studio_pipeline_bar_test.dart` | **New** — integration tests |

---

## Components and Interfaces

### 1. `TargetChip` widget

**File:** `lib/widgets/target_chip.dart`

`TargetChip` is a `ConsumerWidget` (Riverpod). It reads `workspaceProvider.selectedDeployTarget` and `preflightProvider`, renders a styled chip, and delegates target switching to `TargetPopover`.

#### Pseudocode

```dart
// lib/widgets/target_chip.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import '../providers/workspace_provider.dart';
import '../providers/preflight_provider.dart'; // from nir-target-aware-preflight spec
import '../theme/app_theme.dart';
import 'target_popover.dart';

/// The set of simulator-only deploy target IDs that show a CompatibilityDot.
const _simulatorTargets = {'lava_sim', 'snntorch_sim'};

class TargetChip extends ConsumerWidget {
  const TargetChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = NmtkShellTokens.of(context);
    final selectedTarget = ref.watch(
      workspaceProvider.select((s) => s.selectedDeployTarget),
    );
    final isEmpty = selectedTarget.isEmpty;

    return _TargetChipContent(
      targetId: isEmpty ? null : selectedTarget,
      tokens: tokens,
    );
  }
}

class _TargetChipContent extends ConsumerStatefulWidget {
  const _TargetChipContent({required this.targetId, required this.tokens});

  final String? targetId;          // null = empty state
  final NmtkShellTokens tokens;

  @override
  ConsumerState<_TargetChipContent> createState() => _TargetChipContentState();
}

class _TargetChipContentState extends ConsumerState<_TargetChipContent> {
  OverlayEntry? _overlayEntry;

  void _openPopover() {
    if (_overlayEntry != null) {
      _closePopover();
      return;
    }
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (ctx) => TargetPopover(
        anchorOffset: offset,
        anchorSize: size,
        onClose: _closePopover,
        onSelectTarget: (id) {
          ref.read(workspaceProvider.notifier).setSelectedDeployTarget(id);
          _closePopover();
        },
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _closePopover() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final targetId = widget.targetId;
    final isOpen = _overlayEntry != null;

    if (targetId == null) {
      // Empty state
      return GestureDetector(
        onTap: _openPopover,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(
              color: AppTheme.border,
              style: BorderStyle.solid,
              // Dart doesn't have a dashed border API natively; use a subtle
              // double border or a CustomPainter for dashes. Default: solid muted.
            ),
          ),
          child: const Text(
            'Select target',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
      );
    }

    final targetData = _targetForId(targetId);
    final isSimulator = _simulatorTargets.contains(targetId);

    return GestureDetector(
      onTap: _openPopover,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isOpen
              ? AppTheme.primary.withValues(alpha: 0.14)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(
            color: isOpen ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              targetData.label,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isSimulator) ...[
              const SizedBox(width: 6),
              CompatibilityDot(tokens: tokens),
            ],
          ],
        ),
      ),
    );
  }
}
```

### 2. `CompatibilityDot` widget

`CompatibilityDot` is a small `ConsumerWidget` that reads `preflightProvider` and renders an 8 px circle.

```dart
/// 8 px filled circle showing preflight result for the current simulator target.
class CompatibilityDot extends ConsumerWidget {
  const CompatibilityDot({super.key, required this.tokens});

  final NmtkShellTokens tokens;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preflight = ref.watch(preflightProvider);

    final Color dotColor;
    Widget? child;

    switch (preflight.status) {
      case PreflightStatus.running:
        // Show a micro spinner instead of a static dot while running.
        return SizedBox(
          width: 8,
          height: 8,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: AppTheme.border,
          ),
        );
      case PreflightStatus.success:
        final level = preflight.level;
        if (level == 'exact' || level == 'approximate') {
          dotColor = tokens.healthyColor; // 0xFF22C55E
        } else {
          dotColor = tokens.errorColor; // 0xFFEF4444
        }
      case PreflightStatus.error:
        dotColor = tokens.errorColor;
      case PreflightStatus.idle:
      default:
        dotColor = AppTheme.border; // gray
    }

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: dotColor,
        shape: BoxShape.circle,
      ),
      child: child,
    );
  }
}
```

**Dot color decision table:**

| `PreflightStatus` | `level` | Dot color |
|-------------------|---------|-----------|
| `idle` | — | `AppTheme.border` (gray) |
| `running` | — | `CircularProgressIndicator` (gray stroke) |
| `success` | `"exact"` | `tokens.healthyColor` (`0xFF22C55E`) |
| `success` | `"approximate"` | `tokens.healthyColor` (`0xFF22C55E`) |
| `success` | `"unsupported"` | `tokens.errorColor` (`0xFFEF4444`) |
| `error` | — | `tokens.errorColor` (`0xFFEF4444`) |

Hardware targets never receive a `CompatibilityDot` — the check `_simulatorTargets.contains(targetId)` in `_TargetChipContentState.build` gates the dot.

### 3. `TargetPopover` widget

**File:** `lib/widgets/target_popover.dart`

`TargetPopover` uses `OverlayEntry` (already inserted by `_TargetChipContentState`) plus a `CompositedTransformFollower`-style manual positioning so it anchors below the chip without covering the pipeline bar. It is NOT a `Dialog` or `AlertDialog` — it does not use `NmtkDesignTokens.dialogShape`.

```dart
// lib/widgets/target_popover.dart

class TargetPopover extends ConsumerWidget {
  const TargetPopover({
    super.key,
    required this.anchorOffset,
    required this.anchorSize,
    required this.onClose,
    required this.onSelectTarget,
  });

  final Offset anchorOffset;
  final Size anchorSize;
  final VoidCallback onClose;
  final ValueChanged<String> onSelectTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = NmtkShellTokens.of(context);
    final selectedTarget = ref.watch(
      workspaceProvider.select((s) => s.selectedDeployTarget),
    );

    // Position the popover below the chip with 4 px gap.
    final top = anchorOffset.dy + anchorSize.height + 4;
    final left = anchorOffset.dx;

    return Stack(
      children: [
        // Dismiss layer — transparent full-screen tap target.
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
        ),
        // Popover container.
        Positioned(
          top: top,
          left: left,
          child: KeyboardListener(
            focusNode: FocusNode()..requestFocus(),
            onKeyEvent: (event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                onClose();
              }
            },
            child: Material(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(tokens.radiusMd),
              elevation: 8,
              shadowColor: Colors.black.withValues(alpha: 0.18),
              child: Container(
                width: 220,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(tokens.radiusMd),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final target in _deployTargets)
                      _PopoverTargetRow(
                        target: target,
                        selected: selectedTarget == target.id,
                        onTap: () => onSelectTarget(target.id),
                      ),
                    const Divider(height: 1, thickness: 1, color: AppTheme.border),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text(
                        'Configure device settings in the Deploy tab.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PopoverTargetRow extends StatelessWidget {
  const _PopoverTargetRow({
    required this.target,
    required this.selected,
    required this.onTap,
  });

  final _DeployTargetData target;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppTheme.primary : AppTheme.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        color: selected ? AppTheme.primary.withValues(alpha: 0.14) : null,
        child: Row(
          children: [
            Icon(target.icon, size: 16, color: fg),
            const SizedBox(width: 10),
            Text(
              target.label,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

**Implementation notes:**
- `_deployTargets` is the existing `const List<_DeployTargetData>` defined in `studio_screen.dart`. To avoid duplication it should be moved to `lib/services/studio_target_registry_service.dart` or a new `lib/models/deploy_target.dart` file, and imported by both `studio_screen.dart` and `target_popover.dart`.
- The popover does NOT use `showDialog` — no `ModalBarrier` is inserted. This satisfies Requirement 6.5.
- The `GestureDetector` dismiss layer uses `HitTestBehavior.translucent` so underlying widgets remain hittable after the popover closes.

### 4. `_PipelineWorkspaceHeader` integration

**Current widget tree** (from `studio_screen.dart`, `_PipelineWorkspaceHeader.build`):

```
Container (surface bg, bottom border)
  └─ LayoutBuilder
       └─ Row
            ├─ _PlayStopButton          (key: 'play-stop-button')
            ├─ SizedBox(width: gap)
            └─ Expanded
                 └─ PipelineBar(bare: true, ...)
```

**Modified widget tree** (this feature):

```
Container (surface bg, bottom border)
  └─ LayoutBuilder
       └─ Row
            ├─ _PlayStopButton          (key: 'play-stop-button')
            ├─ SizedBox(width: gap)
            ├─ TargetChip()             ← NEW
            ├─ SizedBox(width: gap)     ← NEW (same gap value)
            └─ Expanded
                 └─ PipelineBar(bare: true, ...)
```

The chip is placed between the play/stop button and the pipeline bar, which mirrors the visual reading order: "action → target → pipeline steps." The `gap` variable (`compactGap` or `12.0`) is reused for consistent spacing.

**Dart delta** (in `_PipelineWorkspaceHeader.build`):

```dart
// Before:
return Row(
  children: [
    button,
    SizedBox(width: gap),
    Expanded(
      child: PipelineBar(
        bare: true,
        activeStepId: activePanel,
        onStepSelected: onSelected,
      ),
    ),
  ],
);

// After:
return Row(
  children: [
    button,
    SizedBox(width: gap),
    const TargetChip(),   // <-- added
    SizedBox(width: gap),
    Expanded(
      child: PipelineBar(
        bare: true,
        activeStepId: activePanel,
        onStepSelected: onSelected,
        onDeployStepTapped: _handleDeployStepTap,  // see §5 below
      ),
    ),
  ],
);
```

`_PipelineWorkspaceHeader` is a `ConsumerWidget`, so `TargetChip` (also `ConsumerWidget`) can be inserted without widget-state complications.

### 5. Pipeline bar Deploy step interactivity

`PipelineBar` currently calls `onStepSelected(stepId)` for every step unconditionally. The Deploy step needs context-sensitive behavior:

- **No target selected** → open `TargetPopover` anchored to the Deploy step chip, do NOT navigate to the deploy panel.
- **Target selected** → navigate to the Deploy tab (existing `_setActivePanel('deploy')` behavior).

#### `PipelineBar` changes

Add an optional `onDeployStepTapped` callback:

```dart
class PipelineBar extends ConsumerWidget {
  const PipelineBar({
    super.key,
    this.bare = false,
    this.activeStepId,
    this.onStepSelected,
    this.onDeployStepTapped,  // ← new: context-aware override for Deploy step
  });

  final VoidCallback? onDeployStepTapped;
  // ...

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pipeline = ref.watch(pipelineProvider);
    final selectedTarget = ref.watch(
      workspaceProvider.select((s) => s.selectedDeployTarget),
    );
    final noTarget = selectedTarget.isEmpty;
    // ...

    // Deploy step
    NmtkPipelineStepData(
      id: 'deploy',
      label: l10n.deploy,
      status: noTarget ? NmtkStepStatus.idle : _mapStatus(_deployStatusFor(pipeline)),
      detail: noTarget ? 'Select a target' : _deployDetailFor(pipeline),
      onTap: onDeployStepTapped,   // ← passed through to NmtkPipelineStepData.onTap
    ),
    // ...
  }
}
```

#### `_PipelineWorkspaceHeader` changes

`_PipelineWorkspaceHeader` now holds a `GlobalKey` on the `TargetChip` so the popover can anchor to it when the Deploy step is tapped while no target is selected:

```dart
// In _PipelineWorkspaceHeader:
final _targetChipKey = GlobalKey(debugLabel: 'target-chip');
// ...

void _handleDeployStepTap(BuildContext context, WidgetRef ref) {
  final selectedTarget = ref.read(
    workspaceProvider.select((s) => s.selectedDeployTarget),
  );
  if (selectedTarget.isEmpty) {
    // Open TargetPopover anchored to the chip, same logic as TargetChip tap.
    // Access the chip state via the key if needed, or let TargetChip handle it
    // by calling a method exposed through the key.
    final chipState = _targetChipKey.currentState as _TargetChipContentState?;
    chipState?._openPopover();
  } else {
    onSelected('deploy');
  }
}
```

Alternatively (simpler, preferred): expose a `VoidCallback openPopover` from `TargetChip` through a `TargetChipController` if key access feels fragile. Given the widgets are in the same `_PipelineWorkspaceHeader` build, using `GlobalKey` is sufficient and idiomatic for Flutter UI triggers.

**Deploy step detail/status table:**

| `selectedDeployTarget` | `generateResult` | detail text | step status |
|------------------------|-----------------|-------------|-------------|
| `''` (empty) | any | `"Select a target"` | `NmtkStepStatus.idle` |
| non-empty | `null` | `null` or `"Available"` (existing) | existing logic |
| non-empty | non-null | `"Ready"` (existing) | `success` |

### 6. `_BackendSupportCard` target label

**File:** `lib/widgets/validation_panel.dart`

`_BackendSupportCard` currently renders `'${support.backend} • ${support.verdict}'` in its `NmtkShellStatusBadge` label. The only change is to enrich the subtitle when a simulator target is active.

The `_BackendSupportCard` is a `StatelessWidget` receiving a `BackendSupportResult`. It needs to become a `ConsumerWidget` (or accept the display label as a constructor param) to read `workspaceProvider`.

**Preferred approach:** change to `ConsumerWidget` (minimal diff, no prop-drilling):

```dart
// Before:
class _BackendSupportCard extends StatelessWidget {
  const _BackendSupportCard({required this.support});
  final BackendSupportResult support;

  @override
  Widget build(BuildContext context) {
    final status = neurocnlStatusFromVerdict(
      support.verdict,
      label: '${support.backend} • ${support.verdict}',
    );
    return NeurocnlSectionCard(
      title: 'Backend Support',
      subtitle: 'Support verdicts remain contract-driven...',
      // ...
    );
  }
}

// After:
class _BackendSupportCard extends ConsumerWidget {
  const _BackendSupportCard({required this.support});
  final BackendSupportResult support;

  static const _simulatorLabels = {
    'lava_sim': 'Lava simulator',
    'snntorch_sim': 'snnTorch simulator',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTarget = ref.watch(
      workspaceProvider.select((s) => s.selectedDeployTarget),
    );
    final simulatorLabel = _simulatorLabels[selectedTarget];

    // Use human-readable label when backend matches the selected simulator target.
    final displayBackend = (simulatorLabel != null &&
            support.backend == selectedTarget)
        ? simulatorLabel
        : support.backend;

    final statusLabel = 'Target: $displayBackend • ${support.verdict}';

    final status = neurocnlStatusFromVerdict(
      support.verdict,
      label: statusLabel,
    );

    return NeurocnlSectionCard(
      title: 'Backend Support',
      subtitle: statusLabel,
      // ... rest unchanged
    );
  }
}
```

This change only affects the label text shown to the user. Verdict logic, node lists, and warning display are completely unchanged.

---

## Data Models

### `_DeployTargetData` (shared)

Currently defined as a private class at the bottom of `studio_screen.dart`. To let `TargetPopover` and `TargetChip` share the same data without importing `studio_screen.dart`, move it to a new file:

**New file:** `lib/models/deploy_target.dart`

```dart
// lib/models/deploy_target.dart
import 'package:flutter/material.dart';

class DeployTargetData {
  const DeployTargetData({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}

const kSimulatorTargets = <String>{'lava_sim', 'snntorch_sim'};

const kDeployTargets = <DeployTargetData>[
  DeployTargetData(id: 'lava_sim',    label: 'Lava',          icon: Icons.bolt_outlined),
  DeployTargetData(id: 'snntorch_sim',label: 'snnTorch',       icon: Icons.auto_graph_outlined),
  DeployTargetData(id: 'teensy',      label: 'Teensy 4.1',     icon: Icons.memory_outlined),
  DeployTargetData(id: 'pynq',        label: 'PYNQ',           icon: Icons.developer_board_outlined),
  DeployTargetData(id: 'akida',       label: 'Akida',          icon: Icons.hub_outlined),
  DeployTargetData(id: 'lava',        label: 'Lava / Loihi2',  icon: Icons.settings_input_composite_outlined),
];

DeployTargetData deployTargetForId(String id) {
  for (final t in kDeployTargets) {
    if (t.id == id) return t;
  }
  return kDeployTargets.first;
}

String deployTargetLabel(String id) => deployTargetForId(id).label;
```

`studio_screen.dart` is updated to import from this file and alias `_DeployTargetData` usage to `DeployTargetData`. The private `_deployTargets` const and `_targetForId` / `_targetLabel` helpers become imports of the public equivalents. The existing `_DeployTargetData` type and `_deployTargets` list are removed from `studio_screen.dart`.

### `WorkspaceState.selectedDeployTarget`

No schema changes. The existing field (default `'teensy'`, persisted, restored on load) is the complete data model for target selection. `setSelectedDeployTarget` in `WorkspaceNotifier` is the only write path.

### `PreflightState` (from `nir-target-aware-preflight` spec)

Read-only from this feature's perspective. `CompatibilityDot` watches `preflightProvider` and uses:

```dart
preflight.status   // PreflightStatus enum
preflight.level    // String? — "exact" | "approximate" | "unsupported"
```

No writes to `preflightProvider` from this feature.

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

This feature is a Flutter widget feature involving UI state projection from a provider to multiple widget surfaces. The core logic — mapping a `selectedDeployTarget` string and `PreflightState` into visual output — contains universal properties that hold across all valid input combinations. PBT is therefore applicable for these logical projection functions, with the understanding that UI rendering tests use widget test harnesses (not pure functions).

---

### Property 1: CompatibilityDot color reflects preflight level for any simulator target

*For any* simulator target ID (`lava_sim`, `snntorch_sim`) and any valid `PreflightState`, the `CompatibilityDot`'s rendered color SHALL equal `tokens.healthyColor` when `level` is `"exact"` or `"approximate"`, `tokens.errorColor` when `level` is `"unsupported"` or `status` is `error`, and `AppTheme.border` (gray) when `status` is `idle`.

**Validates: Requirements 2.1, 2.2, 2.3**

---

### Property 2: Hardware targets never show a CompatibilityDot

*For any* hardware target ID (`teensy`, `pynq`, `akida`, `lava`) and any `PreflightState`, the `TargetChip` widget tree SHALL NOT contain a `CompatibilityDot` widget.

**Validates: Requirements 2.4, 11.1**

---

### Property 3: Target label round-trip display

*For any* non-empty target ID from the set of six valid deploy targets, the `TargetChip` SHALL display the same label string that `deployTargetLabel(id)` returns, and the `TargetPopover` SHALL list all six targets with their correct labels regardless of which target is currently selected.

**Validates: Requirements 1.3, 3.2**

---

### Property 4: Popover selection updates workspace state and closes

*For any* target ID `T` in the six valid deploy targets, tapping the corresponding row in the `TargetPopover` SHALL result in `workspaceProvider.selectedDeployTarget == T` and the popover SHALL be removed from the widget tree.

**Validates: Requirements 3.3, 4.3, 4.4**

---

### Property 5: Deploy step detail is "Select a target" iff selectedDeployTarget is empty

*For any* `WorkspaceState` where `selectedDeployTarget` is the empty string `''`, the `PipelineBar` Deploy step's detail text SHALL be `"Select a target"` and its `NmtkStepStatus` SHALL be `idle`. *For any* `WorkspaceState` where `selectedDeployTarget` is non-empty, the detail text and status SHALL follow the existing pipeline-state-derived logic (unchanged behavior).

**Validates: Requirements 5.3, 5.4**

---

### Property 6: Chip variant matches selectedDeployTarget non-emptiness

*For any* `WorkspaceState`, the `TargetChip` SHALL render its normal variant (label visible, `AppTheme.textPrimary`) when and only when `selectedDeployTarget` is a non-empty string, and SHALL render its empty-state variant ("Select target", `AppTheme.textSecondary`) when and only when `selectedDeployTarget` is the empty string.

**Validates: Requirements 1.3, 1.5, 6.4**

---

### Property 7: _BackendSupportCard subtitle label for simulator targets

*For any* `BackendSupportResult` whose `backend` field equals `selectedDeployTarget`, and for any `selectedDeployTarget` in `{'lava_sim', 'snntorch_sim'}`, the `_BackendSupportCard` subtitle SHALL begin with `"Target: "` followed by the human-readable label (`"Lava simulator"` or `"snnTorch simulator"`). *For any* hardware target or empty target, the subtitle SHALL use the backend string exactly as returned by the validation result.

**Validates: Requirements 7.1, 7.2, 7.3**

---

### Property 8: Target selection persists across workspace serialization round-trip

*For any* valid target ID `T`, calling `workspaceProvider.notifier.setSelectedDeployTarget(T)` followed by serializing `WorkspaceState.toJson()` and deserializing with `WorkspaceState.fromJson(...)` SHALL yield a state where `selectedDeployTarget == T`.

**Validates: Requirements 8.1, 8.2**

---

## Error Handling

### Preflight provider unavailable

If the `nir-target-aware-preflight` spec's `preflightProvider` is not yet registered (e.g. during early app boot or in a test context where it is not overridden), `CompatibilityDot` treats the state as `PreflightStatus.idle` and renders a gray dot. No exception is thrown.

### `OverlayEntry` lifecycle

`_TargetChipContentState` holds a nullable `_overlayEntry`. On widget `dispose`, the entry is removed. If the chip is removed while the popover is open (e.g. the panel collapses), `dispose` guarantees cleanup. Tapping the chip while the popover is already open toggles it closed (guard: `if (_overlayEntry != null) { _closePopover(); return; }`).

### `targetId` not in `kDeployTargets`

`deployTargetForId` falls back to `kDeployTargets.first` (Lava simulator) for unknown IDs — matching the existing `_targetForId` fallback behavior. This prevents a crash if a future workspace file contains a target ID not yet in the enum.

### Empty `selectedDeployTarget`

`WorkspaceState.selectedDeployTarget` defaults to `'teensy'`, so the empty-string case is only reachable via a programmatic clear (e.g. future "no target" affordance) or a corrupted workspace payload. The chip's empty-state branch handles this gracefully without any error state.

### Popover positioning near screen edges

The `TargetPopover` is positioned at `anchorOffset.dy + anchorSize.height + 4` from the top. If the chip is near the bottom of the screen, the popover could be clipped. A production-ready implementation should clamp `top` to `MediaQuery.of(context).size.height - popoverHeight - 8`. This clamping logic belongs in `TargetPopover.build` and should use a `LayoutBuilder` or a two-pass render if the popover height is unknown.

---

## Testing Strategy

### Approach

This feature uses a **dual testing approach**:

- **Widget tests** for specific chip rendering states, popover open/close interactions, and structural assertions (no `ModalBarrier`, correct token usage).
- **Property-based tests** for the logical projection functions (dot color mapping, chip variant mapping, deploy step detail mapping, backend label mapping, serialization round-trip).

The PBT library for Dart is **[`dart_test_annotations`](https://pub.dev/packages/test) with [`fast_check`](https://pub.dev/packages/fast_check)** or the established **`package:propcheck`**. Given the codebase already uses `flutter test`, the simplest approach is to use `package:test`'s parameterized test utilities or add `package:propcheck` as a dev dependency. Each property test runs a minimum of **100 iterations**.

Unit tests should focus on specific examples and edge cases. Property tests cover the universal input-space behaviors.

---

### Widget Tests: `test/widgets/target_chip_test.dart`

```dart
// Feature: studio-target-first-workflow

group('TargetChip', () {
  // ── Empty state ────────────────────────────────────────────────────────────

  testWidgets('empty state renders "Select target" with no CompatibilityDot', (tester) async {
    // Overrides workspaceProvider with selectedDeployTarget = ''
    await tester.pumpWidget(
      buildTestApp(overrides: [
        workspaceProvider.overrideWith((_) => WorkspaceNotifier.forTesting(target: '')),
        preflightProvider.overrideWith((_) => PreflightNotifier.idle()),
      ]),
    );
    expect(find.text('Select target'), findsOneWidget);
    expect(find.byType(CompatibilityDot), findsNothing);
    // Assert no ModalBarrier in tree (Req 6.5)
    expect(find.byType(ModalBarrier), findsNothing);
  });

  // ── Simulator target — three dot states ────────────────────────────────────
  // Property 1: studio-target-first-workflow, Property 1: CompatibilityDot color reflects preflight level

  testWidgets('snntorch_sim + preflight success/exact → green dot', (tester) async {
    await tester.pumpWidget(buildTestApp(overrides: [
      workspaceProvider.overrideWith((_) => WorkspaceNotifier.forTesting(target: 'snntorch_sim')),
      preflightProvider.overrideWith((_) => PreflightNotifier.withState(
        PreflightState(status: PreflightStatus.success, level: 'exact'),
      )),
    ]));
    final dot = tester.widget<Container>(
      find.descendant(of: find.byType(CompatibilityDot), matching: find.byType(Container)),
    );
    expect((dot.decoration as BoxDecoration).color, const Color(0xFF22C55E));
  });

  testWidgets('snntorch_sim + preflight success/approximate → green dot', (tester) async { /* ... */ });

  testWidgets('lava_sim + preflight success/unsupported → red dot', (tester) async {
    // dot color = tokens.errorColor = 0xFFEF4444
  });

  testWidgets('lava_sim + preflight idle → gray dot (AppTheme.border)', (tester) async { /* ... */ });

  testWidgets('lava_sim + preflight running → CircularProgressIndicator shown', (tester) async { /* ... */ });

  // ── Hardware target — no dot ───────────────────────────────────────────────
  // Property 2: studio-target-first-workflow, Property 2: Hardware targets never show CompatibilityDot

  for (final hw in ['teensy', 'pynq', 'akida', 'lava']) {
    testWidgets('hardware target $hw shows no CompatibilityDot', (tester) async {
      await tester.pumpWidget(buildTestApp(overrides: [
        workspaceProvider.overrideWith((_) => WorkspaceNotifier.forTesting(target: hw)),
        preflightProvider.overrideWith((_) => PreflightNotifier.idle()),
      ]));
      expect(find.byType(CompatibilityDot), findsNothing);
      expect(find.text(deployTargetLabel(hw)), findsOneWidget);
    });
  }
});
```

---

### Widget Tests: `test/widgets/target_popover_test.dart`

```dart
group('TargetPopover', () {
  testWidgets('tapping TargetChip opens TargetPopover with all 6 targets', (tester) async {
    // Pump StudioScreen or a minimal scaffold containing TargetChip.
    // Tap TargetChip → expect TargetPopover in widget tree
    // Expect all 6 target labels are present in the overlay
  });

  testWidgets('selecting a target in popover updates workspaceProvider and closes popover', (tester) async {
    // Tap TargetChip → popover opens
    // Tap 'snnTorch' row → workspaceProvider.selectedDeployTarget == 'snntorch_sim'
    // Expect TargetPopover no longer in widget tree
  });

  testWidgets('tapping outside popover closes it without changing selection', (tester) async {
    // Tap TargetChip → popover opens
    // Tap outside → popover removed, selection unchanged
  });

  testWidgets('popover shows configure note text', (tester) async {
    expect(
      find.text('Configure device settings in the Deploy tab.'),
      findsOneWidget,
    );
  });

  testWidgets('popover has no ModalBarrier (Req 6.5)', (tester) async {
    // After tap, assert find.byType(ModalBarrier) finds nothing
  });

  testWidgets('currently selected target row has primary tinting', (tester) async {
    // Pump with snntorch_sim selected
    // Tap chip → popover open
    // Find the 'snnTorch' row Container → color == AppTheme.primary.withValues(alpha: 0.14)
  });

  testWidgets('Escape key closes popover without changing selection', (tester) async {
    // Tap chip → popover open
    // Send Escape key event → popover removed, selection unchanged
  });
});
```

---

### Integration Tests: `test/screens/studio_pipeline_bar_test.dart`

```dart
group('Pipeline bar + TargetChip integration', () {
  testWidgets(
    'Deploy step shows "Select a target" and opens popover when no target selected',
    (tester) async {
      // Pump with selectedDeployTarget = ''
      // Assert Deploy step detail text == 'Select a target'
      // Tap Deploy step → assert TargetPopover in widget tree (no panel navigation)
    },
  );

  testWidgets(
    'Deploy step navigates to deploy tab when target is already selected',
    (tester) async {
      // Pump with selectedDeployTarget = 'snntorch_sim'
      // Tap Deploy step → assert panel changed to 'deploy' (no popover)
    },
  );

  testWidgets(
    'Switching target from popover propagates to TargetChip label AND _HardwareTargetRow selected tile',
    (tester) async {
      // Pump with selectedDeployTarget = 'teensy'
      // Open TargetChip popover
      // Tap 'snnTorch' row
      // Assert TargetChip shows 'snnTorch' label
      // Navigate to deploy tab
      // Assert snntorch_sim _TargetNavTile is selected (has primary tinting)
    },
  );

  testWidgets(
    'lava_sim + unsupported preflight → CompatibilityDot is errorColor, Deploy step shows status',
    (tester) async {
      // Pump with lava_sim selected, preflightProvider returns success/unsupported
      // Assert CompatibilityDot color == tokens.errorColor
      // Assert Deploy step NmtkStepStatus follows existing generate status logic
    },
  );
});
```

---

### Property-Based Tests: `test/logic/target_chip_properties_test.dart`

These tests exercise the pure mapping functions extracted from the widget logic — no UI pump required.

```dart
// Feature: studio-target-first-workflow

// Property 1: CompatibilityDot color reflects preflight level for any simulator target
test('dot color maps correctly for all simulator x level combinations', () {
  // Tag: Feature: studio-target-first-workflow, Property 1: CompatibilityDot color reflects preflight level
  const simulatorTargets = ['lava_sim', 'snntorch_sim'];
  const levels = ['exact', 'approximate', 'unsupported'];
  for (final target in simulatorTargets) {
    for (final level in levels) {
      final state = PreflightState(status: PreflightStatus.success, level: level);
      final color = dotColorForPreflightState(state);
      if (level == 'exact' || level == 'approximate') {
        expect(color, const Color(0xFF22C55E)); // healthyColor
      } else {
        expect(color, const Color(0xFFEF4444)); // errorColor
      }
    }
  }
  // Also test idle and running
  expect(dotColorForPreflightState(PreflightState(status: PreflightStatus.idle)), AppTheme.border);
});

// Property 5: Deploy step detail is "Select a target" iff selectedDeployTarget is empty
// Tag: Feature: studio-target-first-workflow, Property 5: Deploy step detail maps to empty-target guidance
test('deployStepDetail returns "Select a target" for empty target, existing logic otherwise', () {
  expect(deployDetailFor(pipeline: PipelineState(), selectedTarget: ''), 'Select a target');
  expect(deployStatusFor(pipeline: PipelineState(), selectedTarget: ''), NmtkStepStatus.idle);

  final pipelineWithResult = PipelineState(generateStatus: StepStatus.success, generateResult: mockResult);
  expect(deployDetailFor(pipeline: pipelineWithResult, selectedTarget: 'snntorch_sim'), 'Ready');
});

// Property 6: Chip variant matches selectedDeployTarget non-emptiness
// Tag: Feature: studio-target-first-workflow, Property 6: Chip variant matches non-emptiness
test('targetChipVariant is empty for empty string, normal for any valid target ID', () {
  expect(chipVariantForTarget(''), TargetChipVariant.empty);
  for (final target in kDeployTargets) {
    expect(chipVariantForTarget(target.id), TargetChipVariant.normal);
  }
});

// Property 7: _BackendSupportCard subtitle label for simulator targets
// Tag: Feature: studio-target-first-workflow, Property 7: BackendSupportCard subtitle label
test('backendDisplayLabel returns human-readable label for simulator, raw for hardware', () {
  expect(backendDisplayLabel('lava_sim', 'lava_sim'), 'Lava simulator');
  expect(backendDisplayLabel('snntorch_sim', 'snntorch_sim'), 'snnTorch simulator');
  // Hardware — backend label passed through unchanged
  expect(backendDisplayLabel('nir', 'teensy'), 'nir');
  expect(backendDisplayLabel('nir', ''), 'nir');
});

// Property 8: Target selection persists across workspace serialization round-trip
// Tag: Feature: studio-target-first-workflow, Property 8: Serialization round-trip
test('WorkspaceState toJson/fromJson preserves selectedDeployTarget for all valid targets', () {
  for (final target in kDeployTargets) {
    final state = WorkspaceState(
      files: const [],
      activeFileId: '',
      selectedDeployTarget: target.id,
    );
    final json = state.toJson();
    final restored = WorkspaceState.fromJson(json);
    expect(restored.selectedDeployTarget, target.id);
  }
  // Default for missing field
  final stateNoTarget = WorkspaceState.fromJson({'files': [], 'activeFileId': ''});
  expect(stateNoTarget.selectedDeployTarget, 'teensy');
});
```

Note: For properties 1 and 6, the "for all" statement ranges over a small finite set (6 targets × 5 preflight states = 30 combinations). This is complete enumeration; a PBT library would generate the same space. These are written as parameterized loops for clarity but can be expressed as `prop` in `package:propcheck` with appropriate generators.

---

### Extractable pure functions for testability

The widget logic should extract these pure helper functions so they can be unit/property tested without pumping a Flutter widget:

```dart
// lib/widgets/target_chip.dart (or lib/models/deploy_target.dart)

/// Maps PreflightState to dot color. Pure function — testable without UI.
Color dotColorForPreflightState(PreflightState state, NmtkShellTokens tokens) {
  switch (state.status) {
    case PreflightStatus.success:
      final level = state.level;
      if (level == 'exact' || level == 'approximate') return tokens.healthyColor;
      return tokens.errorColor;
    case PreflightStatus.error:
      return tokens.errorColor;
    case PreflightStatus.idle:
    case PreflightStatus.running:
      return AppTheme.border;
  }
}

// lib/widgets/pipeline_bar.dart

/// Returns the deploy step detail text. Pure function — testable without UI.
String? deployDetailFor({required PipelineState pipeline, required String selectedTarget}) {
  if (selectedTarget.isEmpty) return 'Select a target';
  if (pipeline.generateResult != null) return 'Ready';
  if (pipeline.validateResult?.overall == true) return 'Available';
  return null;
}

/// Returns the deploy step NmtkStepStatus. Pure function — testable without UI.
NmtkStepStatus deployStatusFor({required PipelineState pipeline, required String selectedTarget}) {
  if (selectedTarget.isEmpty) return NmtkStepStatus.idle;
  return _mapStatus(_deployStatusFor(pipeline)); // existing logic
}

// lib/widgets/validation_panel.dart

/// Returns the display backend label for the BackendSupportCard. Pure function.
String backendDisplayLabel(String supportBackend, String selectedTarget) {
  const labels = {'lava_sim': 'Lava simulator', 'snntorch_sim': 'snnTorch simulator'};
  if (labels.containsKey(selectedTarget) && supportBackend == selectedTarget) {
    return labels[selectedTarget]!;
  }
  return supportBackend;
}
```

Extracting these functions makes the codebase more testable and keeps the widget `build` methods thin.

---

### Testing checklist (maps to Requirement 9 and 10)

| Test | Requirement |
|------|-------------|
| `TargetChip` renders label + green dot for exact/approximate | Req 9.1 |
| `TargetChip` renders red dot for unsupported | Req 9.1 |
| `TargetChip` renders gray dot for idle | Req 9.1 |
| `TargetChip` tap opens popover, selection updates provider | Req 9.2 |
| `TargetChip` empty state renders, tap opens popover | Req 9.3 |
| Hardware target shows no dot | Req 9.4 |
| Deploy step "Select a target" + tap → popover (no target) | Req 10.1 |
| lava_sim unsupported → red dot, deploy step status | Req 10.2 |
| Switching target in popover propagates to chip + HardwareTargetRow | Req 10.3 |
