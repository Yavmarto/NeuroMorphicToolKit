import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/detected_hardware_entry.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/feature_launch_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/hardware_auto_add.dart';
import 'package:neuro_toolkit/features/neurocnl/services/speck_target_service.dart';

/// The launcher's view of the backend this neurocnl surface is connected to.
///
/// Scanner only ever talks to launcher-control and to the connected backend, so
/// it is safe to keep alive for the surface's lifetime; [run] re-reads state on
/// every call.
final hardwareAutoAddScannerProvider = Provider<HardwareTargetAutoScanner>((
  ref,
) {
  final api = ref.watch(apiClientProvider);
  final registry = ref.watch(studioTargetRegistryServiceProvider);
  final speckTargets = ref.watch(speckTargetServiceProvider);
  final backendUri = ref.watch(featureLaunchContextProvider).backendUri;
  final backendHost = backendUri.host.trim().toLowerCase();

  String displayNameFor(DetectedHardwareEntry entry) {
    final name = entry.displayName.trim();
    if (name.isNotEmpty) return name;
    return switch (entry.chipType) {
      'speck' => 'Speck ${entry.identifier.trim()}',
      _ => 'Akida ${entry.identifier.trim()}',
    };
  }

  return HardwareTargetAutoScanner(
    detectDevices: ({required registeredIdentifiers}) =>
        api.fetchDetectedHardware(registeredIdentifiers: registeredIdentifiers),
    fetchAkidaHosts: registry.fetchAkidaHosts,
    createSameHostAkidaHost: (entry) => registry.saveAkidaHost(
      displayName: displayNameFor(entry),
      hostAddress: backendHost,
      sshPort: 22,
      username: '',
      authMode: AkidaHostAuthMode.none.apiValue,
      password: null,
      sshKeyPath: '',
      runtimeApiUrl: '',
      controlApiUrl: '',
      remoteInstallRoot: '',
      serviceUser: '',
      sameHostAsBackend: true,
      deviceIdentifier: entry.identifier.trim(),
    ),
    fetchSpeckDevices: speckTargets.fetchDevices,
    createSameHostSpeckDevice: (entry) => speckTargets.saveDevice(
      displayName: displayNameFor(entry),
      deviceIdentifier: entry.identifier.trim(),
      sameHostAsBackend: true,
    ),
  );
});
