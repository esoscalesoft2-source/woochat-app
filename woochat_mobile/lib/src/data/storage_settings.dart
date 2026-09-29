import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How much of a photo goes over when it is sent.
enum UploadQuality {
  /// Resized to a phone-screen's worth and recompressed — WhatsApp's own
  /// default, and what makes a send feel instant on a weak connection.
  standard('Standard quality'),

  /// The file as picked. Bigger, slower, every pixel.
  hd('HD quality');

  const UploadQuality(this.label);
  final String label;
}

/// The kinds of media WhatsApp lets you choose between for auto-download.
enum MediaKind {
  photos('Photos'),
  audio('Audio'),
  videos('Videos'),
  documents('Documents');

  const MediaKind(this.label);
  final String label;

  /// The kind an attachment marker's type falls under. A voice note is
  /// not "audio" here — it always downloads, as WhatsApp's page says.
  static MediaKind? of(String attachmentType) => switch (attachmentType) {
        'image' || 'sticker' => MediaKind.photos,
        'audio' => MediaKind.audio,
        'video' => MediaKind.videos,
        'document' => MediaKind.documents,
        _ => null,
      };
}

/// Which media loads by itself on a given kind of connection: any subset
/// of the four kinds. Anything not in the set waits to be asked for.
class AutoDownload {
  const AutoDownload(this.kinds);

  final Set<MediaKind> kinds;

  static const AutoDownload none = AutoDownload(<MediaKind>{});
  static const AutoDownload photosOnly =
      AutoDownload(<MediaKind>{MediaKind.photos});
  static const AutoDownload all = AutoDownload(<MediaKind>{
    MediaKind.photos,
    MediaKind.audio,
    MediaKind.videos,
    MediaKind.documents,
  });

  bool allows(String attachmentType) {
    // Voice notes always.
    if (attachmentType == 'voice') return true;
    final kind = MediaKind.of(attachmentType);
    return kind != null && kinds.contains(kind);
  }

  bool has(MediaKind kind) => kinds.contains(kind);

  /// "No media", "All media", or the kinds picked, in the page's order.
  String get label {
    if (kinds.isEmpty) return 'No media';
    if (kinds.length == MediaKind.values.length) return 'All media';
    return <String>[
      for (final kind in MediaKind.values)
        if (kinds.contains(kind)) kind.label,
    ].join(', ');
  }

  AutoDownload toggled(MediaKind kind) => AutoDownload(
        kinds.contains(kind)
            ? (kinds.toSet()..remove(kind))
            : (kinds.toSet()..add(kind)),
      );

  /// For preferences: the names, comma-joined.
  String encode() => <String>[
        for (final kind in MediaKind.values)
          if (kinds.contains(kind)) kind.name,
      ].join(',');

  static AutoDownload decode(String? raw, AutoDownload fallback) {
    if (raw == null) return fallback;
    final names = raw.split(',').where((n) => n.isNotEmpty).toSet();
    return AutoDownload(<MediaKind>{
      for (final kind in MediaKind.values)
        if (names.contains(kind.name)) kind,
    });
  }
}

/// The Storage and data page's settings, kept on the device — the same
/// three WhatsApp keeps there, with WhatsApp's defaults.
///
/// A [ChangeNotifier] so the thread and the composer pick a change up
/// without a restart. There is one for the app; tests build their own
/// over an in-memory store.
class StorageSettings extends ChangeNotifier {
  StorageSettings({Future<SharedPreferencesWithCache> Function()? prefs})
      : _prefs = prefs ?? _defaultPrefs;

  static StorageSettings instance = StorageSettings();

  final Future<SharedPreferencesWithCache> Function() _prefs;

  static const String _qualityKey = 'storage:upload_quality';
  static const String _mobileKey = 'storage:auto_download:mobile';
  static const String _wifiKey = 'storage:auto_download:wifi';

  UploadQuality _quality = UploadQuality.standard;
  AutoDownload _onMobile = AutoDownload.photosOnly;
  AutoDownload _onWifi = AutoDownload.all;
  bool _loaded = false;

  UploadQuality get uploadQuality => _quality;
  AutoDownload get onMobileData => _onMobile;
  AutoDownload get onWifi => _onWifi;

  static Future<SharedPreferencesWithCache> _defaultPrefs() =>
      SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(),
      );

  /// Reads the saved values once. Safe to call any number of times, and
  /// harmless when there is nowhere to read from — defaults stand.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await _prefs();
      _quality = _enumFrom(
        UploadQuality.values,
        prefs.getString(_qualityKey),
        UploadQuality.standard,
      );
      _onMobile = AutoDownload.decode(
        prefs.getString(_mobileKey),
        AutoDownload.photosOnly,
      );
      _onWifi = AutoDownload.decode(
        prefs.getString(_wifiKey),
        AutoDownload.all,
      );
      notifyListeners();
    } catch (_) {
      // No store (tests, a sandbox): the defaults are the settings.
    }
  }

  Future<void> setUploadQuality(UploadQuality value) async {
    _quality = value;
    notifyListeners();
    await _save(_qualityKey, value.name);
  }

  Future<void> setOnMobileData(AutoDownload value) async {
    _onMobile = value;
    notifyListeners();
    await _save(_mobileKey, value.encode());
  }

  Future<void> setOnWifi(AutoDownload value) async {
    _onWifi = value;
    notifyListeners();
    await _save(_wifiKey, value.encode());
  }

  Future<void> _save(String key, String value) async {
    try {
      final prefs = await _prefs();
      await prefs.setString(key, value);
    } catch (_) {
      // Kept in memory for this session either way.
    }
  }

  static T _enumFrom<T extends Enum>(List<T> values, String? name, T fallback) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }
}
