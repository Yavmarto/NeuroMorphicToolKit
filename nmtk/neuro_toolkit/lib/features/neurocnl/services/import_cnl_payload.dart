import 'dart:convert';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/neurocnl_import_contract.dart';

NeurocNlImportContract? decodeImportedContract(Uri uri) {
  final encoded = uri.queryParameters['import_contract']?.trim();
  if (encoded == null || encoded.isEmpty) {
    return null;
  }

  final padding = (4 - encoded.length % 4) % 4;
  final normalized = '$encoded${'=' * padding}';
  final decoded = utf8.decode(base64Url.decode(normalized));
  return NeurocNlImportContract.fromJson(
    jsonDecode(decoded) as Map<String, dynamic>,
  );
}

String? decodeImportedCnl(Uri uri) {
  final encoded = uri.queryParameters['import_cnl']?.trim();
  if (encoded == null || encoded.isEmpty) {
    return null;
  }

  final padding = (4 - encoded.length % 4) % 4;
  final normalized = '$encoded${'=' * padding}';
  return utf8.decode(base64Url.decode(normalized));
}
