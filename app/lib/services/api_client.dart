import 'dart:convert';

import 'package:http/http.dart' as http;

// NOTE: Change this to an HTTPS URL for any non-local deployment.
// Do not hardcode tokens or secrets here.
const String _defaultBaseUrl = 'http://localhost:3000';
const Duration _requestTimeout = Duration(seconds: 30);

class ApiClient {
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? _defaultBaseUrl;

  final String baseUrl;

  Future<List<Map<String, dynamic>>> recognize(String base64Image) async {
    final Uri uri = Uri.parse('$baseUrl/recognize');
    final http.Response response = await http
        .post(
          uri,
          headers: <String, String>{
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'image': base64Image,
          }),
        )
        .timeout(
          _requestTimeout,
          onTimeout: () => throw Exception('Recognition request timed out'),
        );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Recognition request failed: ${response.statusCode}');
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Invalid recognition response format');
    }

    return decoded.map<Map<String, dynamic>>((dynamic entry) {
      if (entry is Map<String, dynamic>) {
        return entry;
      }
      if (entry is Map) {
        return Map<String, dynamic>.from(entry);
      }
      throw Exception('Invalid recognition entry format');
    }).toList();
  }
}
