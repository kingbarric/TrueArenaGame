import 'dart:convert';

import 'package:http/http.dart' as http;

/// What players see when something can't load or the server can't be
/// reached. Never the word "error": it reads as broken, not busy.
const userErrorMessage = "We're trying to connect you to PlayHuud — hold tight.";

/// What players see when a tap or request didn't go through.
const userRetryMessage = "That didn't go through just now — give it another go.";

class ApiException implements Exception {
  ApiException(this.status, this.diagnosticMessage);
  final int status;
  /// For internal flow decisions only; never render this value.
  final String diagnosticMessage;

  /// A refused request reads as "try again"; no answer, or a server in
  /// trouble, reads as "we're connecting you".
  /// 401 is a session being renewed behind the scenes, so it's "connecting" too.
  String get message => status >= 400 && status < 500 && status != 401 ? userRetryMessage : userErrorMessage;
  @override
  String toString() => message;
}

/// Thin JSON client for the TrueArena backend. Base URL is compiled in via
/// `--dart-define=API_BASE=...` (defaults to the local dev server).
class ApiClient {
  ApiClient({http.Client? client}) : _http = client ?? http.Client();

  static const base = String.fromEnvironment('API_BASE', defaultValue: 'https://vps-8030ec94.vps.ovh.net');

  final http.Client _http;

  String? bearer;
  String? deviceId;

  /// Set by `AppState` once it can attempt `/auth/refresh` — the access
  /// token is short-lived (15 min) and this is the *only* place that expiry
  /// gets handled outside of a fresh app launch. Returns whether it got a
  /// new token (and already updated `bearer`); `_send` retries the request
  /// exactly once if so, so a mid-session 401 recovers silently instead of
  /// surfacing as a bodyless "request failed" (Spring Security's 401
  /// entrypoint sends no JSON body, so there's no real message to show).
  Future<bool> Function()? refreshHandler;
  bool _refreshing = false;

  Uri _uri(String path) => Uri.parse('$base/api/v1$path');

  Map<String, String> _headers({bool json = true}) => {
        if (json) 'content-type': 'application/json',
        if (bearer != null) 'authorization': 'Bearer $bearer',
        if (deviceId != null) 'x-device-id': deviceId!,
      };

  Future<dynamic> get(String path) => _send(() => _http.get(_uri(path), headers: _headers(json: false)));

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) =>
      _send(() => _http.post(_uri(path), headers: _headers(), body: jsonEncode(body ?? const {})));

  /// Raw bytes (e.g. an image) instead of JSON, for routes that read the body directly.
  Future<dynamic> postBytes(String path, List<int> bytes, String contentType) =>
      _send(() => _http.post(_uri(path),
          headers: {..._headers(json: false), 'content-type': contentType}, body: bytes));

  Future<dynamic> patch(String path, [Map<String, dynamic>? body]) =>
      _send(() => _http.patch(_uri(path), headers: _headers(), body: jsonEncode(body ?? const {})));

  Future<dynamic> delete(String path, [Map<String, dynamic>? body]) => _send(() => _http.delete(
      _uri(path),
      headers: _headers(json: body != null),
      body: body == null ? null : jsonEncode(body)));

  Future<dynamic> _send(Future<http.Response> Function() call, {bool allowRefresh = true}) async {
    final http.Response res;
    try {
      res = await call();
    } catch (_) {
      throw ApiException(0, 'transport failure');
    }
    if (res.statusCode == 401 && allowRefresh && !_refreshing && refreshHandler != null && bearer != null) {
      _refreshing = true;
      bool refreshed;
      try {
        refreshed = await refreshHandler!();
      } finally {
        _refreshing = false;
      }
      if (refreshed) return _send(call, allowRefresh: false); // retry once with the new bearer
    }
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
          ? (decoded['code'] ?? decoded['message']).toString()
          : (res.statusCode == 401 ? 'your session expired — please sign in again' : 'request failed');
      throw ApiException(res.statusCode, msg);
    }
    return decoded;
  }
}
