import 'package:get/get.dart';

import '../attorney_selection_screen.dart';
import '../billing_screen.dart';
import '../chat_screen.dart';
import '../notary_portal_screen.dart';
import '../send_request_screen.dart';

Future<void> openAttorneySelection() {
  return Get.to(() => const AttorneySelectionScreen()) ?? Future.value();
}

Future<void> openSendRequest() {
  return Get.to(() => const SendRequestScreen()) ?? Future.value();
}

Future<void> openNotaryPortal() {
  return Get.to(() => const NotaryPortalScreen()) ?? Future.value();
}

Future<void> openBilling() {
  return Get.to(() => const BillingScreen()) ?? Future.value();
}

Future<void> openChat({
  required String conversationId,
  required String otherUserId,
  required String otherUserName,
}) {
  return Get.to(
        () => ChatScreen(
          conversationId: conversationId,
          otherUserId: otherUserId,
          otherUserName: otherUserName,
        ),
      ) ??
      Future.value();
}
