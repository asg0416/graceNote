import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:grace_note/core/services/web_update_runtime.dart';

/// Service Worker update detection for PWA version updates.
/// Checks navigator.serviceWorker for waiting workers (new versions).
class UpdateNotifier extends ChangeNotifier {
  bool _updateAvailable = false;
  Timer? _timer;

  bool get updateAvailable => _updateAvailable;

  UpdateNotifier() {
    if (kIsWeb) {
      _checkForUpdate();
      // Check every 30 minutes
      _timer =
          Timer.periodic(const Duration(minutes: 30), (_) => _checkForUpdate());
      // Also check when app comes back to foreground
      addBrowserVisibilityListener(_checkForUpdate);
    }
  }

  void _checkForUpdate() {
    try {
      checkBrowserServiceWorkerUpdate(() {
        _updateAvailable = true;
        notifyListeners();
      });
    } catch (e) {
      debugPrint('UpdateNotifier: $e');
    }
  }

  void applyUpdate() {
    reloadBrowserWindow();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
