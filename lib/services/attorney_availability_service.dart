import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/office_time_slots.dart';

/// Occupied attorney times that clients may read.
///
/// Documents store an attorney id, a holder id, and a start time.
/// They do not store client names, case titles, or hearing details.
class AttorneyAvailabilityService {
  AttorneyAvailabilityService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static String slotDocId(String attorneyId, DateTime slotStart) {
    final y = slotStart.year.toString().padLeft(4, '0');
    final m = slotStart.month.toString().padLeft(2, '0');
    final d = slotStart.day.toString().padLeft(2, '0');
    final h = slotStart.hour.toString().padLeft(2, '0');
    final min = slotStart.minute.toString().padLeft(2, '0');
    return '${attorneyId}_$y$m${d}_$h$min';
  }

  CollectionReference<Map<String, dynamic>> get _slots =>
      _firestore.collection('appointment_slots');

  DocumentReference<Map<String, dynamic>> _ref(
    String attorneyId,
    DateTime slotStart,
  ) {
    return _slots.doc(slotDocId(attorneyId, slotStart));
  }

  /// Busy start times for [attorneyId]. Callers must not display holder ids.
  Stream<List<DateTime>> watchBusyStarts(String attorneyId) {
    final aid = attorneyId.trim();
    if (aid.isEmpty) return Stream.value(const []);
    return _slots.where('attorneyId', isEqualTo: aid).snapshots().map((snap) {
      final starts = <DateTime>[];
      for (final doc in snap.docs) {
        final raw = doc.data()['startAt'];
        if (raw is Timestamp) starts.add(raw.toDate());
      }
      return starts;
    });
  }

  /// True when another holder already occupies the office slot that contains
  /// [dateTime]. Times outside the office grid are not treated as taken here.
  Future<bool> isWindowTaken({
    required String attorneyId,
    required DateTime dateTime,
    String? exceptHolderId,
  }) async {
    final aid = attorneyId.trim();
    final window = OfficeTimeSlots.windowStart(dateTime);
    if (aid.isEmpty || window == null) return false;
    try {
      final snap = await _slots.where('attorneyId', isEqualTo: aid).get();
      for (final doc in snap.docs) {
        final holder = doc.data()['appointmentId'] as String?;
        if (exceptHolderId != null &&
            holder != null &&
            holder == exceptHolderId) {
          continue;
        }
        final raw = doc.data()['startAt'];
        if (raw is! Timestamp) continue;
        if (OfficeTimeSlots.occupies(window, raw.toDate())) return true;
      }
    } catch (_) {}
    return false;
  }

  /// Marks [holderId] on the office slot. Does not replace a different holder.
  Future<void> claimHolder({
    required String attorneyId,
    required DateTime when,
    required String holderId,
  }) async {
    final aid = attorneyId.trim();
    final holder = holderId.trim();
    final window = OfficeTimeSlots.windowStart(when);
    if (aid.isEmpty || holder.isEmpty || window == null) return;
    final ref = _ref(aid, window);
    try {
      final existing = await ref.get();
      if (existing.exists) {
        final current = existing.data()?['appointmentId'] as String?;
        if (current != null && current.isNotEmpty && current != holder) {
          return;
        }
        if (current == holder) return;
      }
      await ref.set({
        'attorneyId': aid,
        'appointmentId': holder,
        'startAt': Timestamp.fromDate(window),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Removes every slot owned by [holderId]. Other bookings stay.
  Future<void> releaseHolder({
    required String attorneyId,
    required String holderId,
  }) async {
    final aid = attorneyId.trim();
    final holder = holderId.trim();
    if (aid.isEmpty || holder.isEmpty) return;
    try {
      final snap = await _slots.where('attorneyId', isEqualTo: aid).get();
      for (final doc in snap.docs) {
        final current = doc.data()['appointmentId'] as String?;
        if (current != holder) continue;
        await doc.reference.delete();
      }
    } catch (_) {}
  }

  /// Drops the old slot for [holderId] and claims [when].
  Future<void> moveHolder({
    required String attorneyId,
    required String holderId,
    required DateTime when,
  }) async {
    await releaseHolder(attorneyId: attorneyId, holderId: holderId);
    await claimHolder(
      attorneyId: attorneyId,
      when: when,
      holderId: holderId,
    );
  }
}
