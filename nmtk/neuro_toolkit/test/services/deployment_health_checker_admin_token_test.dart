import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/deployment_health_checker.dart';

/// Every doctor endpoint except /api/suite/health sits behind the
/// administrator token. A token-less probe answers 401, which the UI reports
/// as "the backend is not serving requests" and offers to reinstall.
void main() {
  Future<Map<String, String?>> capturedTokens({String adminToken = ''}) async {
    final seen = <String, String?>{};
    final checker = DeploymentHealthChecker(
      httpClient: MockClient((request) async {
        seen[request.url.path] = request.headers['X-NMTK-Admin-Token'];
        return http.Response(
          jsonEncode(
            request.url.path == '/api/suite/doctor'
                ? <String, dynamic>{'checks': <dynamic>[]}
                : <String, dynamic>{
                    'fatalCount': 0,
                    'degradedCount': 0,
                    'akidaHosts': <dynamic>[],
                  },
          ),
          200,
        );
      }),
    );
    final report = await checker.diagnoseHost(
      '192.168.2.90',
      adminToken: adminToken,
    );
    expect(report.overall, isNot(SystemHealthStatus.failed));
    return seen;
  }

  test('doctor probes carry the saved administrator token', () async {
    final seen = await capturedTokens(adminToken: 'secret-token');
    expect(seen['/api/suite/doctor'], 'secret-token');
    expect(seen['/api/launcher/doctor'], 'secret-token');
  });

  test('unsaved quick-connect probes stay token-less', () async {
    final seen = await capturedTokens();
    expect(seen['/api/suite/doctor'], isNull);
    expect(seen['/api/launcher/doctor'], isNull);
  });
}
