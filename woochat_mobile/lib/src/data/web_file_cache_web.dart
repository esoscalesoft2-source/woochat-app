import 'dart:js_interop';

import 'package:crypto/crypto.dart';
import 'package:web/web.dart' as web;

/// The browser's Cache Storage, standing in for a Downloads folder.
///
/// A web page cannot write to the user's disk without a Save dialog, and
/// the browser refuses to pop several of those on its own — so "downloaded
/// by itself" on the web means fetched into the browser's own store, where
/// it survives a reload and opens at once. That is what WhatsApp Web keeps
/// too. Saving to disk stays a thing the user asks for with the ⬇.
///
/// Entries are keyed by the SHA-256 of the bytes, not the URL: the same
/// file sent under ten URLs is kept once. Each URL is a small alias entry
/// pointing at the hash, so `has(url)` stays one lookup.
class WebFileCache {
  const WebFileCache();

  static const String _name = 'woochat-downloads';

  /// Keys are synthetic URLs on a private origin — Cache Storage wants a
  /// URL for a key, and these can never collide with a real download.
  static String _byHash(String hash) => 'https://woochat.local/file/$hash';
  static String _byUrl(String url) =>
      'https://woochat.local/alias/${Uri.encodeComponent(url)}';

  Future<web.Cache> _cache() => web.window.caches.open(_name).toDart;

  Future<bool> has(String url) async {
    final cache = await _cache();
    return await cache.match(_byUrl(url).toJS).toDart != null;
  }

  /// Fetches the file and keeps it — unless its bytes are already here,
  /// in which case only the alias is added. Throws on a refused fetch.
  Future<void> put(String url) async {
    final response = await web.window.fetch(url.toJS).toDart;
    if (!response.ok) throw StateError('HTTP ${response.status}');
    final bytes = (await response.arrayBuffer().toDart).toDart.asUint8List();
    final hash = sha256.convert(bytes).toString();
    final type = response.headers.get('content-type') ?? 'application/octet-stream';

    final cache = await _cache();
    if (await cache.match(_byHash(hash).toJS).toDart == null) {
      await cache
          .put(
            _byHash(hash).toJS,
            web.Response(
              bytes.toJS,
              web.ResponseInit(headers: _headers(type)),
            ),
          )
          .toDart;
    }
    await cache
        .put(
          _byUrl(url).toJS,
          web.Response(
            hash.toJS,
            web.ResponseInit(headers: _headers('text/plain')),
          ),
        )
        .toDart;
  }

  static web.Headers _headers(String contentType) =>
      web.Headers()..set('content-type', contentType);

  Future<String?> _hashFor(String url) async {
    final cache = await _cache();
    final alias = await cache.match(_byUrl(url).toJS).toDart;
    if (alias == null) return null;
    return (await alias.text().toDart).toDart;
  }

  /// Opens the kept copy in a new tab — the browser shows what it can
  /// (PDFs, pictures) and saves what it cannot. False when nothing is kept.
  Future<bool> open(String url) async {
    final hash = await _hashFor(url);
    if (hash == null) return false;
    final cache = await _cache();
    final match = await cache.match(_byHash(hash).toJS).toDart;
    if (match == null) return false;
    final blob = await match.blob().toDart;
    web.window.open(web.URL.createObjectURL(blob), '_blank');
    return true;
  }

  /// Bytes kept — each distinct file counted once, however many URLs
  /// point at it. Aliases are a few bytes and are not counted.
  Future<int> totalBytes() async {
    final cache = await _cache();
    final keys = (await cache.keys().toDart).toDart;
    var total = 0;
    for (final request in keys) {
      if (!request.url.contains('/file/')) continue;
      final match = await cache.match(request).toDart;
      if (match == null) continue;
      total += (await match.blob().toDart).size;
    }
    return total;
  }

  Future<void> clear() async {
    await web.window.caches.delete(_name).toDart;
  }
}
