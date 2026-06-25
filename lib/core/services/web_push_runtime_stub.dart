String getBrowserUserAgent() => '';

Future<void> registerBrowserServiceWorker(String scriptPath) async {}

void showBrowserNotification(
  String title, {
  String? body,
  String? icon,
}) {}

void listenForBrowserServiceWorkerMessages(
  void Function(String link) onDeepLink,
) {}

String getBrowserLocationHref() => '';

void replaceBrowserHistoryUrl(String path) {}

bool isBrowserNotificationDenied() => false;
