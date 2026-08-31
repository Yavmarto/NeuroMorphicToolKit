import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/backend_tunnel_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/workspace/native_surface_registry.dart';

Uri? launcherBaseUri(WidgetRef ref) =>
    ref.read(selectedControlApiServiceProvider)?.baseUri;

BackendTunnelSession? tunnelSession(WidgetRef ref) =>
    ref.read(backendTunnelServiceProvider).currentSession;

bool usesRemoteHostedServices(WidgetRef ref) {
  if (kIsWeb) {
    return false;
  }
  final baseUri = launcherBaseUri(ref);
  return baseUri != null && !ControlApiService.isLoopbackHost(baseUri.host);
}

String get configuredServicesHost =>
    const String.fromEnvironment('NMTK_SERVICES_HOST', defaultValue: '');

String serviceHost(WidgetRef ref) {
  if (!kIsWeb) {
    final override = configuredServicesHost.trim();
    if (override.isNotEmpty && !ControlApiService.isLoopbackHost(override)) {
      return override;
    }
    final baseUri = launcherBaseUri(ref);
    if (baseUri != null && usesRemoteHostedServices(ref)) {
      return baseUri.host;
    }
    return 'localhost';
  }
  final host = Uri.base.host.trim();
  if (host.isEmpty || host == '0.0.0.0') {
    return 'localhost';
  }
  return host;
}

String serviceScheme(WidgetRef ref) {
  if (!kIsWeb) {
    final baseUri = launcherBaseUri(ref);
    if (baseUri != null && usesRemoteHostedServices(ref)) {
      return baseUri.scheme.isEmpty ? 'http' : baseUri.scheme;
    }
    return 'http';
  }
  final scheme = Uri.base.scheme.trim();
  return scheme.isEmpty ? 'http' : scheme;
}

Uri moduleUri(WidgetRef ref, Module module, {bool healthCheck = false}) {
  final String moduleId = module.id.toLowerCase();

  // If it's on the monolith port (9000), we use path-based routing.
  if (module.effectivePort == 9000) {
    final tunnelBase = tunnelSession(ref)?.suiteApiUri;
    if (healthCheck) {
      return tunnelBase?.replace(path: '/api/$moduleId/health') ??
          Uri(
            scheme: serviceScheme(ref),
            host: serviceHost(ref),
            port: 9000,
            path: '/api/$moduleId/health',
          );
    }
    return tunnelBase?.replace(path: '/$moduleId/') ??
        Uri(
          scheme: serviceScheme(ref),
          host: serviceHost(ref),
          port: 9000,
          path: '/$moduleId/',
        );
  }

  // Standalone modules on non-monolith ports.
  // Use deployment.healthPath when available so modules like Jupyter (which
  // expose /api/health rather than /health) are polled correctly.
  final String healthPath = module.deployment?.healthPath.isNotEmpty == true
      ? module.deployment!.healthPath
      : '/health';
  final path = healthCheck ? healthPath : (module.hasFrontend ? '' : '/docs');
  if (module.effectivePort == 8008 && tunnelSession(ref) != null) {
    return tunnelSession(ref)!.jupyterUri.replace(path: path);
  }
  return Uri(
    scheme: serviceScheme(ref),
    host: serviceHost(ref),
    port: module.effectivePort,
    path: path,
  );
}

/// Backend API base URL to hand to a natively-embedded module so it can
/// skip its own connect prompt — the launcher already knows this host.
/// Only meaningful for modules sharing the monolith port (9000); other
/// modules resolve their own backend independently.
String? nativeSurfaceServerUrl(WidgetRef ref, Module module) {
  if (module.effectivePort != 9000) {
    return null;
  }
  // Neurobench is the one module on the monolith port with its own
  // `/api/neurobench` mount; every other native surface here (neurocnl,
  // and Neurochip embedded inside the neurocnl studio shell) uses
  // `/api/neurocnl`.
  final apiPath = module.id == 'Neurobench' ? '/api/neurobench' : '/api/neurocnl';
  return (tunnelSession(ref)?.suiteApiUri ??
          Uri(scheme: serviceScheme(ref), host: serviceHost(ref), port: 9000))
      .replace(path: apiPath)
      .toString();
}

String surfaceModeForModule(String moduleId) {
  return NativeSurfaceRegistry.supportsModule(moduleId) ? 'native' : 'embedded';
}
