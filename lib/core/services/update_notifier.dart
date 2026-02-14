// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import 'package:flutter/foundation.dart';

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
      _timer = Timer.periodic(const Duration(minutes: 30), (_) => _checkForUpdate());
      // Also check when app comes back to foreground
      html.document.addEventListener('visibilitychange', (event) {
        if (html.document.visibilityState == 'visible') {
          _checkForUpdate();
        }
      });
    }
  }

  void _checkForUpdate() {
    try {
      final sw = html.window.navigator.serviceWorker;
      if (sw != null) {
        sw.getRegistration().then((registration) {
          if (registration != null) {
            // Force check for updates
            registration.update();
            
            // Check if there's a waiting worker
            if (registration.waiting != null) {
              _updateAvailable = true;
              notifyListeners();
            }
            
            // Listen for new workers becoming available
            registration.addEventListener('updatefound', (event) {
              final newWorker = registration.installing;
              if (newWorker != null) {
                newWorker.addEventListener('statechange', (event) {
                  if (newWorker.state == 'installed' && html.window.navigator.serviceWorker?.controller != null) {
                    _updateAvailable = true;
                    notifyListeners();
                  }
                });
              }
            });
          }
        });
      }
    } catch (e) {
      debugPrint('UpdateNotifier: $e');
    }
  }

  void applyUpdate() {
    html.window.location.reload();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
