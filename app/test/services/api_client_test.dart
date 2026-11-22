import 'package:flutter_test/flutter_test.dart';
import 'package:home_scatolo/models/item.dart';
import 'package:home_scatolo/models/recognition_candidate.dart';
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

    test('normalizes trailing slash and supports relative same-origin URLs',
        () async {
      final ApiClient client = ApiClient(
        baseUrl: '',
        client: MockClient(
          (http.Request request) async {
            expect(request.url.toString(), '/health');
            return http.Response('{"status":"ok"}', 200);
          },
        ),
      );

      expect(await client.healthCheck(), isTrue);
    });
  });

  group('ApiClient recognize', () {
    test('sends Authorization header when apiToken is configured', () async {
      final ApiClient client = ApiClient(
        baseUrl: 'https://scatolo.example.test/',
        apiToken: 'secret-token',
        client: MockClient(
          (http.Request request) async {
            expect(request.url.toString(), 'https://scatolo.example.test/recognize');
            expect(request.headers['Authorization'], 'Bearer secret-token');
            return http.Response(
              '{"items":[{"name":"Libro","category":"Libri","shortDescription":"Tascabile","quantity":1,"confidence":0.9}]}',
              200,
            );
          },
        ),
      );

      final List<RecognitionCandidate> result = await client.recognize(
        imageBase64: 'aGVsbG8=',
        mimeType: 'image/jpeg',
        existingItems: const <Item>[],
      );

      expect(result, hasLength(1));
      expect(result.single.name, 'Libro');
    });
  });
}
