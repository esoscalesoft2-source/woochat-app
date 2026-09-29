import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import 'supabase_client.dart';
import 'templates_repository.dart';

/// The approved templates, read from the server once and kept on the
/// device — not re-read every time the Templates sheet opens.
///
/// The list changes rarely (a template is approved, edited or deleted) and
/// is read often (every closed-window send), and the full rows are heavy:
/// bodies, header media. So:
///
///  1. The first open in a session hands back the saved copy at once —
///     no spinner — and, in the background, asks the server only for the
///     ids and their `updated_at`. If that fingerprint matches, nothing
///     more is read. If it differs, the full list is fetched and saved.
///  2. From then on the copy is in memory, and a Realtime subscription on
///     `whatsapp_templates` is what triggers a re-read: the list is only
///     fetched again when something on the server actually changed.
///
/// A missing copy (first run, cleared storage) reads the server directly.
class ApprovedTemplatesCache {
  ApprovedTemplatesCache({
    Future<List<MessageTemplate>> Function()? fetchAll,
    Future<String> Function()? fetchFingerprint,
    Future<SharedPreferencesWithCache> Function()? prefs,
    this.subscribe = true,
  })  : _fetchAll = fetchAll ?? TemplatesRepository.fetchApprovedFromServer,
        _fetchFingerprint =
            fetchFingerprint ?? TemplatesRepository.fetchApprovedFingerprint,
        _prefs = prefs ?? _defaultPrefs;

  /// The one the app uses; tests build their own.
  static ApprovedTemplatesCache instance = ApprovedTemplatesCache();

  final Future<List<MessageTemplate>> Function() _fetchAll;
  final Future<String> Function() _fetchFingerprint;
  final Future<SharedPreferencesWithCache> Function() _prefs;

  /// False in tests, which have no Realtime to subscribe to.
  final bool subscribe;

  static const String _listKey = 'templates:approved';
  static const String _fingerprintKey = 'templates:approved:fingerprint';

  List<MessageTemplate>? _memory;
  Future<List<MessageTemplate>>? _inFlight;
  bool _checkedThisSession = false;
  RealtimeChannel? _channel;

  /// Fires with the new list whenever the server's changed and the copy
  /// was refreshed, so a sheet that is open can redraw.
  final ValueNotifier<List<MessageTemplate>?> latest =
      ValueNotifier<List<MessageTemplate>?>(null);

  static Future<SharedPreferencesWithCache> _defaultPrefs() =>
      SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(),
      );

  /// ids + updated_at, order-independent, so two reads of the same rows
  /// always agree.
  static String fingerprintOf(Iterable<(String, String?)> rows) {
    final parts = <String>[for (final (id, at) in rows) '$id@${at ?? ''}']
      ..sort();
    return parts.join('|');
  }

  /// The approved templates, the fastest honest way available.
  Future<List<MessageTemplate>> get() {
    final memory = _memory;
    if (memory != null) return Future<List<MessageTemplate>>.value(memory);
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<List<MessageTemplate>> _load() async {
    _listen();
    final saved = await _readSaved();
    if (saved != null) {
      _memory = saved;
      // Hand back the copy now; find out whether it is stale without
      // making anyone wait for the answer.
      if (!_checkedThisSession) {
        _checkedThisSession = true;
        unawaited(_refreshIfChanged());
      }
      return saved;
    }
    _checkedThisSession = true;
    return _refresh();
  }

  /// Asks only for the fingerprint; reads the whole list only on a change.
  Future<void> _refreshIfChanged() async {
    try {
      final prefs = await _prefs();
      final known = prefs.getString(_fingerprintKey);
      final now = await _fetchFingerprint();
      if (known == now) return;
      await _refresh(fingerprint: now);
    } catch (_) {
      // Offline, or the check failed: the saved copy stands. The next
      // Realtime event or session will try again.
    }
  }

  /// Reads the full list, saves it, and tells listeners.
  Future<List<MessageTemplate>> _refresh({String? fingerprint}) async {
    final list = await _fetchAll();
    _memory = list;
    try {
      final prefs = await _prefs();
      await prefs.setString(
        _listKey,
        jsonEncode(<Map<String, dynamic>>[for (final t in list) t.toMap()]),
      );
      await prefs.setString(
        _fingerprintKey,
        fingerprint ??
            fingerprintOf(<(String, String?)>[
              for (final t in list) (t.id, t.updatedAt),
            ]),
      );
    } catch (_) {
      // Could not save: still served from memory for this session.
    }
    latest.value = list;
    return list;
  }

  Future<List<MessageTemplate>?> _readSaved() async {
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(_listKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return <MessageTemplate>[
        for (final item in decoded)
          if (item is Map<String, dynamic>) MessageTemplate.fromMap(item),
      ];
    } catch (_) {
      // A copy that cannot be read is no copy.
      return null;
    }
  }

  /// One subscription for the app's life: any change to the table on the
  /// server is the only thing, after the first load, that re-reads it.
  void _listen() {
    if (!subscribe || _channel != null) return;
    _channel = db
        .channel('whatsapp_templates:approved')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: Db.whatsappTemplates,
          callback: (_) => unawaited(_refreshIfChanged()),
        )
        .subscribe();
  }

  /// Drops the copy — used when the signed-in tenant changes, since the
  /// list is theirs.
  Future<void> clear() async {
    _memory = null;
    _checkedThisSession = false;
    try {
      final prefs = await _prefs();
      await prefs.remove(_listKey);
      await prefs.remove(_fingerprintKey);
    } catch (_) {}
  }
}
