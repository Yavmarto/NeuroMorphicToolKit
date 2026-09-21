import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';
import 'package:neuro_toolkit/features/neurocnl/models/detected_hardware_entry.dart';
import 'package:neuro_toolkit/features/neurocnl/models/speck_paired_device.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/feature_launch_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/hardware_auto_add_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/hardware_auto_add.dart';
import 'package:neuro_toolkit/features/neurocnl/services/speck_target_service.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_target_registry_service.dart';
import 'package:neuro_toolkit/ui_core/models/akida_deployment_model.dart';

/// ApiClient double that answers `fetchDetectedHardware` from a fixed list and
/// records the `registered_identifier` values it was called with.
class _FakeApiClient extends ApiClient {
  _FakeApiClient(this.detected)
    : super(
        baseUrl: 'http://backend.test:8000',
        httpClient: MockClient(
          (_) async => http.Response('{"detail":"unexpected call"}', 500),
        ),
      );

  final List<DetectedHardwareEntry> detected;
  final List<List<String>> registeredIdentifierCalls = <List<String>>[];

  @override
  Future<List<DetectedHardwareEntry>> fetchDetectedHardware({
    List<String> registeredIdentifiers = const <String>[],
  }) async {
    registeredIdentifierCalls.add(List<String>.of(registeredIdentifiers));
    return detected;
  }
}

/// Registry double that records how hosts would be saved.
class _FakeStudioTargetRegistryService extends StudioTargetRegistryService {
  _FakeStudioTargetRegistryService({this.existing = const <AkidaPairedHost>[]});

  final List<AkidaPairedHost> existing;

  /// [displayName, hostAddress, authMode, sameHostAsBackend, username,
  /// deviceIdentifier] of every save attempt.
  final List<(String, String, String, bool, String, String)> saved =
      <(String, String, String, bool, String, String)>[];

  @override
  Future<List<AkidaPairedHost>> fetchAkidaHosts() async => existing;

  @override
  Future<AkidaPairedHost> saveAkidaHost({
    String? hostId,
    required String displayName,
    required String hostAddress,
    required int sshPort,
    required String username,
    required String authMode,
    required String? password,
    required String sshKeyPath,
    required String runtimeApiUrl,
    required String controlApiUrl,
    required String remoteInstallRoot,
    required String serviceUser,
    bool isDefault = false,
    bool sameHostAsBackend = false,
    String deviceIdentifier = '',
  }) async {
    saved.add((
      displayName,
      hostAddress,
      authMode,
      sameHostAsBackend,
      username,
      deviceIdentifier,
    ));
    return AkidaPairedHost(
      id: hostId ?? 'created',
      displayName: displayName,
      host: hostAddress,
      sshPort: sshPort,
      username: username,
      runtimeApiUrl: runtimeApiUrl,
      controlApiUrl: controlApiUrl,
      authMode: AkidaHostAuthMode.fromString(authMode),
      credentialRef: '',
      password: '',
      hasPassword: false,
      sshKeyPath: sshKeyPath,
      remoteInstallRoot: remoteInstallRoot,
      serviceUser: serviceUser,
      hostOs: '',
      pythonVersion: '',
      runtimeMode: AkidaRuntimeMode.unknown,
      state: AkidaPairedHostState.pending,
      lastReadinessMessage: '',
      lastVerifiedAt: '',
      isDefault: isDefault,
      sameHostAsBackend: sameHostAsBackend,
      deviceIdentifier: deviceIdentifier,
    );
  }
}

class _FakeSpeckTargetService extends SpeckTargetService {
  _FakeSpeckTargetService({this.existing = const <SpeckPairedDevice>[]});

  final List<SpeckPairedDevice> existing;
  final List<(String, String)> saved = <(String, String)>[];

  @override
  Future<List<SpeckPairedDevice>> fetchDevices() async => existing;

  @override
  Future<SpeckPairedDevice> saveDevice({
    String? deviceId,
    required String displayName,
    required String deviceIdentifier,
    bool isDefault = false,
    bool sameHostAsBackend = true,
  }) async {
    saved.add((displayName, deviceIdentifier));
    return SpeckPairedDevice(
      id: deviceId ?? 'speck-created',
      displayName: displayName,
      deviceIdentifier: deviceIdentifier,
      isDefault: isDefault,
      sameHostAsBackend: sameHostAsBackend,
    );
  }
}

AkidaPairedHost _host({String id = 'h1', String deviceIdentifier = ''}) {
  return AkidaPairedHost(
    id: id,
    displayName: 'Saved host',
    host: 'backend.test',
    sshPort: 22,
    username: '',
    runtimeApiUrl: 'http://backend.test:8002',
    controlApiUrl: 'http://backend.test:8091',
    authMode: AkidaHostAuthMode.none,
    credentialRef: '',
    password: '',
    hasPassword: false,
    sshKeyPath: '',
    remoteInstallRoot: '',
    serviceUser: '',
    hostOs: '',
    pythonVersion: '',
    runtimeMode: AkidaRuntimeMode.remoteSdk,
    state: AkidaPairedHostState.pending,
    lastReadinessMessage: '',
    lastVerifiedAt: '',
    deviceIdentifier: deviceIdentifier,
  );
}

DetectedHardwareEntry _akida(String identifier, {bool registered = false}) {
  return DetectedHardwareEntry(
    chipType: 'akida',
    displayName: 'Akida $identifier',
    identifier: identifier,
    alreadyRegistered: registered,
  );
}

void main() {
  late _FakeApiClient api;
  late _FakeStudioTargetRegistryService registry;
  late _FakeSpeckTargetService speckRegistry;

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        studioTargetRegistryServiceProvider.overrideWithValue(registry),
        speckTargetServiceProvider.overrideWithValue(speckRegistry),
        featureLaunchContextProvider.overrideWith(
          () => SeededFeatureLaunchContextNotifier(
            NmtkFeatureLaunchContext(
              moduleId: NmtkModuleId.neurocnl,
              backendUri: Uri.parse('http://backend.test:8000'),
              onNavigate: (_) async => false,
              onReportError: (_) async {},
              onEditServer: () async {},
            ),
          ),
        ),
      ],
    );
  }

  setUp(() {
    api = _FakeApiClient(const <DetectedHardwareEntry>[]);
    registry = _FakeStudioTargetRegistryService();
    speckRegistry = _FakeSpeckTargetService();
  });

  group('HardwareTargetAutoScanner (CEL-122)', () {
    test('detected-but-unregistered device is auto-created as a name-only '
        'same-host target with no SSH credentials', () async {
      api = _FakeApiClient([_akida('SER-123')]);
      final container = makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(hardwareAutoAddScannerProvider).run();

      expect(result.addedNames, ['Akida SER-123']);
      expect(result.alreadyRegisteredCount, 0);
      expect(registry.saved, hasLength(1));
      final (
        displayName,
        hostAddress,
        authMode,
        sameHostAsBackend,
        username,
        deviceIdentifier,
      ) = registry.saved.single;
      expect(displayName, 'Akida SER-123');
      expect(hostAddress, 'backend.test');
      expect(authMode, 'none');
      expect(sameHostAsBackend, isTrue);
      expect(username, isEmpty);
      expect(deviceIdentifier, 'SER-123');
    });

    test('already-registered device does not create a duplicate '
        '(backend marks it registered)', () async {
      registry = _FakeStudioTargetRegistryService(
        existing: [_host(deviceIdentifier: 'SER-123')],
      );
      api = _FakeApiClient([_akida('SER-123', registered: true)]);
      final container = makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(hardwareAutoAddScannerProvider).run();

      expect(registry.saved, isEmpty);
      expect(result.addedNames, isEmpty);
      expect(result.alreadyRegisteredCount, 1);
      expect(api.registeredIdentifierCalls.single, ['SER-123']);
    });

    test('already-registered device does not create a duplicate even when the '
        'backend response omits the registration flag', () async {
      registry = _FakeStudioTargetRegistryService(
        existing: [_host(deviceIdentifier: 'SER-123')],
      );
      api = _FakeApiClient([_akida('SER-123', registered: false)]);
      final container = makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(hardwareAutoAddScannerProvider).run();

      expect(registry.saved, isEmpty);
      expect(result.addedNames, isEmpty);
    });

    test('Speck is auto-added and Teensy is reported unsupported', () async {
      api = _FakeApiClient(const [
        DetectedHardwareEntry(
          chipType: 'speck',
          displayName: 'Speck 2e0018',
          identifier: '2e0018',
        ),
        DetectedHardwareEntry(
          chipType: 'teensy',
          displayName: 'Teensy /dev/cu.usbmodem1',
          identifier: '/dev/cu.usbmodem1',
        ),
        DetectedHardwareEntry(
          chipType: 'akida',
          displayName: 'Akida SER-9',
          identifier: 'SER-9',
        ),
      ]);
      final container = makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(hardwareAutoAddScannerProvider).run();

      expect(result.addedNames, ['Speck 2e0018', 'Akida SER-9']);
      expect(registry.saved, hasLength(1));
      expect(speckRegistry.saved, hasLength(1));
      expect(speckRegistry.saved.single, ('Speck 2e0018', '2e0018'));
      expect(result.unsupportedByChipType, {'teensy': 1});
      expect(result.describe(), contains('Teensy detected but not auto-added'));
    });
  });
}
