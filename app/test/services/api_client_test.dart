import 'package:flutter_test/flutter_test.dart';
import 'package:home_scatolo/services/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ApiClient healthCheck', () {
    test('returns true when the backend health endpoint responds with 200',
        () async {
      final ApiClient client = ApiClient(
        baseUrl: 'https://api.example.test',
        client: MockClient(
          (http.Request request) async {
            expect(request.url.path, '/health');
            return http.Response('{"status":"ok"}', 200);
          },
        ),
      );

      expect(await client.healthCheck(), isTrue);
    });

    test('returns false when the backend health endpoint is unavailable',
        () async {
      final ApiClient client = ApiClient(
        baseUrl: 'https://api.example.test',
        client: MockClient(
          (http.Request _) async => http.Response('', 503),
        ),
      );

      expect(await client.healthCheck(), isFalse);
    });
  });
}
