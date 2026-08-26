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
    final context = NmtkFeatureLaunchContext(
      moduleId: NmtkModuleId.neurobench,
      backendUri: Uri.parse('http://127.0.0.1:9000/api/neurobench'),
      restorationState: restorationState,
      onNavigate: (request) async {
        navigationRequest = request;
        return true;
      },
      onReportError: (event) async => errorEvent = event,
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
  });
}
