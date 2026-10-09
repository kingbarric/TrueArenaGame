import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'page_cache.dart';

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

  static const base = String.fromEnvironment('API_BASE',
      defaultValue: 'https://vps-8030ec94.vps.ovh.net');

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
  Future<bool>? _tokenRefresh;
  PageCache? pageCache;
  final offline = ValueNotifier<bool>(false);
  dynamic cached(String path) => pageCache?.read(path);
  final _savedResponses = <String>{};
  bool usedSavedResponse(String path) => _savedResponses.contains(path);

  Uri _uri(String path) => Uri.parse('$base/api/v1$path');

  Map<String, String> _headers({bool json = true}) => {
        if (json) 'content-type': 'application/json',
        if (bearer != null) 'authorization': 'Bearer $bearer',
        if (deviceId != null) 'x-device-id': deviceId!,
      };

  Future<dynamic> get(String path) async {
    final cache = pageCache;
    try {
      final value = await _send(
          () => _http.get(_uri(path), headers: _headers(json: false)));
      _savedResponses.remove(path);
      if (identical(cache, pageCache)) await cache?.write(path, value);
      return value;
    } catch (error) {
      if (error is ApiException &&
          [401, 403, 404, 410].contains(error.status)) {
        await cache?.remove(path);
        rethrow;
      }
      final retryable = error is TimeoutException ||
          error is SocketException ||
          error is http.ClientException ||
          (error is ApiException && error.status >= 500);
      final saved = identical(cache, pageCache) ? cache?.read(path) : null;
      if (retryable && saved != null) {
        _savedResponses.add(path);
        return saved;
      }
      rethrow;
    }
  }

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) => _send(
      () => _http.post(_uri(path),
          headers: _headers(), body: jsonEncode(body ?? const {})),
      allowRefresh: path != '/auth/refresh');

  Future<dynamic> patch(String path, [Map<String, dynamic>? body]) =>
      _send(() => _http.patch(_uri(path),
          headers: _headers(), body: jsonEncode(body ?? const {})));

  Future<dynamic> delete(String path, [Map<String, dynamic>? body]) =>
      _send(() => _http.delete(_uri(path),
          headers: _headers(json: body != null),
          body: body == null ? null : jsonEncode(body)));

  Future<dynamic> _send(Future<http.Response> Function() call,
      {bool allowRefresh = true}) async {
    final http.Response res;
    try {
      res = await call().timeout(const Duration(seconds: 8));
    } on TimeoutException {
      offline.value = true;
      rethrow;
    } on SocketException {
      offline.value = true;
      rethrow;
    } on http.ClientException {
      offline.value = true;
      rethrow;
    }
    offline.value = res.statusCode >= 500;
    if (res.statusCode == 401 &&
        allowRefresh &&
        refreshHandler != null &&
        bearer != null) {
      final refresh = _tokenRefresh ??= refreshHandler!();
      bool refreshed;
      try {
        refreshed = await refresh;
      } finally {
        if (identical(_tokenRefresh, refresh)) _tokenRefresh = null;
      }
      if (refreshed) return _send(call, allowRefresh: false);
      // An expired access token plus an offline refresh is not a revoked login.
      if (offline.value) throw http.ClientException('Connection unavailable');
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
          ? decoded['message'].toString()
          : (res.statusCode == 401
              ? 'your session expired — please sign in again'
              : 'request failed');
      throw ApiException(res.statusCode, msg);
    }
    return decoded;
  }
}
