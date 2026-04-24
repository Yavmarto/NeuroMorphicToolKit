import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

void main() {
  group('Shell primitives', () {
    test('default shell tokens are attached to the app theme', () {
      final theme = AppTheme.darkTheme;
      final tokens = theme.extension<NmtkShellTokens>();

      expect(tokens, isNotNull);
      expect(tokens!.topAppBarHeight, 52);
      expect(tokens.workspaceBarHeight, 48);
      expect(
        tokens.paletteForMode(NmtkShellMode.command).accent,
        theme.colorScheme.primary,
      );
      expect(
        tokens.paletteForMode(NmtkShellMode.studio).accent,
        isNot(theme.colorScheme.primary),
      );
    });

    testWidgets('top app bar renders destinations, badges, and actions', (
      tester,
    ) async {
      var selectedIndex = 0;
      var actionTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            appBar: NmtkTopAppBar(
              title: const Text('Suite Shell'),
              destinations: const [
                NavigationDestinationData(
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home,
                  label: 'Home',
                ),
                NavigationDestinationData(
                  icon: Icons.extension_outlined,
                  selectedIcon: Icons.extension,
                  label: 'Modules',
                ),
              ],
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) {
                selectedIndex = index;
              },
              statusBadges: const [
                NmtkShellStatusBadge(
                  status: NmtkShellStatusSpec(
                    label: 'Ready',
                    tone: NmtkTone.success,
                    icon: Icons.check_circle_outline,
                  ),
                ),
              ],
              actions: [
                NmtkTopAppBarAction(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  tooltip: 'Settings',
                  onPressed: () {
                    actionTapped = true;
                  },
                ),
              ],
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      );

      expect(find.text('Suite Shell'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Modules'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);

      await tester.tap(find.text('Modules'));
      await tester.pump();
      expect(selectedIndex, 1);

      await tester.tap(find.text('Settings'));
      await tester.pump();
      expect(actionTapped, isTrue);
    });

    testWidgets('workspace switcher renders active and pinned workspaces', (
      tester,
    ) async {
      String? selected;
      String? closed;
      String? pinned;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: NmtkWorkspaceSwitcherBar(
              activeWorkspaceId: 'bench',
              onWorkspaceSelected: (id) {
                selected = id;
              },
              onWorkspaceClosed: (id) {
                closed = id;
              },
              onWorkspacePinned: (id) {
                pinned = id;
              },
              workspaces: const [
                NmtkWorkspaceChipData(
                  id: 'bench',
                  label: 'Neurobench',
                  icon: Icons.analytics_outlined,
                  state: NmtkWorkspaceVisualState.active,
                  statusText: 'Live',
                  pinned: true,
                ),
                NmtkWorkspaceChipData(
                  id: 'sim',
                  label: 'NeuroSim',
                  icon: Icons.schema_outlined,
                  state: NmtkWorkspaceVisualState.starting,
                  badgeCount: 2,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Neurobench'), findsOneWidget);
      expect(find.text('NeuroSim'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.text('NeuroSim'));
      await tester.pump();
      expect(selected, 'sim');

      await tester.tap(find.byTooltip('Close workspace').last);
      await tester.pump();
      expect(closed, 'sim');

      await tester.tap(find.byTooltip('Pinned workspace').first);
      await tester.pump();
      expect(pinned, 'bench');
    });

    testWidgets('readiness state view shows degraded and retry action', (
      tester,
    ) async {
      var retried = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: NmtkShellReadinessStateView.fromState(
              NmtkShellReadinessState.degraded,
              message: 'Hardware acceleration is unavailable.',
              action: NmtkShellRetryButton(
                onPressed: () {
                  retried = true;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('Running with degraded capability'), findsOneWidget);
      expect(
        find.text('Hardware acceleration is unavailable.'),
        findsNWidgets(2),
      );
      expect(find.text('Degraded'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retried, isTrue);
    });
  });
}
