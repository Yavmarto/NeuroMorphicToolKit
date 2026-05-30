// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Test helpers
// ─────────────────────────────────────────────────────────────────────────────



Widget _buildHarness(Widget child) {
  return MaterialApp(home: child);
}

const _kNavItems = [
  NmtkSidebarItem(id: 'home', label: 'Home', icon: Icons.home_outlined),
  NmtkSidebarItem(id: 'editor', label: 'Editor', icon: Icons.code_outlined),
  NmtkSidebarItem(
    id: 'simulate',
    label: 'Simulate',
    icon: Icons.play_arrow_outlined,
  ),
];

// A minimal file-action delegate for testing.
class _TestFileDelegate implements NmtkFileActionDelegate {
  int newCount = 0;
  int openCount = 0;
  int saveCount = 0;
  int saveAsCount = 0;

  @override
  void onNewFile() => newCount++;
  @override
  void onOpenFile() => openCount++;
  @override
  void onSaveFile() => saveCount++;
  @override
  void onSaveFileAs() => saveAsCount++;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // Use a large screen so the scaffold can lay out without overflow errors.
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('NmtkDesktopScaffold', () {
    // 1. Rail renders nav items
    testWidgets('renders rail with nav items', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildHarness(
          const NmtkDesktopScaffold(
            navItems: _kNavItems,
            selectedIndex: 0,
            child: Text('Content'),
          ),
        ),
      );

      // Icons for all 3 items must be present.
      expect(find.byIcon(Icons.home_outlined), findsOneWidget);
      expect(find.byIcon(Icons.code_outlined), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_outlined), findsOneWidget);
    });

    // 2. Back button hidden by default
    testWidgets('back button is hidden when showBackButton is false', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildHarness(
          const NmtkDesktopScaffold(
            navItems: _kNavItems,
            selectedIndex: 0,
            child: Text('Content'),
          ),
        ),
      );

      // No content header rendered means no back button icon.
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
    });

    // 3. Back button visible when showBackButton is true
    testWidgets('back button is visible when showBackButton is true', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildHarness(
          const NmtkDesktopScaffold(
            navItems: _kNavItems,
            selectedIndex: 0,
            showBackButton: true,
            child: Text('Content'),
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    });

    // 4. onSettingsPressed callback fires
    testWidgets('onSettingsPressed callback fires when settings gear tapped', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var settingsTapped = false;

      await tester.pumpWidget(
        _buildHarness(
          NmtkDesktopScaffold(
            navItems: _kNavItems,
            selectedIndex: 0,
            onSettingsPressed: () => settingsTapped = true,
            child: const Text('Content'),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pump();

      expect(settingsTapped, isTrue);
    });

    // 5. Profile initials derived from displayName
    testWidgets('profile initials are derived from displayName', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildHarness(
          const NmtkDesktopScaffold(
            navItems: _kNavItems,
            selectedIndex: 0,
            userProfile: NmtkUserProfile(displayName: 'Yoshi M.'),
            child: Text('Content'),
          ),
        ),
      );

      // "YM" should be the derived initials from "Yoshi M."
      expect(find.text('YM'), findsOneWidget);
    });

    // 6. File action buttons render when fileActions provided
    testWidgets('file action icon strip renders when fileActions is provided', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final delegate = _TestFileDelegate();

      await tester.pumpWidget(
        _buildHarness(
          NmtkDesktopScaffold(
            navItems: _kNavItems,
            selectedIndex: 0,
            fileActions: delegate,
            child: const Text('Content'),
          ),
        ),
      );

      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      expect(find.byIcon(Icons.folder_open_rounded), findsOneWidget);
      expect(find.byIcon(Icons.save_rounded), findsOneWidget);
      expect(find.byIcon(Icons.save_as_rounded), findsOneWidget);
    });

    // 7. onNavItemSelected fires with correct index
    testWidgets('onNavItemSelected fires with tapped item index', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      int? tappedIndex;

      await tester.pumpWidget(
        _buildHarness(
          NmtkDesktopScaffold(
            navItems: _kNavItems,
            selectedIndex: 0,
            onNavItemSelected: (i) => tappedIndex = i,
            child: const Text('Content'),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.code_outlined));
      await tester.pump();

      expect(tappedIndex, 1);
    });

    // 8. Legacy params accepted without error
    testWidgets('legacy params are accepted without error', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildHarness(
          NmtkDesktopScaffold(
            navItems: _kNavItems,
            selectedIndex: 0,
            pageTitle: 'Legacy Title',
            headerActions: const Icon(Icons.more_horiz),
            footerNavItems: const [
              NmtkSidebarItem(
                id: 'help',
                label: 'Help',
                icon: Icons.help_outline,
              ),
            ],
            onFooterNavItemSelected: (_) {},
            initiallyExpanded: false,
            child: const Text('Content'),
          ),
        ),
      );

      // Scaffold renders without exception; content child is present.
      expect(find.text('Content'), findsOneWidget);
      // Legacy title is NOT rendered in the UI.
      expect(find.text('Legacy Title'), findsNothing);
    });

    testWidgets('mobile layout renders bottom navigation when tabs fit', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      int? tappedIndex;

      await tester.pumpWidget(
        _buildHarness(
          NmtkDesktopScaffold(
            navItems: _kNavItems,
            selectedIndex: 0,
            pageTitle: 'Workspace',
            onNavItemSelected: (i) => tappedIndex = i,
            footerNavItems: const [
              NmtkSidebarItem(
                id: 'settings',
                label: 'Settings',
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings_rounded,
              ),
            ],
            onFooterNavItemSelected: (_) {},
            child: const Text('Content'),
          ),
        ),
      );

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byIcon(Icons.menu_rounded), findsNothing);
      expect(find.text('Workspace'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.code_outlined));
      await tester.pumpAndSettle();

      expect(tappedIndex, 1);
    });

    testWidgets(
      'mobile bottom navigation routes footer items through callback',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        int? tappedFooterIndex;

        await tester.pumpWidget(
          _buildHarness(
            NmtkDesktopScaffold(
              navItems: _kNavItems,
              selectedIndex: -1,
              pageTitle: 'Settings',
              footerNavItems: const [
                NmtkSidebarItem(
                  id: 'settings',
                  label: 'Settings',
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings_rounded,
                ),
              ],
              onFooterNavItemSelected: (i) => tappedFooterIndex = i,
              child: const Text('Content'),
            ),
          ),
        );

        await tester.tap(find.text('Settings').last);
        await tester.pumpAndSettle();

        expect(tappedFooterIndex, 0);
      },
    );
  });
}
