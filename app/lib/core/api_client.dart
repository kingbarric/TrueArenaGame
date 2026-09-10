import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => 'ApiException($status): $message';
}

/// Thin JSON client for the TrueArena backend. Base URL is compiled in via
/// `--dart-define=API_BASE=...` (defaults to the local dev server).
class ApiClient {
  ApiClient({http.Client? client}) : _http = client ?? http.Client();

  static const base = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8080');

  final http.Client _http;

  String? bearer;
  String? deviceId;

  Uri _uri(String path) => Uri.parse('$base/api/v1$path');

  Map<String, String> _headers({bool json = true}) => {
        if (json) 'content-type': 'application/json',
        if (bearer != null) 'authorization': 'Bearer $bearer',
        if (deviceId != null) 'x-device-id': deviceId!,
      };

  Future<dynamic> get(String path) => _send(() => _http.get(_uri(path), headers: _headers(json: false)));

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) =>
      _send(() => _http.post(_uri(path), headers: _headers(), body: jsonEncode(body ?? const {})));

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    final res = await call();
    final ok = res.statusCode >= 200 && res.statusCode < 300;
    dynamic decoded;
    if (res.body.isNotEmpty) {
      try {
        decoded = jsonDecode(res.body);
      } catch (_) {
        decoded = res.body;
      }
    }
    if (!ok) {
      final msg = decoded is Map && decoded['message'] != null
          ? decoded['message'].toString()
          : 'request failed';
      throw ApiException(res.statusCode, msg);
    }
    return decoded;
  }
}
