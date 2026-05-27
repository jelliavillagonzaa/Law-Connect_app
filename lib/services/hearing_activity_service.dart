import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'hearing_calendar_sync_service.dart';
import 'hearing_notification_fanout_service.dart';

/// Activity rows in Firestore `hearings`. Cloud Functions send push, email (if SMTP
/// configured), and in-app `notifications` to everyone on the case — including the sender.
class HearingActivityService {
  HearingActivityService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _hearings =>
      _firestore.collection('hearings');

  /// Real-time stream of hearing rows for one case (newest first).
  Stream<QuerySnapshot<Map<String, dynamic>>> watchHearingsForCase(String caseId) {
    return _hearings
        .where('caseId', isEqualTo: caseId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<String> _resolveSenderName(User user) async {
    final dn = user.displayName?.trim();
    if (dn != null && dn.isNotEmpty) return dn;
    try {
      final snap = await _firestore.collection('users').doc(user.uid).get();
      final n = snap.data()?['name'] as String?;
      if (n != null && n.trim().isNotEmpty) return n.trim();
    } catch (_) {
      /* ignore */
    }
    return 'User';
  }

  /// Same shape as Firestore console / OCR imports (`caseNo`, `fullText`, …). Staff/attorney/admin only (see rules).
  Future<DocumentReference<Map<String, dynamic>>> postCourtHearingRecord({
    required String caseNo,
    required String fullText,
    String? clientName,
    String? courtBranch,
    String? timeZone,
    List<String>? notifyUserIds,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Must be signed in');
    }

    final data = <String, dynamic>{
      'caseNo': caseNo,
      'fullText': fullText,
      'createdAt': FieldValue.serverTimestamp(),
      'uploadedBy': user.uid,
    };
    if (clientName != null && clientName.trim().isNotEmpty) {
      data['clientName'] = clientName.trim();
    }
    if (courtBranch != null && courtBranch.trim().isNotEmpty) {
      data['courtBranch'] = courtBranch.trim();
    }
    if (timeZone != null && timeZone.trim().isNotEmpty) {
      data['timeZone'] = timeZone.trim();
    }
    if (notifyUserIds != null && notifyUserIds.isNotEmpty) {
      data['notifyUserIds'] = notifyUserIds;
    }

    final ref = await _hearings.add(data);
    HearingNotificationFanoutService.instance.scheduleProcess(ref);
    unawaited(HearingCalendarSyncService.instance.syncHearingDoc(ref));
    return ref;
  }

  /// Creates a `hearings` document. Triggers [onHearingActivityCreated] (push, email queue, in-app, reminder jobs).
  Future<DocumentReference<Map<String, dynamic>>> postHearingActivity({
    required String caseId,
    required String caseTitle,
    required String message,
    required String activityType,
    DateTime? hearingDateTime,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Must be signed in to post a hearing activity');
    }

    final senderName = await _resolveSenderName(user);
    final data = <String, dynamic>{
      'caseId': caseId,
      'caseTitle': caseTitle,
      'senderId': user.uid,
      'senderName': senderName,
      'activityType': activityType,
      'message': message,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (hearingDateTime != null) {
      data['hearingDateTime'] = Timestamp.fromDate(hearingDateTime);
    }

    final ref = await _hearings.add(data);
    HearingNotificationFanoutService.instance.scheduleProcess(ref);
    return ref;
  }

  /// Updates an existing activity (same sender only — see Firestore rules). Triggers reminder reschedule when [hearingDateTime] changes.
  Future<void> updateHearingActivity({
    required String hearingDocId,
    required String message,
    required String activityType,
    DateTime? hearingDateTime,
    String? caseTitle,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Must be signed in');
    }

    final data = <String, dynamic>{
      'message': message,
      'activityType': activityType,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (hearingDateTime != null) {
      data['hearingDateTime'] = Timestamp.fromDate(hearingDateTime);
    } else {
      data['hearingDateTime'] = null;
    }
    if (caseTitle != null) data['caseTitle'] = caseTitle;

    final ref = _hearings.doc(hearingDocId);
    await ref.update(data);
    HearingNotificationFanoutService.instance.scheduleProcess(ref);
    unawaited(HearingCalendarSyncService.instance.syncHearingDoc(ref));
  }
}
