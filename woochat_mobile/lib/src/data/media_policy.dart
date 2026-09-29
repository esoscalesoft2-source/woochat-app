import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'storage_settings.dart';

/// Whether a piece of media in a thread should load by itself right now:
/// the auto-download setting for the connection the device is on.
///
/// Wi-Fi and a cable count as Wi-Fi; mobile data is mobile data; with no
/// connection nothing can load anyway, so the Wi-Fi rule is used and the
/// image simply fails to arrive. Listens to both the settings and the
/// connection, so a thread redraws when either changes.
class MediaPolicy extends ChangeNotifier {
  MediaPolicy({
    StorageSettings? settings,
    Stream<List<ConnectivityResult>>? connectivity,
  })  : _settings = settings ?? StorageSettings.instance,
        _connectivity =
            connectivity ?? Connectivity().onConnectivityChanged {
    _settings.addListener(notifyListeners);
    _subscription = _connectivity.listen((results) {
      final mobile = _isMobile(results);
      if (mobile == _onMobile) return;
      _onMobile = mobile;
      notifyListeners();
    });
    unawaited(_settings.load());
  }

  static MediaPolicy instance = MediaPolicy();

  final StorageSettings _settings;
  final Stream<List<ConnectivityResult>> _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _onMobile = false;

  /// True while the device is on mobile data (and not also on Wi-Fi).
  bool get onMobileData => _onMobile;

  AutoDownload get rule =>
      _onMobile ? _settings.onMobileData : _settings.onWifi;

  bool autoLoads(String attachmentType) => rule.allows(attachmentType);

  static bool _isMobile(List<ConnectivityResult> results) =>
      results.contains(ConnectivityResult.mobile) &&
      !results.contains(ConnectivityResult.wifi) &&
      !results.contains(ConnectivityResult.ethernet);

  @override
  void dispose() {
    _settings.removeListener(notifyListeners);
    _subscription?.cancel();
    super.dispose();
  }
}
