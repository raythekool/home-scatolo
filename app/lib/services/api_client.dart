import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/item.dart';
import '../models/recognition_candidate.dart';

const String _defaultBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000',
);
const String _defaultApiToken = String.fromEnvironment('API_TOKEN');
const Duration _requestTimeout = Duration(seconds: 95);
const Duration _healthCheckTimeout = Duration(seconds: 70);

class ApiClient {
  ApiClient({String? baseUrl, String? apiToken, http.Client? client})
      : baseUrl = _normalizeBaseUrl(baseUrl ?? _defaultBaseUrl),
        apiToken = (apiToken ?? _defaultApiToken).trim(),
        _client = client ?? http.Client();

  final String baseUrl;
  final String apiToken;
  final http.Client _client;

  static String _normalizeBaseUrl(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> _jsonHeaders() {
    return <String, String>{
      'Content-Type': 'application/json',
      if (apiToken.isNotEmpty) 'Authorization': 'Bearer $apiToken',
    };
  }

  Future<bool> healthCheck() async {
    try {
      final http.Response response = await _client
          .get(_uri('/health'))
          .timeout(_healthCheckTimeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<RecognitionCandidate>> recognize({
    required String imageBase64,
    required String mimeType,
    required List<Item> existingItems,
  }) async {
    final Uri uri = _uri('/recognize');
    final http.Response response = await _client
        .post(
          uri,
          headers: _jsonHeaders(),
          body: jsonEncode(<String, dynamic>{
            'imageBase64': imageBase64,
            'mimeType': mimeType,
            'existingItems': existingItems
                .where((Item item) => item.id != null)
                .map((Item item) => <String, dynamic>{
                      'id': item.id,
                      'name': item.name,
                      'category': item.category,
                      'quantity': item.quantity,
                    })
                .toList(),
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
    if (decoded is! Map) {
      throw Exception('Invalid recognition response format');
    }
    final dynamic items = decoded['items'];
    if (items is! List) {
      throw Exception('Invalid recognition response format');
    }

    return items.map<RecognitionCandidate>((dynamic entry) {
      if (entry is! Map) {
        throw Exception('Invalid recognition entry format');
      }
      return RecognitionCandidate.fromJson(Map<String, dynamic>.from(entry));
    }).toList();
  }
}
