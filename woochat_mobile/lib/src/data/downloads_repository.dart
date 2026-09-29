import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/message.dart';
import 'web_file_cache_stub.dart' if (dart.library.js_interop) 'web_file_cache_web.dart';

/// Raised when a file could not be fetched or saved.
class DownloadException implements Exception {
  const DownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Files pulled out of chats onto this device, the way WhatsApp keeps them:
/// once a file is saved its ⬇ goes away, and tapping it opens the copy.
///
/// On a phone the app fetches the bytes itself and writes them under its
/// own documents folder, so it knows exactly when the file is there and
/// where. On the web there is no disk to write to, so the browser's own
/// store stands in: a file "downloaded" there is one fetched into Cache
/// Storage, where it survives a reload and opens at once. The ⬇ on the web
/// additionally hands the file to the browser's Save dialog, since that is
/// what a person tapping ⬇ in a browser means.
///
/// What is saved is remembered by URL in preferences, so the icons are
/// right the next time the thread opens.
///
/// A file is stored by WHAT IT IS, not by which message it came in: the
/// name on disk (or the key in the browser's store) is the SHA-256 of its
/// bytes. The same poster sent in ten chats, or the same template image
/// behind ten templates, is ten URLs in the index pointing at one copy —
/// fetched once, saved once, and cleared once.
class DownloadsRepository {
  DownloadsRepository({
    http.Client? client,
    Future<SharedPreferencesWithCache> Function()? prefs,
    Future<Directory> Function()? directory,
  })  : _client = client ?? http.Client(),
        _prefs = prefs ?? _defaultPrefs,
        _directory = directory ?? _defaultDirectory;

  final http.Client _client;
  final Future<SharedPreferencesWithCache> Function() _prefs;
  final Future<Directory> Function() _directory;
  final WebFileCache _webCache = const WebFileCache();

  static const String _prefix = 'download:';

  static Future<SharedPreferencesWithCache> _defaultPrefs() =>
      SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(),
      );

  static Future<Directory> _defaultDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/downloads');
  }

  /// Where the file was saved, or null when it has not been. On the web
  /// the value is the URL itself: there is no path, only the fact.
  Future<String?> localPathFor(String url) async {
    final prefs = await _prefs();
    final path = prefs.getString('$_prefix$url');
    if (path == null) return null;
    // A phone's copy can be cleared behind the app's back (storage
    // cleanup, a reinstall); the icon must come back when it is.
    if (!kIsWeb && !File(path).existsSync()) {
      await prefs.remove('$_prefix$url');
      return null;
    }
    return path;
  }

  /// Every URL saved so far, for marking a whole thread in one read.
  Future<Set<String>> downloadedUrls() async {
    final prefs = await _prefs();
    return <String>{
      for (final key in prefs.keys)
        if (key.startsWith(_prefix)) key.substring(_prefix.length),
    };
  }

  /// The ⬇: saves the file and remembers it. Returns where it went.
  Future<String> download(MessageAttachment attachment) async {
    if (kIsWeb) {
      await _handToBrowser(attachment);
      // Kept in the browser's store as well, so a tap later opens it
      // instead of asking the browser to save it a second time. Best
      // effort: the Save dialog already happened.
      try {
        await _webCache.put(attachment.url);
      } catch (_) {}
      return attachment.url;
    }
    return _fetchToDisk(attachment);
  }

  /// Auto-download: the same as [download] on a phone; on the web, into
  /// the browser's store only — no Save dialog nobody asked for.
  Future<String> prefetch(MessageAttachment attachment) async {
    if (kIsWeb) {
      try {
        await _webCache.put(attachment.url);
      } catch (error) {
        throw DownloadException('Could not fetch ${attachment.name}: $error');
      }
      await _remember(attachment.url, attachment.url);
      return attachment.url;
    }
    return _fetchToDisk(attachment);
  }

  /// Web only: opens the kept copy in a new tab. False when there is none.
  Future<bool> openKept(String url) => _webCache.open(url);

  Future<String> _fetchToDisk(MessageAttachment attachment) async {

    final uri = Uri.tryParse(attachment.url);
    if (uri == null) {
      throw const DownloadException('This file has no address to load from.');
    }

    final http.Response response;
    try {
      response = await _client.get(uri);
    } catch (error) {
      throw DownloadException('Could not fetch ${attachment.name}: $error');
    }
    if (response.statusCode != 200) {
      throw DownloadException(
        'Could not fetch ${attachment.name} (HTTP ${response.statusCode}).',
      );
    }

    final dir = await _directory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    // Content-addressed: the file's name is the hash of its bytes, with the
    // extension kept so the phone knows what to open it with. A second
    // message carrying the same bytes finds the file already there and
    // only adds its URL to the index.
    final file = File('${dir.path}/${contentName(response.bodyBytes, attachment)}');
    if (!file.existsSync()) {
      try {
        await file.writeAsBytes(response.bodyBytes, flush: true);
      } catch (error) {
        throw DownloadException('Could not save ${attachment.name}: $error');
      }
    }

    await _remember(attachment.url, file.path);
    return file.path;
  }

  /// `<sha256>.<ext>` — what a file is called on disk, from its bytes.
  static String contentName(List<int> bytes, MessageAttachment attachment) {
    final ext = attachment.extension;
    return ext.isEmpty
        ? sha256.convert(bytes).toString()
        : '${sha256.convert(bytes)}.$ext';
  }

  /// Web: the browser saves it. Storage's `download=` query makes the
  /// response an attachment under the file's own name.
  Future<String> _handToBrowser(MessageAttachment attachment) async {
    final uri = attachment.downloadUri;
    if (uri == null) {
      throw const DownloadException('This file has no address to load from.');
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      throw DownloadException('Could not download ${attachment.name}.');
    }
    await _remember(attachment.url, attachment.url);
    return attachment.url;
  }

  /// Bytes the saved files take up on this device — the app's folder on a
  /// phone, the browser's store on the web.
  Future<int> totalBytes() async {
    if (kIsWeb) {
      try {
        return await _webCache.totalBytes();
      } catch (_) {
        return 0;
      }
    }
    final dir = await _directory();
    if (!dir.existsSync()) return 0;
    // One small folder of the app's own files: read in one go.
    var total = 0;
    for (final entry in dir.listSync()) {
      if (entry is File) total += entry.lengthSync();
    }
    return total;
  }

  /// Removes every saved file and forgets them, so each ⬇ comes back.
  Future<void> clearAll() async {
    final prefs = await _prefs();
    for (final key in prefs.keys.toList()) {
      if (key.startsWith(_prefix)) await prefs.remove(key);
    }
    if (kIsWeb) {
      await _webCache.clear();
      return;
    }
    final dir = await _directory();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  Future<void> _remember(String url, String path) async {
    final prefs = await _prefs();
    await prefs.setString('$_prefix$url', path);
  }
}
