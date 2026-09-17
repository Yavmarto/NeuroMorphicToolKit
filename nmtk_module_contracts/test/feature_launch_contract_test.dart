import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

void main() {
  group('NmtkModuleId', () {
    test('accepts canonical and legacy launcher IDs', () {
      expect(NmtkModuleId.fromExternal('neurobench'), NmtkModuleId.neurobench);
      expect(NmtkModuleId.fromExternal('Neurobench'), NmtkModuleId.neurobench);
    });

    test('rejects an unknown external ID', () {
      expect(
        () => NmtkModuleId.fromExternal('unknown-feature'),
        throwsArgumentError,
      );
    });
  });

  test('launch context defensively copies restoration state', () async {
    final restorationState = <String, Object?>{'tab': 'reports'};
    NmtkFeatureNavigationRequest? navigationRequest;
    NmtkFeatureErrorEvent? errorEvent;
    var recovered = 0;
    final context = NmtkFeatureLaunchContext(
      moduleId: NmtkModuleId.neurobench,
      backendUri: Uri.parse('http://127.0.0.1:9000/api/neurobench'),
      restorationState: restorationState,
      onNavigate: (request) async {
        navigationRequest = request;
        return true;
      },
      onReportError: (event) async => errorEvent = event,
      onRecovered: () async => recovered++,
      onEditServer: () async {},
    );

    restorationState['tab'] = 'changed';
    expect(context.restorationState, <String, Object?>{'tab': 'reports'});
    expect(
      () => context.restorationState['tab'] = 'changed',
      throwsUnsupportedError,
    );

    final request = NmtkFeatureNavigationRequest(
      moduleId: NmtkModuleId.neurocnl,
      deepLink: '/reports',
    );
    expect(await context.onNavigate(request), isTrue);
    expect(navigationRequest, same(request));

    final event = NmtkFeatureErrorEvent(
      moduleId: NmtkModuleId.neurobench,
      kind: NmtkFeatureErrorKind.connection,
      message: 'Connection unavailable.',
    );
    await context.onReportError(event);
    expect(errorEvent, same(event));

    await context.onRecovered();
    expect(recovered, 1);
  });

  test('launch context defaults to a no-op recovery reporter', () async {
    final context = NmtkFeatureLaunchContext(
      moduleId: NmtkModuleId.neurobench,
      backendUri: Uri.parse('http://127.0.0.1:9000/api/neurobench'),
      onNavigate: (_) async => false,
      onReportError: (_) async {},
      onEditServer: () async {},
    );

    // Must not throw and must be non-null even when the host omits it.
    await context.onRecovered();
    expect(context.onRecovered, isNotNull);
  });
}
