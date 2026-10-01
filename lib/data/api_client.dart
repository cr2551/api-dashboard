import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'service_event.dart';

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;

  @override
  String toString() => 'ApiException: $message';
}

/// The backend answered 401: a token is required or the one sent was wrong.
class UnauthorizedException extends ApiException {
  const UnauthorizedException({required this.hadToken})
    : super(
        hadToken
            ? 'The backend rejected the access token. '
                  'Check it and try again.'
            : 'The backend requires an access token. Enter it to continue.',
      );

  /// Whether a token was sent with the rejected request.
  final bool hadToken;
}

/// Talks to the monitor backend (`server/bin/serve.dart`).
///
/// Override the address at build time with
/// `--dart-define=API_BASE_URL=http://host:port`. When the backend has
/// `API_TOKEN` set, pass the same value with `--dart-define=API_TOKEN=...`
/// (development) or enter it in the app; it is sent as a bearer token.
class ApiClient {
  ApiClient({String? baseUrl, String? apiToken, http.Client? client})
    : baseUrl = baseUrl ?? defaultBaseUrl,
      _apiToken = _blankToNull(apiToken ?? defaultApiToken),
      _client = client ?? http.Client();

  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  static const defaultApiToken = String.fromEnvironment('API_TOKEN');

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  final String baseUrl;
  final http.Client _client;

  /// Sent as `Authorization: Bearer <token>` with every request. Kept in
  /// memory only; it is never written to storage.
  String? get apiToken => _apiToken;
  set apiToken(String? value) => _apiToken = _blankToNull(value);
  String? _apiToken;

  Future<StatusSnapshot> getStatus() async =>
      StatusSnapshot.fromJson(await _get('/api/status', {}));

  Future<ServiceHistory> getHistory(
    String provider, {
    int minutes = 60,
  }) async => ServiceHistory.fromJson(
    await _get('/api/history', {'provider': provider, 'minutes': '$minutes'}),
  );

  /// Breaches that opened or resolved, oldest first. [after] returns only
  /// events with a greater id; [limit] keeps the most recent ones.
  Future<List<ServiceEvent>> getEvents({int? after, int limit = 50}) async =>
      (await getEventsPage(after: after, limit: limit)).events;

  /// Like [getEvents], plus the highest event id the backend holds, which
  /// lets a caller notice that the backend's database was reset.
  Future<EventsPage> getEventsPage({int? after, int limit = 50}) async {
    final json = await _get('/api/events', {
      if (after != null) 'after': '$after',
      'limit': '$limit',
    });
    try {
      return EventsPage(
        events: [
          for (final e in json['events'] as List)
            ServiceEvent.fromJson(e as Map<String, dynamic>),
        ],
        latestId: json['latestId'] as int?,
      );
    } catch (_) {
      throw const ApiException('Backend returned an unexpected response');
    }
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    final uri = Uri.parse(baseUrl)
        .replace(path: path, queryParameters: query.isEmpty ? null : query);
    final http.Response response;
    try {
      final token = _apiToken;
      response = await _client
          .get(
            uri,
            headers: {if (token != null) 'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      throw ApiException('Cannot reach the backend at $baseUrl ($e)');
    }
    if (response.statusCode == 401) {
      throw UnauthorizedException(hadToken: _apiToken != null);
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
