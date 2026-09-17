/// Resolves the suite launcher-control endpoint from a configured backend URL.
///
/// The Suite API and launcher-control are published on separate ports of the
/// same backend host. The launcher port is a suite contract and must not be
/// confused with the Akida host's own remote-control port.
const int studioLauncherControlPort = int.fromEnvironment(
  'NMTK_CONTROL_API_PORT',
  defaultValue: 8090,
);

Uri resolveLauncherControlUri(
  String? configuredBackendUrl,
  String path, {
  Map<String, String>? queryParameters,
}) {
  final normalizedPath = path.startsWith('/') ? path : '/$path';
  final configuredBase = Uri.tryParse(configuredBackendUrl?.trim() ?? '');
  final host = configuredBase?.host.trim().isNotEmpty == true
      ? configuredBase!.host
      : '127.0.0.1';
  final scheme = configuredBase?.scheme.trim().isNotEmpty == true
      ? configuredBase!.scheme
      : 'http';
  return Uri(
    scheme: scheme,
    host: host,
    port: studioLauncherControlPort,
    path: normalizedPath,
    queryParameters: queryParameters,
  );
}
