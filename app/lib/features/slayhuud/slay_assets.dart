import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Serves the 3D studio to its WebView on the device loopback, as the
/// renderer expects (`http://localhost:8187/...`).
///
/// The renderer page is bundled. Art is not, apart from a small starter pack:
/// the catalogue's `assets` manifest maps each `assets/...` path to a
/// content-hashed file on playhuud.com, downloaded once, checked against its
/// SHA-256 and kept on disk. The renderer never knows the difference.
class SlayAssets {
  SlayAssets._([http.Client? client, this._cache])
      : _http = client ?? http.Client();
  static final instance = SlayAssets._();

  @visibleForTesting
  factory SlayAssets.test(http.Client client, Directory cache) =>
      SlayAssets._(client, cache);
  static const port = 8187;

  String _base = '';
  Map<String, Map<String, dynamic>> _files = const {};
  Future<void>? _starting;
  Directory? _cache;
  final _downloads = <String, Future<File>>{};
  final http.Client _http;

  /// Takes the delivery manifest from a catalogue (`GET /slay/catalog`).
  void configure(Map<String, dynamic> catalog) {
    final assets = catalog['assets'];
    if (assets is! Map) return;
    _base = assets['base'] as String? ?? '';
    _files = {
      for (final e in (assets['files'] as Map? ?? const {}).entries)
        e.key as String: Map<String, dynamic>.from(e.value as Map)
    };
    unawaited(_evictStale().catchError((Object e) {
      debugPrint('SlayHuud asset cleanup failed: $e');
    }));
  }

  Future<void> start() =>
      _starting ??= HttpServer.bind('127.0.0.1', port, shared: true)
          .then((server) => server.listen(_handle))
          .catchError((Object error) {
        _starting = null;
        throw error;
      });

  /// Wardrobe thumbnails: bundled when they shipped with the app, else downloaded.
  ImageProvider? thumbnail(String url) {
    final file = _files[url];
    if (file == null) {
      return url.startsWith('http') ? NetworkImage(url) : null;
    }
    return file['bundled'] == true
        ? AssetImage('assets/slay_renderer/starter/${url.split('/').last}')
        : NetworkImage('$_base${file['name']}');
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      var path = Uri.decodeComponent(request.uri.path).replaceFirst('/', '');
      if (path.isEmpty) path = 'index.html';
      final bytes = request.method == 'GET' &&
              !path.split('/').any((part) => part.isEmpty || part == '..')
          ? await _bytes(path)
          : null;
      if (bytes == null) {
        response.statusCode = HttpStatus.notFound;
      } else {
        response.headers.contentType = _type(path);
        response.add(bytes);
      }
    } catch (e) {
      debugPrint('SlayHuud asset ${request.uri.path} failed: $e');
      response.statusCode = HttpStatus.badGateway;
    } finally {
      await response.close();
    }
  }

  @visibleForTesting
  Future<List<int>?> bytesFor(String path) => _bytes(path);

  Future<List<int>?> _bytes(String path) async {
    final file = _files[path];
    if (file == null) {
      // The renderer page itself; art outside the manifest is not served.
      return path.startsWith('assets/')
          ? null
          : _bundled('assets/slay_renderer/$path');
    }
    if (file['bundled'] == true) {
      final starter = await _bundled(
          'assets/slay_renderer/starter/${path.split('/').last}');
      if (starter != null) return starter;
    }
    return (await _download(file)).readAsBytes();
  }

  Future<List<int>?> _bundled(String key) async {
    try {
      return (await rootBundle.load(key)).buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _directory() async => _cache ??= await Directory(
          '${(await getApplicationSupportDirectory()).path}/slay-assets')
      .create(recursive: true);

  Future<File> _download(Map<String, dynamic> file) {
    final name = file['name'] as String;
    return _downloads[name] ??= () async {
      try {
        final target = File('${(await _directory()).path}/$name');
        // Written only after its hash checked out, under a content-hashed name.
        if (await target.exists() && await target.length() == file['bytes']) {
          return target;
        }
        final response = await _http
            .get(Uri.parse('$_base$name'))
            .timeout(const Duration(seconds: 60));
        if (response.statusCode != 200) {
          throw HttpException('HTTP ${response.statusCode} for $name');
        }
        final bytes = response.bodyBytes;
        if (bytes.length != file['bytes'] ||
            sha256.convert(bytes).toString() != file['sha256']) {
          throw HttpException('$name failed its integrity check');
        }
        final part = File('${target.path}.part');
        await part.writeAsBytes(bytes, flush: true);
        return await part.rename(target.path);
      } finally {
        _downloads.remove(name);
      }
    }();
  }

  /// Files from older catalogues are dropped; the current set is ~15 MB at most.
  Future<void> _evictStale() async {
    final current = {for (final f in _files.values) f['name'] as String};
    await for (final entry in (await _directory()).list()) {
      final name = entry.uri.pathSegments.last;
      if (entry is File &&
          !current.contains(name) &&
          !_downloads.containsKey(name)) {
        await entry.delete();
      }
    }
  }

  static ContentType _type(String path) {
    final extension = path.split('.').last.toLowerCase();
    return switch (extension) {
      'html' => ContentType.html,
      'json' => ContentType.json,
      'js' => ContentType('text', 'javascript', charset: 'utf-8'),
      'wasm' => ContentType('application', 'wasm'),
      'txt' => ContentType.text,
      'png' => ContentType('image', 'png'),
      'glb' => ContentType('model', 'gltf-binary'),
      _ => ContentType.binary,
    };
  }
}
