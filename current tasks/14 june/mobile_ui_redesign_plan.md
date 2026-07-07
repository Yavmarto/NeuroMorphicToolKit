# Mobile UI Redesign Plan

## Verified Implementation Status (2026-07-04)

**Status: PARTIAL.** Phases 1 and 2 (the `nmtk_ui_core` scaffold/header/nav work) are substantially done and confirmed by real commits; Phase 3 (per-module content adaptation) is only barely started.

- **Phase 1 (Scaffold & Header):** DONE. `NmtkMobileScaffold` was extracted into its own file, `nmtk_ui_core/lib/widgets/mobile_scaffold.dart` (411 lines), separate from `desktop_scaffold.dart`, and is exported from `nmtk_ui_core/nmtk_ui_core.dart`. The mobile app bar height was raised to `64.0` (`mobile_scaffold.dart:274`, vs. the plan's desktop `_kContentHeaderHeight = 44.0` still used only for desktop in `desktop_scaffold.dart:23,817`). File actions (`New`/`Open`/`Save`/`Save As`) were moved into a `showModalBottomSheet` with `ZetaListItem` entries (`mobile_scaffold.dart:101,125-160`) rather than sitting in the app bar row. Git history confirms real iterative work: commits `89f8156` ("mobile migration"), `5c2dbd9` ("mobile UI canvas"), `1a6a9fc` ("feat(mobile): remove shell nav bar/settings btn, float studio top bar"), `31beefb`/`3e8e93d`/`e19ed31` (Zeta-typography and hamburger fixes).
- **Phase 2 (Navigation & Drawer):** DONE. `_NmtkMobileDrawer` (`mobile_scaffold.dart:324-411`) uses `ZetaListItem` for nav destinations and wraps a Material `Drawer`; the bottom nav uses `NavigationBar` (`mobile_scaffold.dart:225-227`) styled via the same widget tree. Profile/account access goes through the bottom sheet described above rather than a separate popover, consistent with the plan's intent.
- **Phase 3 (Content-Level Adaptation):** PARTIAL/MOSTLY NOT STARTED. `NmtkAdaptiveLayout` (the planned `desktopBuilder`/`mobileBuilder` helper) does exist at `nmtk_ui_core/lib/widgets/adaptive_layout.dart` with a 840px breakpoint, but it has only one real consumer found in product code: `neurocnl/frontend/lib/widgets/quantization_curve_chart.dart:22`. No evidence of split-panes (CNL editor + Canvas) being converted to `ZetaSegmentedControl` tabs on mobile. `DataTable` usage still exists un-converted in `Neurobench/frontend/lib/widgets/benchmark_results_table.dart` and `metric_diff_table.dart` (tables-to-lists conversion not done). The top-level `ResponsiveScaffold` in `nmtk_ui_core/lib/app_theme.dart:365-420` still renders the same `body` widget for both the mobile and desktop branches (lines 388-390 vs. 405+), i.e. the "Identical View Trees" issue called out in the plan's Key Issue #1 is not fully resolved at that call site.

**What's missing:** Phase 3's per-product-module adaptation (NeuroCNL, Neurohub, etc. converting split-panes/tables/forms for mobile) has not meaningfully started — only the shared `nmtk_ui_core` scaffold plumbing (Phases 1-2) is in place.

---

## 1. Current State Analysis

The current mobile implementation (handled mostly within `nmtk_ui_core/lib/widgets/desktop_scaffold.dart` and `app_theme.dart`) suffers from the "crammed desktop" syndrome.

### Key Issues Identified:
1. **Identical View Trees:** `NmtkDesktopScaffold` and `ResponsiveScaffold` use the exact same `child` widget for both desktop and mobile. If a screen contains a dense data table or a split-pane view (e.g., CNL Code Editor next to a Canvas), it simply shrinks down, resulting in a cluttered, unreadable mobile interface.
2. **Cramped, Desktop-Density App Bar:** `_NmtkMobileAppBar` forces a desktop density height (`_kContentHeaderHeight = 44.0`) onto mobile. Worse, it attempts to fit up to 9 distinct items in a single horizontal row (`Menu`, `Back`, `Title`, `New`, `Open`, `Save`, `Save As`, `Settings`, `Profile`).
3. **Violations of Touch Ergonomics:** Icons in the mobile app bar are sized at 18px or 20px with minimal padding, making them virtually impossible to accurately tap on a real device. Mobile touch targets should be 48x48px minimum.
4. **Underutilization of Zeta on Mobile:** While desktop heavily leans on Zeta UI tokens, the mobile layout falls back to raw Material 3 (`NavigationBar`, `Drawer`) without proper Zeta token styling or components (`ZetaListItem`, `ZetaAvatar`, etc.).

---

## 2. Redesign Principles (Zeta-First)

- **The desktop UI is untouched.** All changes will be additive or conditionally rendered for screens `< 600px`.
- **Mobile Paradigms:** Rely on bottom sheets, FABs (Floating Action Buttons), and segmented controls instead of desktop top-bars and split-panes.
- **Zeta Elements:** Use `ZetaListItem` for vertical menus, `ZetaSegmentedControl` for tabbed views, `ZetaAvatar` for profiles, and ensure tap targets use Zeta's spacing and size tokens (`ZetaWidgetSize.large`).

---

## 3. Execution Plan

### Phase 1: Scaffold & Header Overhaul
*Targeting `nmtk_ui_core`*
1. **Extract `NmtkMobileScaffold`:** Move the mobile rendering logic out of `NmtkDesktopScaffold` into a dedicated widget to allow for greater flexibility without polluting desktop code.
2. **Fix the App Bar:**
   - Increase `_NmtkMobileAppBar` height to standard mobile `56px` (or `64px`).
   - Remove file actions (`New`, `Open`, `Save`, `Save As`) from the header.
   - Replace the settings icon and profile chip with a combined "Account/More" avatar that opens a `ZetaBottomSheet`.
3. **Introduce Mobile File Actions:** Create a "More Actions" bottom sheet or a Floating Action Button (FAB) menu for file operations.

### Phase 2: Navigation & Drawer Refresh
*Targeting `nmtk_ui_core`*
1. **Zeta Drawer:** Refactor `_NmtkMobileDrawer` to use `ZetaListItem` for all navigation destinations.
2. **Bottom Navigation:** Ensure the `NavigationBar` is strictly styled with `Zeta.of(context).colors` and uses `ZetaIcons`.
3. **Profile Menu:** Ensure `NmtkUserProfile` interactions trigger a mobile-friendly bottom sheet list rather than a desktop popover.

### Phase 3: Content-Level Adaptation
*Targeting Product Modules (NeuroCNL, Neurohub, etc.)*
1. **Provide `NmtkAdaptiveLayout` Builder:** Create a helper widget that accepts a `desktopBuilder` and a `mobileBuilder`.
2. **Convert Split Panes to Tabs:** Where modules use a side-by-side view (like the CNL text editor next to the Canvas graph), use `ZetaSegmentedControl` on mobile to toggle between "Editor" and "Preview".
3. **Convert Tables to Lists:** Replace `DataTable` with `ListView.builder` returning `ZetaListItem`s or custom cards for mobile screens.
4. **Form Controls:** Ensure all text inputs use `ZetaTextInput` or appropriately styled TextFields with `ZetaWidgetSize.large` for mobile data entry.

## Summary
By separating the mobile layout structure from the desktop scaffold and introducing a dedicated responsive builder, we can design normal mobile views using Zeta components (lists, bottom sheets, segmented tabs) without affecting the already perfectly fine desktop UI.
