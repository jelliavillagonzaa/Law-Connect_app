// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// dart:html [html.Notification] constructor named args are only:
/// `dir`, `body`, `lang`, `tag`, `icon`.
/// JS NotificationOptions such as `silent`, `badge`, `vibrate`,
/// `requireInteraction`, and `renotify` are not constructor parameters
/// and will fail the Chrome compile before the app starts.
html.Notification _createBrowserNotification(String title, {String? body}) {
  return html.Notification(title, body: body);
}

Future<void> showBrowserNotification({
  required String title,
  String? body,
}) async {
  try {
    if (!html.Notification.supported) return;

    var permission = html.Notification.permission;
    if (permission == 'default') {
      permission = await html.Notification.requestPermission();
    }
    if (permission != 'granted') return;

    _createBrowserNotification(title, body: body);
  } catch (_) {
    // Notifications are best-effort on web.
  }
}
