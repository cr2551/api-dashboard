import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;

  @override
  String toString() => 'ApiException: $message';
}

/// Talks to the monitor backend (`server/bin/serve.dart`).
///
/// Override the address at build time with
/// `--dart-define=API_BASE_URL=http://host:port`.
class ApiClient {
  ApiClient({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? defaultBaseUrl,
      _client = client ?? http.Client();

  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  final String baseUrl;
  final http.Client _client;

  Future<StatusSnapshot> getStatus() async =>
      StatusSnapshot.fromJson(await _get('/api/status', {}));

  Future<ServiceHistory> getHistory(
    String provider, {
    int minutes = 60,
  }) async => ServiceHistory.fromJson(
    await _get('/api/history', {'provider': provider, 'minutes': '$minutes'}),
  );

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    final uri = Uri.parse(baseUrl)
        .replace(path: path, queryParameters: query.isEmpty ? null : query);
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 10));
    } catch (_) {
      throw ApiException(
        'Cannot reach the backend at $baseUrl. Is it running? '
        'Start it with `dart run bin/serve.dart` in the server/ folder.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException('Backend returned HTTP ${response.statusCode}');
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const ApiException('Backend returned an unexpected response');
    }
  }

  void close() => _client.close();
}
