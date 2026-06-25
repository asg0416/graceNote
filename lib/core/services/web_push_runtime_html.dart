// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

String getBrowserUserAgent() => html.window.navigator.userAgent;

Future<void> registerBrowserServiceWorker(String scriptPath) async {
  final serviceWorker = html.window.navigator.serviceWorker;
  if (serviceWorker == null) return;

  await serviceWorker.register(scriptPath);
}

void showBrowserNotification(
  String title, {
  String? body,
  String? icon,
}) {
  html.Notification(title, body: body, icon: icon);
}

void listenForBrowserServiceWorkerMessages(
  void Function(String link) onDeepLink,
) {
  final serviceWorker = html.window.navigator.serviceWorker;
  if (serviceWorker == null) return;

  serviceWorker.onMessage.listen((event) {
    final data = event.data;
    if (data is! Map || data['type'] != 'notification_click') return;

    final link = data['link'];
    if (link is String && link.isNotEmpty) {
      onDeepLink(link);
    }
  });
}

String getBrowserLocationHref() => html.window.location.href;

void replaceBrowserHistoryUrl(String path) {
  html.window.history.replaceState(null, '', path);
}

bool isBrowserNotificationDenied() {
  return html.Notification.permission == 'denied';
}
