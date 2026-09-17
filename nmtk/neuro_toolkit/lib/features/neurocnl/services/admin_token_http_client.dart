import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

/// Session-only transport that authenticates requests from the embedded app.
class AdminTokenHttpClient extends http.BaseClient {
  AdminTokenHttpClient({
    required this.adminToken,
    required this.onReportError,
    this.onRecovered = _noopRecovered,
    http.Client? inner,
  }) : _inner = inner ?? http.Client();

  final String adminToken;
  final NmtkFeatureErrorReporter onReportError;

  /// Invoked when a request completes without a network failure or an auth
  /// rejection, telling the host that a previously-reported connection/auth
  /// error no longer applies. No-op by default.
  final NmtkFeatureRecoveryReporter onRecovered;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (adminToken.isNotEmpty) {
      request.headers['X-NMTK-Admin-Token'] = adminToken;
    }
    try {
      final response = await _inner.send(request);
      if (response.statusCode == 401 || response.statusCode == 403) {
        unawaited(
          onReportError(
            const NmtkFeatureErrorEvent(
              moduleId: NmtkModuleId.neurocnl,
              kind: NmtkFeatureErrorKind.authentication,
              message:
                  'NeuroStudio cannot authenticate with the selected backend.',
            ),
          ),
        );
      } else {
        unawaited(onRecovered());
      }
      return response;
    } on Object {
      unawaited(
        onReportError(
          const NmtkFeatureErrorEvent(
            moduleId: NmtkModuleId.neurocnl,
            kind: NmtkFeatureErrorKind.connection,
            message: 'NeuroStudio cannot reach the selected backend.',
          ),
        ),
      );
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}

Future<void> _noopRecovered() async {}
