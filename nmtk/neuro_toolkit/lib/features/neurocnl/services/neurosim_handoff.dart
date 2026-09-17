import 'dart:convert';

import 'package:neuro_toolkit/features/neurocnl/services/neurosim_import_contract.dart';

class NeurosimHandoffTarget {
  const NeurosimHandoffTarget({
    required this.url,
    required this.encodedContract,
  });

  final Uri url;
  final String encodedContract;
}

class NeurosimHandoff {
  static const int maxEncodedSpecLength = 6 * 1024;
  // Canvas is now served by the merged NeuroStudio backend at port 8000.
  static const int neurosimPort = 8000;

  static String? buildDeepLink({
    required NeurosimImportContract importContract,
  }) {
    final encodedContract = _encodeContract(importContract);
    if (encodedContract == null) {
      return null;
    }

    // Deep link targets the /canvas route inside the merged frontend.
    return Uri(
      path: '/canvas',
      queryParameters: {'import_contract': encodedContract},
    ).toString();
  }

  static NeurosimHandoffTarget? buildTarget({
    required NeurosimImportContract importContract,
    required String origin,
  }) {
    final encodedContract = _encodeContract(importContract);
    final trimmedOrigin = origin.trim();
    if (encodedContract == null || trimmedOrigin.isEmpty) {
      return null;
    }

    final originUri = Uri.parse(trimmedOrigin);
    // Use the same port as the origin — canvas is embedded in the same app.
    final targetUri = Uri(
      scheme: originUri.scheme,
      host: originUri.host,
      port: originUri.hasPort ? originUri.port : neurosimPort,
      path: '/canvas',
      queryParameters: {'import_contract': encodedContract},
    );

    return NeurosimHandoffTarget(
      url: targetUri,
      encodedContract: encodedContract,
    );
  }

  static String? _encodeContract(NeurosimImportContract importContract) {
    if (importContract.cnlSpec.trim().isEmpty) {
      return null;
    }

    return base64Url
        .encode(utf8.encode(jsonEncode(importContract.toJson())))
        .replaceAll('=', '');
  }

  static bool exceedsSafePayload(NeurosimHandoffTarget target) {
    return target.encodedContract.length > maxEncodedSpecLength;
  }
}
