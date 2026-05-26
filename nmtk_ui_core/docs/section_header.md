# `NmtkSectionHeader` and `NmtkSection`

Flat, frame-less section primitives for NMTK studio surfaces. Introduced by
`zeta-card-reduction` Task 1.

## When to use

| Need | Use |
|---|---|
| Group multiple sub-elements under a heading without elevation | **`NmtkSection`** (header + child column, frame-less) |
| Just the header row (title + subtitle + status badge + actions) | **`NmtkSectionHeader`** |
| Single self-contained topic that genuinely needs elevation | `NmtkSurfaceCard` (still allowed, never nested) |
| Status banner ("All invariants passed", "Backend Support") | `NmtkStatusBanner` (Zeta `InPageBanner` wrapper) |
| Expandable list of items (Layer 1 / Layer 2) | `ZetaAccordion(inCard: false)` + `ZetaAccordionItem` |

## When NOT to use

- Don't wrap `NmtkSection` inside `NmtkSurfaceCard` — that re-introduces the
  heavy frame the migration removed.
- Don't reach for `NmtkSurfaceCard` as a generic "section divider". Reserve it
  for genuinely elevated single-topic surfaces.
- Don't replicate `NmtkSection` with a hand-rolled `Container + BoxDecoration`.
  The whole point is that the framework forbids the heavy frame; the
  governance test will fail in CI.

## Visual recipe

`NmtkSection` renders:

```
title (titleSmall, w700)
[subtitle in onSurfaceVariant]    ← optional
                                   ← childGap (default 12)
<child>
```

No background, no border, no rounded corners.

## Example

```dart
NmtkSection(
  title: 'Deploy targets',
  subtitle: 'Pick a hardware backend',
  trailing: Row(children: [ArtifactsButton(), TrainButton()]),
  child: ZetaSegmentedControl<String>(
    selected: selectedTarget,
    onChanged: onSelectTarget,
    segments: [
      for (final t in deployTargets)
        ZetaButtonSegment(
          value: t.id,
          icon: Icon(t.icon),
          label: Text(t.label),
        ),
    ],
  ),
);
```
