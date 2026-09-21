import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/setup_step/setup_input_source_section.dart';
import 'package:neuro_toolkit/features/neurocnl/models/neurosense_sensor_target.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/neurosense_popup.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurosense_api_service.dart';

void main() {
  testWidgets('input source section toggles live NeuroSense mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          neurosenseApiServiceProvider.overrideWithValue(
            _SetupFakeNeurosenseApiService(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: const SetupInputSourceSection()),
        ),
      ),
    );

    expect(find.byKey(const Key('setup-input-source-dataset')), findsOneWidget);
    expect(
      find.byKey(const Key('setup-input-source-live-sensor')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('setup-input-source-live-sensor')));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SetupInputSourceSection)),
    );
    expect(
      container.read(workspaceProvider).workspaceSourceKind,
      SetupInputSourceSection.liveSensorKind,
    );
    expect(
      find.byKey(const Key('neurosense-configure-source')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('setup-open-neurosense-panel')),
      findsOneWidget,
    );
  });
}

class _SetupFakeNeurosenseApiService extends NeurosenseApiService {
  _SetupFakeNeurosenseApiService() : super(ApiClient(baseUrl: 'http://test'));

  @override
  Future<List<NeurosenseDeviceInfo>> listDevices() async => const [];
}
