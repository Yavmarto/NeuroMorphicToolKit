import 'dart:convert';
import 'package:http/http.dart' as http;

/// Wraps the Neurosim custom nodes REST API.
class CustomNodeRepository {
  final String baseUrl;
  const CustomNodeRepository({required this.baseUrl});

  static const Duration _requestTimeout = Duration(seconds: 10);

  Future<List<String>> list() async {
    final resp = await http
        .get(Uri.parse('$baseUrl/api/neurosim/custom-nodes'))
        .timeout(_requestTimeout);
    if (resp.statusCode != 200) {
      throw Exception('list failed: ${resp.statusCode}');
    }
    return List<String>.from(jsonDecode(resp.body) as List);
  }

  Future<String> save(
      {required String filename, required String source}) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl/api/neurosim/custom-nodes/save'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'filename': filename, 'source': source}),
        )
        .timeout(_requestTimeout);
    if (resp.statusCode != 200) {
      throw Exception('save failed: ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final installedPath = body['installed_path'];
    if (installedPath == null) {
      throw Exception(
        'save response missing installed_path field. '
        'Check that the Neurosim API version matches the expected contract.',
      );
    }
    return installedPath as String;
  }

  Future<void> delete(String filename) async {
    final resp = await http
        .delete(
          Uri.parse('$baseUrl/api/neurosim/custom-nodes/$filename'),
        )
        .timeout(_requestTimeout);
    if (resp.statusCode != 200) {
      throw Exception('delete failed: ${resp.statusCode}');
    }
  }

  Future<void> install(
      {required String downloadUrl, required String filename}) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl/api/neurosim/custom-nodes/install'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'download_url': downloadUrl, 'filename': filename}),
        )
        .timeout(_requestTimeout);
    if (resp.statusCode != 200) {
      throw Exception('install failed: ${resp.statusCode}');
    }
  }
}
