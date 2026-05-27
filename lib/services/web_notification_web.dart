// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

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

    html.Notification(title, body: body);
  } catch (_) {
    // Notifications are best-effort on web.
  }
}
