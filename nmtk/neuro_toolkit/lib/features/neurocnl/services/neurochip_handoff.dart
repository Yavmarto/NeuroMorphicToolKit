import 'dart:convert';

class NeurochipHandoffTarget {
  const NeurochipHandoffTarget({
    required this.url,
    required this.encodedPayload,
  });

  final Uri url;
  final String encodedPayload;
}

class NeurochipHandoff {
  static const int maxEncodedPayloadLength = 6 * 1024;
  static const int neurochipPort = 8002;

  static String? buildDeepLink({
    required Map<String, dynamic> networkJson,
    required String targetId,
    required String targetLabel,
    required String destinationWorkspace,
    Map<String, dynamic> readinessSummary = const <String, dynamic>{},
  }) {
    final encodedPayload = _encodePayload(
      networkJson: networkJson,
      targetId: targetId,
      targetLabel: targetLabel,
      destinationWorkspace: destinationWorkspace,
      readinessSummary: readinessSummary,
    );
    if (encodedPayload == null) {
      return null;
    }

    return Uri(
      path: '/$destinationWorkspace',
      queryParameters: {'import_network_handoff': encodedPayload},
    ).toString();
  }

  static NeurochipHandoffTarget? buildTarget({
    required Map<String, dynamic> networkJson,
    required String origin,
    required String targetId,
    required String targetLabel,
    required String destinationWorkspace,
    Map<String, dynamic> readinessSummary = const <String, dynamic>{},
  }) {
    final encodedPayload = _encodePayload(
      networkJson: networkJson,
      targetId: targetId,
      targetLabel: targetLabel,
      destinationWorkspace: destinationWorkspace,
      readinessSummary: readinessSummary,
    );
    final trimmedOrigin = origin.trim();
    if (encodedPayload == null || trimmedOrigin.isEmpty) {
      return null;
    }

    final originUri = Uri.parse(trimmedOrigin);
    final targetUri = Uri(
      scheme: originUri.scheme,
      host: originUri.host,
      port: neurochipPort,
      path: '/$destinationWorkspace',
      queryParameters: {'import_network_handoff': encodedPayload},
    );

    return NeurochipHandoffTarget(
      url: targetUri,
      encodedPayload: encodedPayload,
    );
  }

  static String? _encodePayload({
    required Map<String, dynamic> networkJson,
    required String targetId,
    required String targetLabel,
    required String destinationWorkspace,
    required Map<String, dynamic> readinessSummary,
  }) {
    if (networkJson.isEmpty ||
        targetId.trim().isEmpty ||
        targetLabel.trim().isEmpty ||
        destinationWorkspace.trim().isEmpty) {
      return null;
    }

    final payload = <String, dynamic>{
      'handoff_version': 1,
      'source': 'neurocnl_studio',
      'network': networkJson,
      'target_id': targetId,
      'target_label': targetLabel,
      'destination_workspace': destinationWorkspace,
      'readiness_summary': readinessSummary,
    };

    return base64Url
        .encode(utf8.encode(jsonEncode(payload)))
        .replaceAll('=', '');
  }

  static bool exceedsSafePayload(NeurochipHandoffTarget target) {
    return target.encodedPayload.length > maxEncodedPayloadLength;
  }
}
