import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/models/server_workspace_summary.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/admin_token_http_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurochip_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_akida_deploy_service.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_lava_deploy_service.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_pynq_deploy_service.dart';

import 'package:neuro_toolkit/features/neurocnl/services/studio_target_registry_service.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/feature_launch_provider.dart';

/// Singleton API client provider.
///
/// Rebuilds clients when the root changes the selected backend.
final apiClientProvider = Provider<ApiClient>((ref) {
  final launchContext = ref.watch(featureLaunchContextProvider);
  final client = ApiClient(
    baseUrl: launchContext.backendUri.toString(),
    httpClient: AdminTokenHttpClient(
      adminToken: launchContext.authentication.adminToken,
      onReportError: launchContext.onReportError,
    ),
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Singleton Neurochip client provider.
///
/// Connects to the Neurochip backend (default port 8002) for firmware
/// generation, serial port discovery, and flash job management.
final neurochipClientProvider = Provider<NeurochipClient>((ref) {
  final launchContext = ref.watch(featureLaunchContextProvider);
  final client = NeurochipClient(
    baseUrl: launchContext.backendUri.toString(),
    httpClient: AdminTokenHttpClient(
      adminToken: launchContext.authentication.adminToken,
      onReportError: launchContext.onReportError,
    ),
  );
  ref.onDispose(client.dispose);
  return client;
});

final studioTargetRegistryServiceProvider =
    Provider<StudioTargetRegistryService>((ref) {
      final launchContext = ref.watch(featureLaunchContextProvider);
      final service = StudioTargetRegistryService(
        backendUri: launchContext.backendUri,
        client: AdminTokenHttpClient(
          adminToken: launchContext.authentication.adminToken,
          onReportError: launchContext.onReportError,
        ),
      );
      ref.onDispose(service.dispose);
      return service;
    });

final studioAkidaDeployServiceProvider = Provider<StudioAkidaDeployService>((
  ref,
) {
  return StudioAkidaDeployService(
    apiClient: ref.watch(apiClientProvider),
    targetRegistryService: ref.watch(studioTargetRegistryServiceProvider),
  );
});

final studioPynqDeployServiceProvider = Provider<StudioPynqDeployService>((
  ref,
) {
  return StudioPynqDeployService(
    apiClient: ref.watch(apiClientProvider),
    targetRegistryService: ref.watch(studioTargetRegistryServiceProvider),
  );
});

final studioLavaDeployServiceProvider = Provider<StudioLavaDeployService>((
  ref,
) {
  return StudioLavaDeployService(
    apiClient: ref.watch(apiClientProvider),
    neurochipClient: ref.watch(neurochipClientProvider),
  );
});

/// Every workspace saved on the server this client is pointed at — backs
/// the "Load from server" picker in the Setup step.
final serverWorkspacesProvider = FutureProvider<List<ServerWorkspaceSummary>>((
  ref,
) async {
  return ref.read(apiClientProvider).listServerWorkspaces();
});

/// Whether MuJoCo is available on the backend (cached per session).
final mujocoAvailableProvider = FutureProvider<bool>((ref) async {
  final client = ref.read(apiClientProvider);
  try {
    final result = await client.health();
    return result.mujocoAvailable;
  } catch (e) {
    debugPrint('MuJoCo health check failed: $e');
    return false;
  }
});
