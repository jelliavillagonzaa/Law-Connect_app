import 'web_notification_stub.dart'
    if (dart.library.html) 'web_notification_web.dart' as impl;

Future<void> showBrowserNotification({
  required String title,
  String? body,
}) =>
    impl.showBrowserNotification(title: title, body: body);
