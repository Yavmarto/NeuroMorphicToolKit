import 'dart:convert';

class AkidaHandoffTarget {
  const AkidaHandoffTarget({required this.url, required this.encodedPayload});

  final Uri url;
  final String encodedPayload;
}

class AkidaHandoff {
  static const int maxEncodedPayloadLength = 6 * 1024;
  static const int neurochipPort = 8002;

  static String? buildDeepLink({
    required Map<String, dynamic> mappedNetwork,
    required int bitWidth,
    required String akidaVersion,
    String supportState = 'unsupported',
    String topologyVerdict = 'unknown',
    Map<String, dynamic>? networkSummary,
    List<String> warnings = const [],
    List<String> rejections = const [],
    String? hardwareUrl,
  }) {
    final encodedPayload = _encodePayload(
      mappedNetwork: mappedNetwork,
      bitWidth: bitWidth,
      akidaVersion: akidaVersion,
      supportState: supportState,
      topologyVerdict: topologyVerdict,
      networkSummary: networkSummary,
      warnings: warnings,
      rejections: rejections,
      hardwareUrl: hardwareUrl,
    );
    if (encodedPayload == null) {
      return null;
    }

    return Uri(
      path: '/',
      queryParameters: {'import_akida': encodedPayload},
    ).toString();
  }

  static AkidaHandoffTarget? buildTarget({
    required Map<String, dynamic> mappedNetwork,
    required int bitWidth,
    required String akidaVersion,
    required String origin,
    String supportState = 'unsupported',
    String topologyVerdict = 'unknown',
    Map<String, dynamic>? networkSummary,
    List<String> warnings = const [],
    List<String> rejections = const [],
    String? hardwareUrl,
  }) {
    final encodedPayload = _encodePayload(
      mappedNetwork: mappedNetwork,
      bitWidth: bitWidth,
      akidaVersion: akidaVersion,
      supportState: supportState,
      topologyVerdict: topologyVerdict,
      networkSummary: networkSummary,
      warnings: warnings,
      rejections: rejections,
      hardwareUrl: hardwareUrl,
    );
    final trimmedOrigin = origin.trim();
    if (trimmedOrigin.isEmpty || encodedPayload == null) {
      return null;
    }
    final originUri = Uri.parse(trimmedOrigin);
    final targetUri = Uri(
      scheme: originUri.scheme,
      host: originUri.host,
      port: neurochipPort,
      path: '/',
      queryParameters: {'import_akida': encodedPayload},
    );

    return AkidaHandoffTarget(url: targetUri, encodedPayload: encodedPayload);
  }

  static String? _encodePayload({
    required Map<String, dynamic> mappedNetwork,
    required int bitWidth,
    required String akidaVersion,
    String supportState = 'unsupported',
    String topologyVerdict = 'unknown',
    Map<String, dynamic>? networkSummary,
    List<String> warnings = const [],
    List<String> rejections = const [],
    String? hardwareUrl,
  }) {
    if (mappedNetwork.isEmpty) {
      return null;
    }

    final rawSummary = mappedNetwork['network_summary'];
    final effectiveSummary =
        networkSummary ??
        (rawSummary is Map<String, dynamic>
            ? rawSummary
            : rawSummary is Map
            ? Map<String, dynamic>.from(rawSummary)
            : null);

    final runtimeContext = <String, dynamic>{
      'weight_bit_width': bitWidth,
      'akida_version': akidaVersion,
      'support_state': supportState,
      'topology_verdict': topologyVerdict,
      'network_summary': ?effectiveSummary,
      if (warnings.isNotEmpty) 'warnings': warnings,
      if (rejections.isNotEmpty) 'rejections': rejections,
      if (hardwareUrl != null && hardwareUrl.trim().isNotEmpty)
        'hardware_url': hardwareUrl.trim(),
    };

    final handoffPayload = <String, dynamic>{
      'handoff_version': 1,
      'source': 'neurocnl_studio',
      'mapped_network': mappedNetwork,
      'runtime_context': runtimeContext,
    };

    return base64Url
        .encode(utf8.encode(jsonEncode(handoffPayload)))
        .replaceAll('=', '');
  }

  static bool exceedsSafePayload(AkidaHandoffTarget target) {
    return target.encodedPayload.length > maxEncodedPayloadLength;
  }
}
