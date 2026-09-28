import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:intl/intl.dart';
import 'dart:async';
import '../models/case_model.dart';
import '../utils/calendar_live_hearing_map.dart';
import 'fcm_service.dart';
import 'firestore_mirror_helper.dart';
import 'hearing_calendar_sync_service.dart';
import 'hearing_calendar_fields.dart';
import 'notification_service.dart';
import 'sms_service.dart';

class StaffService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<T> _withEmptyOnError<T>(Stream<T> stream, T empty) {
    return stream.transform(
      StreamTransformer<T, T>.fromHandlers(
        handleError: (error, stack, sink) => sink.add(empty),
      ),
    );
  }

  // Get cases assigned to staff
  Stream<List<CaseModel>> getAssignedCases(String staffId) {
    return _withEmptyOnError(
      _firestore
          .collection('cases')
          .where('staffAssigned', arrayContains: staffId)
          .snapshots()
          .map((snapshot) {
            final cases = snapshot.docs
                .map((doc) => CaseModel.fromFirestore(doc))
                .toList();
            cases.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return cases;
          }),
      const <CaseModel>[],
    );
  }

  // Get all cases from assigned attorney (for staff to view and assist)
  Stream<List<CaseModel>> getAttorneyCases(String attorneyId) {
    return _withEmptyOnError(
      _firestore
          .collection('cases')
          .where('attorneyId', isEqualTo: attorneyId)
          .snapshots()
          .map((snapshot) {
            final cases = snapshot.docs
                .map((doc) => CaseModel.fromFirestore(doc))
                .toList();
            cases.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return cases;
          }),
      const <CaseModel>[],
    );
  }

  // Get all documents from attorney's cases
  Stream<List<Map<String, dynamic>>> getAttorneyCaseDocuments(
    String attorneyId,
  ) {
    return _firestore
        .collection('cases')
        .where('attorneyId', isEqualTo: attorneyId)
        .snapshots()
        .map((snapshot) {
          final allDocuments = <Map<String, dynamic>>[];
          for (var doc in snapshot.docs) {
            final caseData = doc.data();
            final caseId = doc.id;
            final caseTitle = caseData['caseTitle'] ?? 'Untitled Case';
            final documents = caseData['documents'] as List<dynamic>? ?? [];

            for (var docItem in documents) {
              if (docItem is Map<String, dynamic>) {
                allDocuments.add({
                  ...docItem,
                  'caseId': caseId,
                  'caseTitle': caseTitle,
                });
              }
            }
          }
          return allDocuments;
        });
  }

  // Get filing deadlines from attorney's cases
  Stream<List<Map<String, dynamic>>> getAttorneyFilingDeadlines(
    String attorneyId,
  ) {
    return _firestore
        .collection('calendar_events')
        .where('assignedTo', isEqualTo: attorneyId)
        .where('eventType', whereIn: ['filing', 'deadline', 'hearing'])
        .snapshots()
        .map((snapshot) {
          final events = snapshot.docs.map((doc) {
            final data = doc.data();
            return <String, dynamic>{
              'id': doc.id,
              ...data,
              'eventDate': (data['eventDate'] as Timestamp?)?.toDate(),
            };
          }).toList();
          // Sort by eventDate in memory to avoid index requirement
          events.sort((a, b) {
            final aDate = a['eventDate'] as DateTime? ?? DateTime(1970);
            final bDate = b['eventDate'] as DateTime? ?? DateTime(1970);
            return aDate.compareTo(bDate);
          });
          return events;
        });
  }

  // Get clients assigned to attorney (for staff to assist)
  Stream<List<Map<String, dynamic>>> getAttorneyClients(String attorneyId) {
    return _firestore
        .collection('cases')
        .where('attorneyId', isEqualTo: attorneyId)
        .snapshots()
        .map((snapshot) {
          final clientIds = <String>{};
          final clientMap = <String, Map<String, dynamic>>{};

          for (var doc in snapshot.docs) {
            final data = doc.data();
            final clientId = data['clientId'] as String?;
            if (clientId == null || clientId.trim().isEmpty) {
              continue;
            }
            if (!clientIds.contains(clientId)) {
              clientIds.add(clientId);
              clientMap[clientId] = {
                'clientId': clientId,
                'caseCount': 1,
                'latestCaseDate': (data['createdAt'] as Timestamp?)?.toDate(),
              };
            } else {
              final prev = clientMap[clientId]!['caseCount'];
              final prevCount = prev is int
                  ? prev
                  : prev is num
                      ? prev.round()
                      : 0;
              clientMap[clientId]!['caseCount'] = prevCount + 1;
            }
          }

          return clientMap.values.toList();
        });
  }

  // Add case note (for attorney review)
  Future<Map<String, dynamic>> addCaseNote({
    required String caseId,
    required String note,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }

      final result = await HybridDatastore.updateCase(
        id: caseId,
        patch: {
          'notes': FieldValue.arrayUnion([
            {
              'note': note,
              'addedBy': user.uid,
              'addedByName': user.email,
              'addedAt': FieldValue.serverTimestamp(),
              'type': 'staff_note',
            },
          ]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      if (!result.isSuccess) {
        return {'success': false, 'message': result.failureMessage};
      }

      // Log activity
      await logActivity(
        action: 'Case note added',
        details: 'Added note to case',
        resourceType: 'case',
        resourceId: caseId,
      );

      return {'success': true, 'message': 'Note added successfully'};
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to add note: ${e.toString()}',
      };
    }
  }

  // Upload document to case (staff can upload secondary documents)
  Future<Map<String, dynamic>> uploadCaseDocument({
    required String caseId,
    required String documentUrl,
    required String documentName,
    String? documentType,
    String? folder,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }

      final documentData = {
        'url': documentUrl,
        'name': documentName,
        'uploadedBy': user.uid,
        'uploadedByRole': 'staff',
        'uploadedAt': FieldValue.serverTimestamp(),
      };

      if (documentType != null) {
        documentData['type'] = documentType;
      }
      if (folder != null) {
        documentData['folder'] = folder;
      }

      final result = await HybridDatastore.updateCase(
        id: caseId,
        patch: {
          'documents': FieldValue.arrayUnion([documentData]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      if (!result.isSuccess) {
        return {'success': false, 'message': result.failureMessage};
      }

      // Log activity
      await logActivity(
        action: 'Document uploaded',
        details: 'Uploaded $documentName to case',
        resourceType: 'case',
        resourceId: caseId,
      );

      return {'success': true, 'message': 'Document uploaded successfully'};
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to upload document: ${e.toString()}',
      };
    }
  }

  // Update client info (limited fields)
  Future<Map<String, dynamic>> updateClientInfo({
    required String clientId,
    String? phone,
    String? email,
    String? address,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (phone != null) updateData['phone'] = phone;
      if (phone != null) updateData['phoneNumber'] = phone;
      if (email != null) updateData['email'] = email;
      if (address != null) updateData['address'] = address;

      final result = await HybridDatastore.update(
        collection: 'users',
        id: clientId,
        patch: updateData,
      );
      if (!result.isSuccess) throw Exception(result.failureMessage);

      // Log activity
      await logActivity(
        action: 'Client info updated',
        details: 'Updated client contact information',
        resourceType: 'client',
        resourceId: clientId,
      );

      return {'success': true, 'message': 'Client info updated successfully'};
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to update client info: ${e.toString()}',
      };
    }
  }

  List<Map<String, dynamic>> _mapActivityLogDocs(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    int take = 300,
  }) {
    final logs = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();
        logs.add(<String, dynamic>{
          'id': doc.id,
          'action': data['action'],
          'details': data['details'],
          'resourceType': data['resourceType'],
          'resourceId': data['resourceId'],
          'userId': data['userId'],
          'timestamp': parseActivityTimestamp(data['timestamp']) ??
              parseActivityTimestamp(data['createdAt']),
        });
      } catch (_) {}
    }
    logs.sort((a, b) {
      final aTime = parseActivityTimestamp(a['timestamp']) ?? DateTime(1970);
      final bTime = parseActivityTimestamp(b['timestamp']) ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });
    return logs.take(take).toList();
  }

  Future<void> purgeJunkActivityLogs(String staffId) async {
    try {
      final snapshot = await _firestore
          .collection('activity_logs')
          .where('userId', isEqualTo: staffId)
          .limit(300)
          .get();
      final refs = snapshot.docs
          .where((doc) => HearingCalendarFields.isJunkWorkLog(doc.data()))
          .map((doc) => doc.reference)
          .toList();
      for (var i = 0; i < refs.length; i += 400) {
        final batch = _firestore.batch();
        for (final ref in refs.skip(i).take(400)) {
          batch.delete(ref);
        }
        await batch.commit();
      }
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> fetchStaffActivityLogs(
    String staffId,
  ) async {
    await purgeJunkActivityLogs(staffId);
    try {
      final snapshot = await _firestore
          .collection('activity_logs')
          .where('userId', isEqualTo: staffId)
          .limit(300)
          .get();
      return _mapActivityLogDocs(snapshot)
          .where((log) => !HearingCalendarFields.isJunkWorkLog(log))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // Get document upload history for staff
  Stream<List<Map<String, dynamic>>> getDocumentUploadHistory(String staffId) {
    return Stream.fromFuture(() async {
      final logs = await fetchStaffActivityLogs(staffId);
      return logs.where((log) {
        final action = (log['action'] ?? '').toString().toLowerCase();
        return action.contains('upload');
      }).take(100).toList();
    }());
  }

  // Create calendar event/reminder
  Future<Map<String, dynamic>> createCalendarEvent({
    required String eventType,
    required DateTime eventDate,
    required String title,
    String? description,
    String? caseId,
    String? assignedTo, // attorneyId
    String? clientId, // For hearing notifications
    bool remindAttorney = false,
    bool remindClient = false,
    List<String> selectedClientIds = const [],
    bool sendNow = false,
    bool notifyStaff = false,
    String createdByRole = 'staff',
    Map<String, dynamic>? extraFields,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }

      final eventData = <String, dynamic>{
        'eventType': eventType, // deadline, hearing, filing, meeting
        'eventDate': Timestamp.fromDate(eventDate),
        'title': title,
        'createdBy': user.uid,
        'createdByRole': createdByRole,
        'createdAt': FieldValue.serverTimestamp(),
        'notificationSent': false, // Track if 2-day notification was sent
        'remindAttorney': remindAttorney,
        'remindClient': remindClient,
        'selectedClientIds': selectedClientIds,
        'notifyStaff': notifyStaff,
      };

      if (extraFields != null) {
        for (final e in extraFields.entries) {
          eventData[e.key] = e.value;
        }
      }

      if (description != null) eventData['description'] = description;
      if (caseId != null) eventData['caseId'] = caseId;
      if (assignedTo != null) eventData['assignedTo'] = assignedTo;
      if (clientId != null) eventData['clientId'] = clientId;

      final junkNotice = HearingCalendarFields.isNonCourtHearingSpam({
        'title': title,
        'description': description ?? '',
        'message': description ?? '',
        'eventType': eventType,
        ...?extraFields,
      });
      if (eventType == 'hearing' && junkNotice) {
        return {
          'success': false,
          'message': 'This hearing is out of scope and was not saved.',
        };
      }

      final eventResult = await HybridDatastore.add(
        collection: 'calendar_events',
        data: eventData,
      );
      if (!eventResult.isSuccess) throw Exception(eventResult.failureMessage);
      final eventRef = _firestore.collection('calendar_events').doc(eventResult.id!);

      // Send immediate reminders if requested.
      if (sendNow && !junkNotice) {
        await _sendImmediateReminders(
          eventId: eventRef.id,
          eventType: eventType,
          eventDate: eventDate,
          title: title,
          description: description,
          assignedTo: assignedTo,
          remindAttorney: remindAttorney,
          remindClient: remindClient,
          selectedClientIds: selectedClientIds,
          staffId: user.uid,
          notifyStaff: notifyStaff,
        );
      }

      // Schedule reminder notifications for upcoming events
      // For hearings: 2 days before
      // For other events: 1 day before
      final reminderDays = eventType == 'hearing' ? 2 : 1;
      final notificationDate = eventDate.subtract(Duration(days: reminderDays));
      
      if (notificationDate.isAfter(DateTime.now()) && !junkNotice) {
        // Create scheduled reminder document
        final reminderData = {
          'eventId': eventRef.id,
          'eventDate': Timestamp.fromDate(eventDate),
          'notificationDate': Timestamp.fromDate(notificationDate),
          'eventType': eventType,
          'title': title,
          'description': description,
          'caseId': caseId,
          'attorneyId': assignedTo,
          'clientId': clientId,
          'remindAttorney': remindAttorney,
          'remindClient': remindClient,
          'selectedClientIds': selectedClientIds,
          'notifyStaff': notifyStaff,
          'createdBy': user.uid,
          'status': 'pending', // pending, sent
          'createdAt': FieldValue.serverTimestamp(),
        };

        // For hearings, also add to hearing_notifications (skip test / mashed titles)
        if (eventType == 'hearing' && !junkNotice) {
          await HybridDatastore.add(
            collection: 'hearing_notifications',
            data: reminderData,
          );
        }
        
        // Add to calendar_event_reminders collection for all event types
        await _firestore.collection('calendar_event_reminders').add(reminderData);
      }

      // Log activity
      if (!junkNotice) {
        await logActivity(
          action: 'Calendar event created',
          details: 'Created $eventType: $title',
          resourceType: 'calendar',
          resourceId: eventRef.id,
        );
      }

      return {
        'success': true,
        'message': 'Calendar event created successfully',
        'eventId': eventRef.id,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to create event: ${e.toString()}',
      };
    }
  }

  // Send immediate reminders for calendar events
  Future<void> _sendImmediateReminders({
    required String eventId,
    required String eventType,
    required DateTime eventDate,
    required String title,
    String? description,
    String? assignedTo,
    required bool remindAttorney,
    required bool remindClient,
    required List<String> selectedClientIds,
    required String staffId,
    bool notifyStaff = false,
  }) async {
    try {
      final dateStr = _formatDate(eventDate);
      final timeStr = _formatTime(eventDate);
      final eventTypeStr = eventType[0].toUpperCase() + eventType.substring(1);
      
      // Base message with early reminder text
      final baseMessage = 'Early reminder for upcoming important deadlines.\n\n'
          'Event: $title\n'
          'Type: $eventTypeStr\n'
          'Date: $dateStr\n'
          'Time: $timeStr';
      
      final fullMessage = description != null && description.isNotEmpty
          ? '$baseMessage\n\nDescription: $description'
          : baseMessage;

      // Get staff name for the message
      final staffDoc = await _firestore.collection('users').doc(staffId).get();
      final staffName = staffDoc.data()?['name'] ?? 'Staff';

      // Always notify staff (current user who created the event)
      await _createNotification(
        userId: staffId,
        type: 'calendar_reminder',
        title: 'Calendar Event Reminder',
        message: '$fullMessage\n\nYou will be reminded about this event.',
        eventId: eventId,
      );

      // Remind Attorney (if checked)
      if (remindAttorney && assignedTo != null && assignedTo != staffId) {
        await _createNotification(
          userId: assignedTo,
          type: 'calendar_reminder',
          title: 'Calendar Event Reminder',
          message: '$fullMessage\n\nReminder sent by: $staffName',
          eventId: eventId,
        );
      }

      // Notify other Staff members (if checked)
      if (notifyStaff && assignedTo != null) {
        // Get all staff assigned to the attorney (staff are in users collection with role='staff')
        final staffSnapshot = await _firestore
            .collection('users')
            .where('role', isEqualTo: 'staff')
            .where('assignedAttorneyId', isEqualTo: assignedTo)
            .get();
        
        for (var staffDoc in staffSnapshot.docs) {
          final staffUserId = staffDoc.id;
          if (staffUserId != staffId) {
            await _createNotification(
              userId: staffUserId,
              type: 'calendar_reminder',
              title: 'Calendar Event Reminder',
              message: '$fullMessage\n\nReminder sent by: $staffName',
              eventId: eventId,
            );
          }
        }
      }

      // Remind Selected Clients
      if (remindClient && selectedClientIds.isNotEmpty) {
        for (final clientId in selectedClientIds) {
          await _createNotification(
            userId: clientId,
            type: 'calendar_reminder',
            title: 'Calendar Event Reminder',
            message: '$fullMessage\n\nReminder sent by: $staffName',
            eventId: eventId,
            isClient: true,
          );
        }
      }
    } catch (e) {
      // Don't fail event creation if notification fails
      print('Error sending immediate reminders: $e');
    }
  }

  // In-app bell + push + SMS for one recipient.
  Future<void> _createNotification({
    required String userId,
    required String type,
    required String title,
    required String message,
    String? eventId,
    bool isClient = false,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;

    try {
      final notifData = <String, dynamic>{
        'userId': uid,
        if (isClient) 'clientId': uid,
        'type': type,
        'title': title,
        'message': message,
        'summary': message,
        if (eventId != null) 'eventId': eventId,
        'isRead': false,
        'createdAt': Timestamp.fromDate(DateTime.now()),
      };
      await HybridDatastore.add(collection: 'notifications', data: notifData);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error creating notification for user $uid: $e');
      }
    }

    final smsBody = _smsSafeBody(title: title, message: message);

    unawaited(
      FCMService()
          .sendNotificationToUser(
            userId: uid,
            title: title,
            body: smsBody,
            data: <String, dynamic>{
              'type': type,
              if (eventId != null) 'eventId': eventId,
            },
          )
          .catchError((Object e) {
            if (kDebugMode) {
              debugPrint('FCM calendar reminder failed for $uid: $e');
            }
            return false;
          }),
    );

    try {
      if (_auth.currentUser?.uid == uid) {
        await NotificationService().showAlert(
          title: title,
          message: smsBody,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Local calendar reminder failed for $uid: $e');
      }
    }

    unawaited(_sendCalendarSms(userId: uid, body: smsBody));
  }

  String _smsSafeBody({required String title, required String message}) {
    var t = '$title - $message'
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' - ')
        .replaceAll(RegExp(r'[^\x20-\x7E]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'( - ){2,}'), ' - ')
        .trim();
    if (t.length > 480) t = '${t.substring(0, 477)}...';
    return t;
  }

  Future<String?> _phoneForUser(String uid) async {
    try {
      final snap = await _firestore.collection('users').doc(uid).get();
      final data = snap.data() ?? {};
      final profilePhone =
          (data['phoneNumber'] ?? data['phone'])?.toString().trim();
      if (profilePhone == null || profilePhone.isEmpty) return null;
      return profilePhone;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('calendar SMS phone lookup $uid: $e');
      }
      return null;
    }
  }

  Future<void> _sendCalendarSms({
    required String userId,
    required String body,
  }) async {
    try {
      final phone = await _phoneForUser(userId);
      if (phone == null || phone.trim().isEmpty || body.trim().isEmpty) return;
      await SmsService().queueSms(
        to: phone,
        body: body,
        userId: userId,
        meta: const {'kind': 'calendar_reminder'},
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('calendar SMS failed for $userId: $e');
      }
    }
  }

  // Helper to format date
  String _formatDate(DateTime date) {
    return DateFormat('EEEE, MMMM dd, yyyy').format(date);
  }

  // Helper to format time
  String _formatTime(DateTime date) {
    return DateFormat('hh:mm a').format(date);
  }

  // Get upcoming hearing notifications (2 days before) — bounded query.
  Stream<List<Map<String, dynamic>>> getUpcomingHearingNotifications(
    String attorneyId,
  ) {
    final now = DateTime.now();
    final twoDaysFromNow = now.add(const Duration(days: 2));

    return _firestore
        .collection('hearing_notifications')
        .where('attorneyId', isEqualTo: attorneyId)
        .where('status', isEqualTo: 'pending')
        .limit(40)
        .snapshots()
        .map((snapshot) {
          final notifications = <Map<String, dynamic>>[];
          for (var doc in snapshot.docs) {
            final data = doc.data();
            final notificationDate = (data['notificationDate'] as Timestamp?)
                ?.toDate();
            // Filter to only show notifications within 2 days and in the future
            if (notificationDate != null &&
                notificationDate.isAfter(
                  now.subtract(const Duration(days: 1)),
                ) &&
                notificationDate.isBefore(
                  twoDaysFromNow.add(const Duration(days: 1)),
                )) {
              notifications.add({
                'id': doc.id,
                ...data,
                'hearingDate': (data['hearingDate'] as Timestamp?)?.toDate(),
                'notificationDate': notificationDate,
                'createdAt': (data['createdAt'] as Timestamp?)?.toDate(),
              });
            }
          }
          // Sort by notificationDate ascending in memory
          notifications.sort((a, b) {
            final aDate = a['notificationDate'] as DateTime? ?? DateTime(1970);
            final bDate = b['notificationDate'] as DateTime? ?? DateTime(1970);
            return aDate.compareTo(bDate);
          });
          return notifications;
        });
  }

  // Mark notification as sent
  Future<void> markNotificationAsSent(String notificationId) async {
    await _firestore
        .collection('hearing_notifications')
        .doc(notificationId)
        .update({'status': 'sent', 'sentAt': FieldValue.serverTimestamp()});
  }

  // Check and send scheduled calendar event reminders
  Future<void> checkAndSendScheduledReminders() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Get user role and attorney ID
      String? attorneyId;
      String? userRole;
      try {
        final userDoc = await _firestore.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          userRole = userDoc.data()?['role'] as String?;
          if (userRole == 'staff') {
            attorneyId = userDoc.data()?['assignedAttorneyId'] as String?;
            // If staff doesn't have an assigned attorney, skip
            if (attorneyId == null || attorneyId.isEmpty) {
              return;
            }
          } else if (userRole == 'attorney') {
            attorneyId = user.uid; // Attorneys query their own reminders
          } else if (userRole != 'admin') {
            // If user is not staff, attorney, or admin, skip
            return;
          }
          // Admins can query all reminders (no filter needed)
        } else {
          // User document doesn't exist, skip
          return;
        }
      } catch (e) {
        print('Error getting user info: $e');
        return;
      }

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));

      // Use a single equality filter so Firestore does not require a composite index
      // (avoids failed-precondition when indexes are not deployed). Filter today + status
      // in memory — typical reminder volume per attorney is small.
      late final QuerySnapshot<Map<String, dynamic>> remindersSnapshot;
      if (userRole == 'admin') {
        remindersSnapshot = await _firestore
            .collection('calendar_event_reminders')
            .where('status', isEqualTo: 'pending')
            .get();
      } else if (attorneyId != null && attorneyId.isNotEmpty) {
        remindersSnapshot = await _firestore
            .collection('calendar_event_reminders')
            .where('attorneyId', isEqualTo: attorneyId)
            .get();
      } else {
        return;
      }

      final todaysDocs = remindersSnapshot.docs.where((reminderDoc) {
        final data = reminderDoc.data();
        if (data['status']?.toString() != 'pending') return false;
        final nd = data['notificationDate'] as Timestamp?;
        if (nd == null) return false;
        final d = nd.toDate();
        return !d.isBefore(todayStart) && d.isBefore(todayEnd);
      }).toList();

      for (var reminderDoc in todaysDocs) {
        try {
          final data = reminderDoc.data();
          final ev = data['eventId'];
          final calendarEventId = (ev is String && ev.trim().isNotEmpty)
              ? ev.trim()
              : reminderDoc.id;
          final eventDate = (data['eventDate'] as Timestamp).toDate();
          final eventType = data['eventType'] as String? ?? 'event';
          final title = data['title'] as String? ?? 'Calendar Event';
          final description = data['description'] as String?;
          final assignedTo = data['attorneyId'] as String?;
          final remindAttorney = data['remindAttorney'] as bool? ?? false;
          final remindClient = data['remindClient'] as bool? ?? false;
          final selectedClientIds = (data['selectedClientIds'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          final notifyStaff = data['notifyStaff'] as bool? ?? false;

          // Format message
          final dateStr = _formatDate(eventDate);
          final timeStr = _formatTime(eventDate);
          final eventTypeStr = eventType[0].toUpperCase() + eventType.substring(1);

          final baseMessage = 'Reminder: Upcoming event approaching.\n\n'
              'Event: $title\n'
              'Type: $eventTypeStr\n'
              'Date: $dateStr\n'
              'Time: $timeStr';

          final fullMessage = description != null && description.isNotEmpty
              ? '$baseMessage\n\nDescription: $description'
              : baseMessage;

          // Send reminders based on settings
          if (remindAttorney && assignedTo != null) {
            await _createNotification(
              userId: assignedTo,
              type: 'calendar_reminder',
              title: 'Upcoming Event Reminder',
              message: fullMessage,
              eventId: calendarEventId,
            );
          }

          if (remindClient && selectedClientIds.isNotEmpty) {
            for (final clientId in selectedClientIds) {
              await _createNotification(
                userId: clientId,
                type: 'calendar_reminder',
                title: 'Upcoming Event Reminder',
                message: fullMessage,
                eventId: calendarEventId,
                isClient: true,
              );
            }
          }

          if (notifyStaff && assignedTo != null) {
            // Get all staff assigned to the attorney
            final staffSnapshot = await _firestore
                .collection('users')
                .where('role', isEqualTo: 'staff')
                .where('assignedAttorneyId', isEqualTo: assignedTo)
                .get();

            for (var staffDoc in staffSnapshot.docs) {
              await _createNotification(
                userId: staffDoc.id,
                type: 'calendar_reminder',
                title: 'Upcoming Event Reminder',
                message: fullMessage,
                eventId: calendarEventId,
              );
            }
          }

          // Mark reminder as sent
          await reminderDoc.reference.update({
            'status': 'sent',
            'sentAt': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          print('Error processing reminder ${reminderDoc.id}: $e');
        }
      }
    } catch (e) {
      print('Error checking scheduled reminders: $e');
    }
  }

  /// Shared per-attorney stream so dashboard + calendar tab do not open duplicate listeners.
  static final Map<String, Stream<List<Map<String, dynamic>>>>
      _calendarEventsStreamCache = {};
  static final Map<String, Stream<List<Map<String, dynamic>>>>
      _liveHearingsStreamCache = {};

  /// Drop cached Firestore broadcast streams after logout (they stop emitting).
  static void clearCalendarStreamCaches() {
    _calendarEventsStreamCache.clear();
    _liveHearingsStreamCache.clear();
  }

  /// Drop the cached `hearings` listener so Calendar gets a fresh query.
  static void clearLiveHearingsStreamCache() {
    _liveHearingsStreamCache.clear();
  }

  // Get calendar events for staff's attorney (bounded — not entire collection).
  Stream<List<Map<String, dynamic>>> getCalendarEvents(String attorneyId) {
    final aid = attorneyId.trim();
    if (aid.isEmpty) {
      return Stream.value(const []);
    }
    return _calendarEventsStreamCache.putIfAbsent(aid, () {
      return _firestore
          .collection('calendar_events')
          .where('assignedTo', isEqualTo: aid)
          .orderBy('eventDate')
          .limit(350)
          .snapshots()
          .map(_mapCalendarEventDocs)
          .asBroadcastStream();
    });
  }

  static const _heavyCalendarEventKeys = {
    'fullText',
    'message',
    'rawText',
    'body',
    'emailBody',
    'extractedText',
    'hearingOrderExcerpt',
    'orderText',
    'orderExcerpt',
    'attachments',
    'raw',
    'ocrText',
    'html',
  };

  static List<Map<String, dynamic>> _mapCalendarEventDocs(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final events = snapshot.docs.map((doc) {
      final data = doc.data();
      final mapped = <String, dynamic>{'id': doc.id};
      data.forEach((key, value) {
        if (_heavyCalendarEventKeys.contains(key)) return;
        if (key == 'description' && value is String && value.length > 400) {
          return;
        }
        mapped[key] = value;
      });
      mapped['eventDate'] = (data['eventDate'] as Timestamp?)?.toDate();
      mapped['createdAt'] = (data['createdAt'] as Timestamp?)?.toDate();
      return mapped;
    }).toList();
    events.sort((a, b) {
      final aDate = a['eventDate'] as DateTime? ?? DateTime(1970);
      final bDate = b['eventDate'] as DateTime? ?? DateTime(1970);
      return aDate.compareTo(bDate);
    });
    return events;
  }

  /// Live hearings as calendar rows. attorneyUid is optional — newest
  /// hearing/order notices are recorded on staff and attorney calendars.
  Stream<List<Map<String, dynamic>>> watchLiveHearingsForGrid(String attorneyId) {
    final aid = HearingCalendarSyncService.overlayKey(attorneyId);
    return _liveHearingsStreamCache.putIfAbsent(aid, () {
      final controller =
          StreamController<List<Map<String, dynamic>>>.broadcast();
      var rows = <Map<String, dynamic>>[];
      StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? uidSub;
      StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? recentSub;
      var fetching = false;

      void emit() {
        if (controller.isClosed) return;
        controller.add(List<Map<String, dynamic>>.from(rows));
      }

      Future<void> hydrateFromServer() async {
        if (fetching) return;
        fetching = true;
        try {
          final overlay = await HearingCalendarSyncService.instance
              .fetchAutomatedCalendarRows(aid);
          final inbox = await HearingCalendarSyncService.instance
              .fetchRowsFromHearingNotifications(aid);
          final fetched = CalendarLiveHearingMap.mergeHearingRows(
            overlay,
            inbox,
          );
          if (fetched.isEmpty || controller.isClosed) return;
          rows = CalendarLiveHearingMap.mergeHearingRows(rows, fetched);
          emit();
        } catch (e) {
          debugPrint('[HearingCalendar] web/live overlay hydrate failed: $e');
        } finally {
          fetching = false;
        }
      }

      controller.onListen = () {
        final cached =
            HearingCalendarSyncService.instance.peekHearingNavRows(aid);
        if (cached != null && cached.isNotEmpty) {
          rows = CalendarLiveHearingMap.mergeHearingRows(rows, cached);
        }
        if (rows.isNotEmpty) emit();
        if (aid != HearingCalendarSyncService.firmOverlayId) {
          uidSub ??= _firestore
              .collection('hearings')
              .where('attorneyUid', isEqualTo: aid)
              .limit(80)
              .snapshots()
              .listen(
                (snap) {
                  final live =
                      CalendarLiveHearingMap.mapHearingSnapshot(snap, aid);
                  rows = CalendarLiveHearingMap.mergeHearingRows(rows, live);
                  HearingCalendarSyncService.instance.rememberOverlayRows(
                    aid,
                    live,
                  );
                  emit();
                },
                onError: (e) {
                  debugPrint('[HearingCalendar] live hearings stream: $e');
                },
              );
        }
        recentSub ??= _firestore
            .collection('hearings')
            .orderBy('createdAt', descending: true)
            .limit(150)
            .snapshots()
            .listen(
              (snap) {
                final live = CalendarLiveHearingMap.mapHearingDocs(
                  snap.docs,
                  aid,
                );
                if (live.isEmpty) return;
                rows = CalendarLiveHearingMap.mergeHearingRows(rows, live);
                HearingCalendarSyncService.instance.rememberOverlayRows(
                  aid,
                  live,
                );
                emit();
              },
              onError: (e) {
                debugPrint('[HearingCalendar] recent hearings stream: $e');
              },
            );
        unawaited(hydrateFromServer());
        Future<void>.delayed(const Duration(seconds: 4), () {
          if (controller.isClosed) return;
          unawaited(hydrateFromServer());
        });
      };
      controller.onCancel = () {
        if (controller.hasListener) return;
        uidSub?.cancel();
        uidSub = null;
        recentSub?.cancel();
        recentSub = null;
        _liveHearingsStreamCache.remove(aid);
      };

      return controller.stream;
    });
  }

  // Get staff activity logs (one-shot — live snapshots crash Flutter web
  // when Firestore returns FirebaseException).
  Stream<List<Map<String, dynamic>>> getStaffActivityLogs(String staffId) {
    return Stream.fromFuture(fetchStaffActivityLogs(staffId)).asBroadcastStream();
  }

  static DateTime? parseActivityTimestamp(dynamic value) {
    try {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is Timestamp) return value.toDate();
      if (value is int) {
        if (value > 1000000000000) {
          return DateTime.fromMillisecondsSinceEpoch(value);
        }
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }
      if (value is String) return DateTime.tryParse(value);
      return null;
    } catch (_) {
      return null;
    }
  }

  // Log staff activity
  Future<void> logActivity({
    required String action,
    String? details,
    String? resourceType,
    String? resourceId,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      String userRole = 'staff';
      try {
        final ud = await _firestore.collection('users').doc(user.uid).get();
        userRole = ud.data()?['role'] as String? ?? 'staff';
      } catch (_) {}

      final now = DateTime.now();
      final stamp = Timestamp.fromDate(now);
      final activityData = <String, dynamic>{
        'userId': user.uid,
        'userRole': userRole,
        'action': action,
        if (details != null) 'details': details,
        if (resourceType != null) 'resourceType': resourceType,
        if (resourceId != null) 'resourceId': resourceId,
        'timestamp': stamp,
        'createdAt': stamp,
      };
      final result =
          await HybridDatastore.add(collection: 'activity_logs', data: activityData);
      if (!result.firestoreOk && kDebugMode) {
        debugPrint('activity_logs write failed: ${result.firestoreError}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('logActivity failed: $e');
      }
    }
  }
}
