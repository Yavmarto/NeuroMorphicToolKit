# Mobile UI Redesign Plan

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
