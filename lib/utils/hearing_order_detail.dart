import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/hearing_calendar_fields.dart';
import 'court_order_display.dart';

/// Loads the court order for a reminder card. Hearing text wins over the
/// short inbox line, and a later page stored on another hearing is joined in.
Future<Map<String, dynamic>?> loadHearingOrderDetail({
  String? hearingDocId,
  String? notificationDocId,
  Map<String, dynamic>? seed,
}) async {
  final fs = FirebaseFirestore.instance;
  var hearingId = hearingDocId?.trim() ?? '';
  final notifId = notificationDocId?.trim() ?? '';
  Map<String, dynamic>? hearingData;
  Map<String, dynamic>? notifData;

  if (hearingId.isEmpty) {
    hearingId = HearingCalendarFields.asDisplayString(seed?['hearingDocId']);
  }
  if (notifId.isNotEmpty) {
    final doc = await fs.collection('notifications').doc(notifId).get();
    notifData = doc.data();
    if (hearingId.isEmpty) {
      hearingId = HearingCalendarFields.asDisplayString(
        notifData?['hearingDocId'],
      );
    }
  }
  if (hearingId.isNotEmpty) {
    final doc = await fs.collection('hearings').doc(hearingId).get();
    hearingData = doc.data();
  }

  final pieces = <Map<String, dynamic>>[
    if (hearingData != null) hearingData,
    if (notifData != null) notifData,
    if (seed != null) seed,
  ];
  if (pieces.isEmpty) return null;

  final caseNo = pieces
      .map((piece) => HearingCalendarFields.asDisplayString(piece['caseNo']))
      .firstWhere((value) => value.isNotEmpty, orElse: () => '');
  var orderText = CourtOrderTextSources.joinPieces(
    pieces.map(CourtOrderTextSources.combine).toList(),
  );
  if (caseNo.isNotEmpty && !CourtOrderTextSources.hasClosing(orderText)) {
    final digits = RegExp(r'\d{3,}').firstMatch(caseNo)?.group(0);
    final variants = <String>{
      caseNo,
      if (digits != null) digits,
      if (digits != null) 'Civil Case No. $digits',
    };
    for (final variant in variants) {
      if (CourtOrderTextSources.hasClosing(orderText)) break;
      try {
        final extra = await fs
            .collection('hearings')
            .where('caseNo', isEqualTo: variant)
            .limit(12)
            .get();
        orderText = CourtOrderTextSources.joinPieces([
          orderText,
          ...extra.docs.map(
            (doc) => CourtOrderTextSources.combine(doc.data()),
          ),
        ]);
      } catch (_) {}
    }
  }

  return {
    ...?seed,
    ...?notifData,
    ...?hearingData,
    if (orderText.isNotEmpty) 'fullText': orderText,
    if (hearingId.isNotEmpty) 'hearingDocId': hearingId,
  };
}
