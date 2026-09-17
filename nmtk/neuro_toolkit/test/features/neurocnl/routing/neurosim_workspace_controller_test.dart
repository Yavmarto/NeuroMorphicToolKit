import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_toolkit/features/neurocnl/routing/canvas/neurosim_restoration_snapshot.dart';
import 'package:neuro_toolkit/features/neurocnl/routing/canvas/neurosim_route_state.dart';
import 'package:neuro_toolkit/features/neurocnl/routing/canvas/neurosim_workspace_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test('NeurosimRestorationSnapshot round-trips export route state', () {
    final snapshot = NeurosimRestorationSnapshot.fromRouteState(
      const NeurosimRouteState(
        target: NeurosimRouteTarget.export,
        selectedProjectId: 'project-42',
        selectedNodeId: 'node-a',
        selectedEdgeId: 'edge-b',
        showPreview: true,
        previewCurrentTime: 1.25,
        previewResults: <String, dynamic>{
          'spikes': <int>[1, 2, 3],
        },
      ),
    );

    final restored = NeurosimRestorationSnapshot.fromEncoded(
      snapshot.encode(),
    ).toRouteState();

    expect(restored.target, NeurosimRouteTarget.export);
    expect(restored.selectedProjectId, 'project-42');
    expect(restored.selectedNodeId, 'node-a');
    expect(restored.selectedEdgeId, 'edge-b');
    expect(restored.showPreview, isTrue);
    expect(restored.previewCurrentTime, 1.25);
    expect(restored.previewResults, <String, dynamic>{
      'spikes': <int>[1, 2, 3],
    });
  });

  test(
    'controller initializes from explicit snapshot before stored state',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        NeurosimWorkspaceController.snapshotStorageKey,
        NeurosimRestorationSnapshot.fromRouteState(
          const NeurosimRouteState(
            target: NeurosimRouteTarget.canvas,
            selectedProjectId: 'stale-project',
          ),
        ).encode(),
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(
        neurosimWorkspaceControllerProvider.notifier,
      );

      await controller.initialize(
        snapshot: NeurosimRestorationSnapshot.fromRouteState(
          const NeurosimRouteState(
            target: NeurosimRouteTarget.export,
            selectedProjectId: 'fresh-project',
            selectedNodeId: 'node-7',
          ),
        ).encode(),
      );

      expect(controller.state.isHydrated, isTrue);
      expect(controller.state.routeState.target, NeurosimRouteTarget.export);
      expect(controller.state.routeState.selectedProjectId, 'fresh-project');
      expect(controller.state.routeState.selectedNodeId, 'node-7');
    },
  );

  test(
    'controller persists route changes for later workspace restoration',
    () async {
      final container1 = ProviderContainer();
      addTearDown(container1.dispose);
      final controller = container1.read(
        neurosimWorkspaceControllerProvider.notifier,
      );

      await controller.initialize();
      await controller.openSweep(projectId: 'project-sweep');
      await controller.updateSelection(selectedNodeId: 'node-9');
      await controller.updatePreviewState(
        currentTime: 2.5,
        previewResults: const <String, dynamic>{'status': 'ok'},
      );

      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      final restoredController = container2.read(
        neurosimWorkspaceControllerProvider.notifier,
      );
      await restoredController.initialize();

      expect(
        restoredController.state.routeState.target,
        NeurosimRouteTarget.sweep,
      );
      expect(
        restoredController.state.routeState.selectedProjectId,
        'project-sweep',
      );
      expect(restoredController.state.routeState.selectedNodeId, 'node-9');
      expect(restoredController.state.routeState.previewCurrentTime, 2.5);
      expect(
        restoredController.state.routeState.previewResults,
        const <String, dynamic>{'status': 'ok'},
      );
    },
  );
}
