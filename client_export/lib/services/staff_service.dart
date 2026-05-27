import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/case_model.dart';

class StaffService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get cases assigned to staff
  Stream<List<CaseModel>> getAssignedCases(String staffId) {
    return _firestore
        .collection('cases')
        .where('staffAssigned', arrayContains: staffId)
        .snapshots()
        .map((snapshot) {
          final cases = snapshot.docs
              .map((doc) => CaseModel.fromFirestore(doc))
              .toList();
          // Sort by createdAt descending in memory
          cases.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return cases;
        });
  }

  // Get all cases from assigned attorney (for staff to view and assist)
  Stream<List<CaseModel>> getAttorneyCases(String attorneyId) {
    return _firestore
        .collection('cases')
        .where('attorneyId', isEqualTo: attorneyId)
        .snapshots()
        .map((snapshot) {
          final cases = snapshot.docs
              .map((doc) => CaseModel.fromFirestore(doc))
              .toList();
          // Sort by createdAt descending in memory
          cases.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return cases;
        });
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
              clientMap[clientId]!['caseCount'] =
                  (clientMap[clientId]!['caseCount'] as int) + 1;
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

      await _firestore.collection('cases').doc(caseId).update({
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
      });

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

      await _firestore.collection('cases').doc(caseId).update({
        'documents': FieldValue.arrayUnion([documentData]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

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

      await _firestore.collection('users').doc(clientId).update(updateData);

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

  // Get document upload history for staff
  Stream<List<Map<String, dynamic>>> getDocumentUploadHistory(String staffId) {
    return _firestore
        .collection('activity_logs')
        .where('userId', isEqualTo: staffId)
        .where('action', isEqualTo: 'Document uploaded')
        .snapshots()
        .map((snapshot) {
          final logs = snapshot.docs.map((doc) {
            final data = doc.data();
            return <String, dynamic>{
              'id': doc.id,
              ...data,
              'timestamp': (data['timestamp'] as Timestamp?)?.toDate(),
            };
          }).toList();
          // Sort by timestamp descending in memory and limit to 100
          logs.sort((a, b) {
            final aTime = a['timestamp'] as DateTime? ?? DateTime(1970);
            final bTime = b['timestamp'] as DateTime? ?? DateTime(1970);
            return bTime.compareTo(aTime);
          });
          return logs.take(100).toList();
        });
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

      final eventRef = await _firestore
          .collection('calendar_events')
          .add(eventData);

      // Send immediate reminders if requested
      if (sendNow) {
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
      
      if (notificationDate.isAfter(DateTime.now())) {
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

        // For hearings, also add to hearing_notifications collection (for backward compatibility)
        if (eventType == 'hearing') {
          await _firestore.collection('hearing_notifications').add(reminderData);
        }
        
        // Add to calendar_event_reminders collection for all event types
        await _firestore.collection('calendar_event_reminders').add(reminderData);
      }

      // Log activity
      await logActivity(
        action: 'Calendar event created',
        details: 'Created $eventType: $title',
        resourceType: 'calendar',
        resourceId: eventRef.id,
      );

      return {
        'success': true,
        'message': 'Calendar event created successfully',
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
      if (remindAttorney && assignedTo != null) {
        // Notify attorney
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
          );
        }
      }
    } catch (e) {
      // Don't fail event creation if notification fails
      print('Error sending immediate reminders: $e');
    }
  }

  // Create notification in Firestore
  Future<void> _createNotification({
    required String userId,
    required String type,
    required String title,
    required String message,
    String? eventId,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': userId,
        'type': type,
        'title': title,
        'message': message,
        'eventId': eventId,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error creating notification for user $userId: $e');
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

  // Get upcoming hearing notifications (2 days before)
  Stream<List<Map<String, dynamic>>> getUpcomingHearingNotifications(
    String attorneyId,
  ) {
    final now = DateTime.now();
    final twoDaysFromNow = now.add(const Duration(days: 2));

    return _firestore
        .collection('hearing_notifications')
        .where('attorneyId', isEqualTo: attorneyId)
        .where('status', isEqualTo: 'pending')
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

  // Get calendar events for staff's attorney
  Stream<List<Map<String, dynamic>>> getCalendarEvents(String attorneyId) {
    return _firestore
        .collection('calendar_events')
        .where('assignedTo', isEqualTo: attorneyId)
        .snapshots()
        .map((snapshot) {
          final events = snapshot.docs.map((doc) {
            final data = doc.data();
            return <String, dynamic>{
              'id': doc.id,
              ...data,
              'eventDate': (data['eventDate'] as Timestamp?)?.toDate(),
              'createdAt': (data['createdAt'] as Timestamp?)?.toDate(),
            };
          }).toList();
          // Sort by eventDate ascending in memory
          events.sort((a, b) {
            final aDate = a['eventDate'] as DateTime? ?? DateTime(1970);
            final bDate = b['eventDate'] as DateTime? ?? DateTime(1970);
            return aDate.compareTo(bDate);
          });
          return events;
        });
  }

  // Get staff activity logs
  Stream<List<Map<String, dynamic>>> getStaffActivityLogs(String staffId) {
    return _firestore
        .collection('activity_logs')
        .where('userId', isEqualTo: staffId)
        .snapshots()
        .map((snapshot) {
          final logs = snapshot.docs.map((doc) {
            final data = doc.data();
            return <String, dynamic>{
              'id': doc.id,
              ...data,
              'timestamp': (data['timestamp'] as Timestamp?)?.toDate(),
            };
          }).toList();
          // Sort by timestamp descending in memory and limit to 50
          logs.sort((a, b) {
            final aTime = a['timestamp'] as DateTime? ?? DateTime(1970);
            final bTime = b['timestamp'] as DateTime? ?? DateTime(1970);
            return bTime.compareTo(aTime);
          });
          return logs.take(50).toList();
        });
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

      await _firestore.collection('activity_logs').add({
        'userId': user.uid,
        'userRole': userRole,
        'action': action,
        'details': details,
        'resourceType': resourceType,
        'resourceId': resourceId,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Silently fail logging
    }
  }
}
