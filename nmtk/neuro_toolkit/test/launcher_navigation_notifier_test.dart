import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/src/features/app/presentation/launcher_navigation_notifier.dart';

void main() {
  test('emits distinct typed requests for repeated launcher actions', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final navigation = container.read(launcherNavigationProvider.notifier);

    navigation.openModule('Neurobench');
    final first = container.read(launcherNavigationProvider);
    navigation.openModule('Neurobench');
    final second = container.read(launcherNavigationProvider);

    expect(first?.action, LauncherNavigationAction.openModule);
    expect(first?.moduleId, 'Neurobench');
    expect(second?.action, LauncherNavigationAction.openModule);
    expect(second?.moduleId, 'Neurobench');
    expect(second!.sequence, first!.sequence + 1);
  });

  test('emits workspace, reload, and shell action requests', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final navigation = container.read(launcherNavigationProvider.notifier);

    navigation.openWorkspace();
    expect(
      container.read(launcherNavigationProvider)?.action,
      LauncherNavigationAction.openWorkspace,
    );

    navigation.reloadWorkspace();
    expect(
      container.read(launcherNavigationProvider)?.action,
      LauncherNavigationAction.reloadWorkspace,
    );

    navigation.toggleSidebar();
    expect(
      container.read(launcherNavigationProvider)?.action,
      LauncherNavigationAction.toggleSidebar,
    );
  });
}
