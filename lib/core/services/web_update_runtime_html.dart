// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

Future<void> checkBrowserServiceWorkerUpdate(
  void Function() onUpdateAvailable,
) async {
  final serviceWorker = html.window.navigator.serviceWorker;
  if (serviceWorker == null) return;

  final registration = await serviceWorker.getRegistration();

  await registration.update();

  if (registration.waiting != null) {
    onUpdateAvailable();
  }

  registration.addEventListener('updatefound', (event) {
    final newWorker = registration.installing;
    if (newWorker == null) return;

    newWorker.addEventListener('statechange', (event) {
      final hasController =
          html.window.navigator.serviceWorker?.controller != null;
      if (newWorker.state == 'installed' && hasController) {
        onUpdateAvailable();
      }
    });
  });
}

void addBrowserVisibilityListener(void Function() onVisible) {
  html.document.addEventListener('visibilitychange', (event) {
    if (html.document.visibilityState == 'visible') {
      onVisible();
    }
  });
}

void reloadBrowserWindow() {
  html.window.location.reload();
}
