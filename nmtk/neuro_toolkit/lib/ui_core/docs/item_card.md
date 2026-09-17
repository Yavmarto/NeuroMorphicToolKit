# `NmtkItemCard` — Unified Inner-Row Card

`NmtkItemCard` is the canonical "row item" primitive for NMTK studio surfaces.
Every list of failure rows, parsed sentences, NIR nodes, or other in-section
items should render through this widget so the studio shell looks consistent
and any future restyle changes one file.

It is the **inner-row** counterpart to [`NmtkSurfaceCard`](../lib/widgets/surface_card.dart):

| Use… | …for |
| :--- | :--- |
| `NmtkSurfaceCard` (or its `NeurocnlSectionCard` wrapper) | The outer **section** chrome — the framed pane that hosts a title, subtitle, and a list of rows. |
| `NmtkItemCard` | A **single row** inside that pane. |

Do not nest `NmtkItemCard` inside another `NmtkItemCard`.

## API

```dart
NmtkItemCard(
  child: Widget,                      // required
  leading: Widget?,                   // optional icon / pill on the left
  trailing: Widget?,                  // optional icon / chip / chevron on the right
  tone: NmtkTone = NmtkTone.neutral,  // controls the left-edge accent only
  density: NmtkItemCardDensity = NmtkItemCardDensity.regular,
  onTap: VoidCallback?,               // when non-null, card becomes interactive
  semanticLabel: String?,             // optional Semantics label
  padding: EdgeInsetsGeometry?,       // override density padding (rare)
)
```

## Visual recipe (Zeta dark mode)

| Property | Token |
| :--- | :--- |
| Body background | `Zeta.of(context).colors.surfaceDefault` |
| Outline | 1 px `Zeta.of(context).colors.borderSubtle` |
| Radius | `NmtkShellTokens.radiusSm` (matches `NmtkSurfaceCard`) |
| Hover overlay (`onTap` set) | `Zeta.of(context).colors.surfaceHover` |
| Left-edge accent (3 px) | per-tone `Zeta.of(context).colors.border*` |

Body and outline never tint based on tone — tone is conveyed by the **left-edge accent only**, plus your own `leading` icon if you want to repeat the cue.

## Tone semantics

| `NmtkTone` | Accent token | Meaning |
| :--- | :--- | :--- |
| `neutral` | `borderSubtle` | No semantic emphasis. Default. |
| `info` | `borderInfo` | Informational. |
| `success` | `borderPositive` | Passed / healthy / OK. |
| `warning` | `borderWarning` | Approximate / degraded. |
| `danger` | `borderNegative` | Failed / error. |

When `ZetaProvider` is not in the tree (some widget tests), `NmtkItemCard`
falls back to `NmtkShellTokens` semantic colors so the widget still renders
without throwing.

## Density semantics

| `NmtkItemCardDensity` | Outer padding | Inner gap | Use for |
| :--- | :--- | :--- | :--- |
| `compact` | 8 px | 6 px | Stacks of short rows: parse sentences, validation messages. |
| `regular` | 12 px | 8 px | Roomier cards carrying more content: NIR node cards. |

If your `child` brings its own internal padding (e.g. an `ExpansionTile`),
pass `padding: EdgeInsets.zero` to suppress NmtkItemCard's outer padding
and let the child flow edge-to-edge inside the card outline.

## Examples

```dart
// Parse row — invalid sentence
NmtkItemCard(
  density: NmtkItemCardDensity.compact,
  tone: sentence.valid ? NmtkTone.neutral : NmtkTone.danger,
  leading: _LinePill(line: sentence.line),
  trailing: Icon(sentence.valid ? Icons.check : Icons.close),
  child: Text(sentence.raw),
);

// Validation row — warning
NmtkItemCard(
  density: NmtkItemCardDensity.compact,
  tone: NmtkTone.warning,
  onTap: () => selectInvariant(inv.name),
  leading: const Icon(Icons.warning_amber_rounded),
  child: Text(inv.description),
);

// NIR node card with its own ExpansionTile
NmtkItemCard(
  density: NmtkItemCardDensity.regular,
  padding: EdgeInsets.zero, // ExpansionTile owns its padding
  child: ExpansionTile(/* … */),
);
```

## Verification

* Pixel rendering is locked by golden tests under
  `test/widgets/item_card_golden_test.dart` (8-image matrix: 5 tones at
  `regular` density + `neutral`/`danger` at `compact`).
* Structural invariants (slot rendering, accent width, padding values, tap
  callback, no `InkWell` when `onTap` is null) are locked by
  `test/widgets/item_card_test.dart`.
* Consuming widgets in `neurocnl/frontend/test/widgets/` use the
  `*_no_nested_cards_test.dart` pattern to forbid raw `Card`/`BoxDecoration`
  row wrappers, asserting `NmtkItemCard` is the only row chrome.
