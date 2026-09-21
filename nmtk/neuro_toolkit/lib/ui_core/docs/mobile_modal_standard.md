# Mobile modal / popup / bottom-sheet standard

Engineers auditing dialogs and sheets in the popup/dialog sweep should treat this
as the single source of truth. Check every dialog, sheet, and popup against all
seven rules below; note pass/fail per file in the closing audit comment.

**Canonical references in code**

| Pattern | File | What to copy |
|---|---|---|
| Simple action sheet | `lib/ui_core/widgets/mobile_scaffold.dart` → `_showFileActionsSheet` | `SafeArea`, `tokens.sectionGap` margin, `radiusLg` top corners, `ZetaListItem` rows |
| Adaptive dialog ↔ sheet | `lib/screens/server_access_popup.dart` | `compactBreakpoint` split, `isScrollControlled` + `useSafeArea` sheet, `SingleChildScrollView` body |
| Tall / draggable sheet | `lib/features/neurocnl/screens/canvas/canvas_screen.dart` → `_showMobileNodeSheet` | `DraggableScrollableSheet` with bounded `maxChildSize` |
| List picker sheet | `lib/features/neurocnl/widgets/canvas/canvas_connect_palette.dart` | `SafeArea`, `maxHeight: height * 0.8`, scrollable list body |

**Zeta components to prefer**

- **Simple confirm / message:** `ZetaDialog` or `showZetaDialog` (text-only body).
- **Rich structured body:** `NmtkContentDialog` (`lib/ui_core/widgets/content_dialog.dart`) on desktop; on mobile prefer a bottom sheet or a full-width dialog (see rule 1).
- **Action rows / pickers:** `ZetaListItem` (built-in 48 px min height — satisfies rule 4).
- **Icon close / toolbar actions:** `ZetaIconButton` (48 px tap target).
- **Primary / secondary actions:** `ZetaButton` — stack vertically on narrow widths (rule 5).

**Breakpoint**

Use `NmtkShellTokens.compactBreakpoint` (**840 px**). Below that width, treat the
surface as phone/tablet-portrait mobile. `MediaQuery.sizeOf(context).width <
NmtkShellTokens.compactBreakpoint` is the canonical test (same as
`NmtkAdaptiveLayout` and `showServerAccessPopup`).

**Spacing tokens**

| Token | Value | Use |
|---|---|---|
| `tokens.sectionGap` | 16 px | Outer padding, title-to-body gap, action block separation |
| `tokens.compactGap` | 8 px | Between sibling actions, chips, inline controls |
| `tokens.radiusLg` | 22 px | Top corners of bottom sheets |
| `NmtkDesignTokens.dialogShape` | 28 px radius | Centered `Dialog` surfaces on desktop |

Never use raw padding under 8 px around title, body, or actions unless Zeta's
own component inset already accounts for it.

**Minimum test widths**

Simulate at least **375 × 667** (iPhone SE class) and **390 × 844** (iPhone 14)
before marking an audit file pass.

---

## Checklist (all seven required)

### 1. No fixed desktop width on phones

`NmtkContentDialog` defaults to `maxWidth: 560` with no mobile branch. On viewports
below `compactBreakpoint`, the surface must **not** stay a narrow centered box
with wasted side margins.

**Pass when:**

- Width is `min(560, screenWidth - 2 * tokens.sectionGap)` or equivalent, **or**
- The popup is a bottom sheet on mobile (preferred for action lists and long forms), **or**
- `showDialog` is replaced by `showModalBottomSheet` below the breakpoint (see
  `showServerAccessPopup`, `showCanvasConnectPalette`).

**Fail when:** `BoxConstraints(maxWidth: 560)` (or any fixed px width) is applied
without a mobile override.

### 2. Content must scroll

Wrap dialog/sheet body in `SingleChildScrollView`, a `ListView`, or a
`DraggableScrollableSheet` whose child scrolls. Long forms and pickers must never
silently clip on short phones.

**Pass when:** Body scrolls independently of the action/footer row.

**Fail when:** A bare `Flexible` / `Expanded` wraps non-scrollable content and
the parent has no height cap with internal scroll (common overflow on 375 px
height).

### 3. SafeArea + keyboard insets

Sheets and dialogs that contain text fields must respect system insets.

**Required for bottom sheets:**

```dart
showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true, // when the sheet should respect bottom inset
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(
      top: Radius.circular(tokens.radiusLg),
    ),
  ),
  builder: (context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: /* scrollable body */,
      ),
    );
  },
);
```

Copy the **SafeArea + `tokens.sectionGap` margin + rounded top corners** recipe
from `_showFileActionsSheet`. For full-height flows (sign-in), see
`ServerAccessSheetSurface` + `server_access_popup.dart` (`isScrollControlled`,
`useSafeArea`, `SingleChildScrollView`).

**Note:** `viewInsets.bottom` padding is not yet applied everywhere in the tree;
new work and audits must add it anywhere `ZetaTextInput` appears inside a sheet.

### 4. Tap targets ≥ 44 × 44 logical px

Close buttons, action buttons, and list rows must meet Material / iOS minimums.

**Pass when:** Using `ZetaIconButton`, `ZetaButton`, or `ZetaListItem`, or
explicit `BoxConstraints(minWidth: 44, minHeight: 44)` / `SizedBox` 44 on
custom icon hits.

**Fail when:** Raw `IconButton` with default padding, dense `ListTile` with
`visualDensity: VisualDensity.compact`, or gesture detectors on areas smaller
than 44 px.

### 5. Stack actions vertically when there are more than two

On widths below `compactBreakpoint`, three or more actions must not share one
squeezed horizontal row.

**Pass when:** `Column` of full-width `ZetaButton`s, or `Wrap` with `direction:
Axis.vertical` / `WrapAlignment.stretch` on mobile.

**Fail when:** Three+ `TextButton`s in a single `Row` on a 375 px-wide viewport.

`NmtkContentDialog` currently uses `Wrap` for actions — verify `runSpacing` and
consider a mobile `Column` when auditing callers with 3+ actions.

### 6. Use design tokens for spacing

Use `tokens.sectionGap` and `tokens.compactGap` for padding and gaps. Flag any
ad-hoc `EdgeInsets` or `SizedBox` with values under 8 px between chrome and
content unless inherited from a Zeta component.

### 7. Never exceed viewport height without internal scrolling

Do not pin sheets or dialogs to a fixed height that can exceed the visible
viewport on SE-class devices.

**Pass when:**

- `maxHeight: MediaQuery.sizeOf(context).height * 0.8` (or similar cap) **and**
  internal scroll, **or**
- `DraggableScrollableSheet` with `maxChildSize ≤ 0.92`, **or**
- `mainAxisSize: MainAxisSize.min` on a scroll-wrapped column.

**Fail when:** `SizedBox(height: 720)` (or any fixed height) on a sheet without
scroll, or content that clips under the keyboard.

---

## Adaptive entry-point template

```dart
final isMobile =
    MediaQuery.sizeOf(context).width < NmtkShellTokens.compactBreakpoint;

if (isMobile) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(NmtkShellTokens.of(context).radiusLg),
      ),
    ),
    builder: (ctx) => /* SafeArea + scroll + token padding */,
  );
}

return showDialog<void>(
  context: context,
  builder: (ctx) => Dialog(
    shape: RoundedRectangleBorder(
      borderRadius: NmtkDesignTokens.dialogShape,
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
      child: /* scrollable body */,
    ),
  ),
);
```

---

## Audit comment template

When closing a per-file audit ticket, paste:

```
File: <path>
1 width: pass|fail — <note>
2 scroll: pass|fail
3 safe area / keyboard: pass|fail
4 tap targets: pass|fail
5 action layout: pass|fail
6 tokens: pass|fail
7 viewport height: pass|fail
Tested: 375×667 ☐  390×844 ☐
```
