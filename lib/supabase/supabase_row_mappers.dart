import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/case_model.dart';
import '../models/invoice_model.dart';
import '../models/message_model.dart';
import '../models/payment_model.dart';
import 'supabase_mirror_tables.dart';

/// Maps Firestore models / maps to Supabase (snake_case) rows.
class SupabaseRowMappers {
  SupabaseRowMappers._();

  static Map<String, dynamic> caseToRow(CaseModel model) {
    return {
      'id': model.id,
      'client_id': model.clientId,
      if (model.attorneyId != null) 'attorney_id': model.attorneyId,
      'case_title': model.caseTitle,
      'case_type': model.caseType,
      'case_description': model.caseDescription,
      'status': model.status,
      'created_at': model.createdAt.toUtc().toIso8601String(),
      'updated_at': model.updatedAt.toUtc().toIso8601String(),
      'documents': model.documents ?? <String>[],
      'progress': model.progress ?? <String, dynamic>{},
      if (model.staffId != null) 'staff_id': model.staffId,
      'staff_assigned': model.staffAssigned ?? <String>[],
      if (model.hearingDate != null)
        'hearing_date': model.hearingDate!.toUtc().toIso8601String(),
      'is_archived': model.isArchived,
      if (model.archivedAt != null)
        'archived_at': model.archivedAt!.toUtc().toIso8601String(),
    };
  }

  static Map<String, dynamic> caseMapToRow(
    String id,
    Map<String, dynamic> data,
  ) {
    return {
      'id': id,
      'client_id': data['clientId'] ?? '',
      if (data['attorneyId'] != null) 'attorney_id': data['attorneyId'],
      'case_title': data['caseTitle'] ?? '',
      'case_type': data['caseType'] ?? '',
      'case_description': data['caseDescription'] ?? '',
      'status': data['status'] ?? 'pending',
      'created_at': _isoFromFirestore(data['createdAt']),
      'updated_at': _isoFromFirestore(data['updatedAt']),
      'documents': data['documents'] ?? <dynamic>[],
      'progress': data['progress'] ?? <String, dynamic>{},
      if (data['staffId'] != null) 'staff_id': data['staffId'],
      'staff_assigned': data['staffAssigned'] ?? <dynamic>[],
      if (data['hearingDate'] != null)
        'hearing_date': _isoFromFirestore(data['hearingDate']),
      'is_archived': data['isArchived'] == true,
      if (data['archivedAt'] != null)
        'archived_at': _isoFromFirestore(data['archivedAt']),
    };
  }

  static Map<String, dynamic> chatToRow(ChatModel model) {
    return {
      'id': model.id,
      'participants': model.participants,
      if (model.lastMessage != null) 'last_message': model.lastMessage,
      'updated_at': model.updatedAt.toUtc().toIso8601String(),
      if (model.clientId != null) 'client_id': model.clientId,
      if (model.attorneyId != null) 'attorney_id': model.attorneyId,
      if (model.staffId != null) 'staff_id': model.staffId,
      if (model.staffEmail != null) 'staff_email': model.staffEmail,
    };
  }

  static Map<String, dynamic> chatMapToRow(
    String id,
    Map<String, dynamic> data,
  ) {
    return {
      'id': id,
      'participants': data['participants'] ?? <dynamic>[],
      if (data['lastMessage'] != null) 'last_message': data['lastMessage'],
      'updated_at': _isoFromFirestore(data['updatedAt']),
      if (data['clientId'] != null) 'client_id': data['clientId'],
      if (data['attorneyId'] != null) 'attorney_id': data['attorneyId'],
      if (data['staffId'] != null) 'staff_id': data['staffId'],
      if (data['staffEmail'] != null) 'staff_email': data['staffEmail'],
      'deleted_for': data['deletedFor'] ?? <dynamic>[],
    };
  }

  static Map<String, dynamic> messageToRow(MessageModel model) {
    return {
      'id': model.id,
      'chat_id': model.chatId,
      'sender_id': model.senderId,
      'text': model.text,
      if (model.attachmentUrl != null) 'attachment_url': model.attachmentUrl,
      'timestamp': model.timestamp.toUtc().toIso8601String(),
      'is_seen': model.isSeen ?? false,
      if (model.senderRole != null) 'sender_role': model.senderRole,
      'reactions': model.reactions ?? <String, dynamic>{},
    };
  }

  static Map<String, dynamic> messageMapToRow(
    String id,
    String chatId,
    Map<String, dynamic> data,
  ) {
    return {
      'id': id,
      'chat_id': chatId,
      'sender_id': data['senderId'] ?? '',
      'text': data['text'] ?? '',
      if (data['attachmentUrl'] != null)
        'attachment_url': data['attachmentUrl'],
      'timestamp': _isoFromFirestore(data['timestamp']),
      'is_seen': data['isSeen'] == true,
      if (data['senderRole'] != null) 'sender_role': data['senderRole'],
      'reactions': data['reactions'] ?? <String, dynamic>{},
    };
  }

  static Map<String, dynamic> invoiceToRow(InvoiceModel model) {
    return {
      'id': model.id,
      'client_id': model.clientId,
      if (model.clientName != null) 'client_name': model.clientName,
      if (model.caseId != null) 'case_id': model.caseId,
      if (model.caseNumber != null) 'case_number': model.caseNumber,
      if (model.caseTitle != null) 'case_title': model.caseTitle,
      'attorney_id': model.attorneyId,
      if (model.staffId != null) 'staff_id': model.staffId,
      if (model.description != null) 'description': model.description,
      'total_legal_fee': model.totalLegalFee,
      'amount_paid': model.amountPaid,
      'status': model.status,
      if (model.createdBy != null) 'created_by': model.createdBy,
      'created_at': model.createdAt.toUtc().toIso8601String(),
      'updated_at': model.updatedAt.toUtc().toIso8601String(),
      if (model.dueDate != null) 'due_date': model.dueDate!.toUtc().toIso8601String(),
    };
  }

  static Map<String, dynamic> paymentToRow(PaymentModel model) {
    return {
      'id': model.id,
      'invoice_id': model.invoiceId,
      'client_id': model.clientId,
      if (model.clientName != null) 'client_name': model.clientName,
      if (model.caseId != null) 'case_id': model.caseId,
      if (model.caseNumber != null) 'case_number': model.caseNumber,
      if (model.caseTitle != null) 'case_title': model.caseTitle,
      'attorney_id': model.attorneyId,
      'amount': model.amount,
      'method': model.method,
      'status': model.status,
      if (model.referenceNo != null) 'reference_no': model.referenceNo,
      if (model.note != null) 'note': model.note,
      if (model.recordedBy != null) 'recorded_by': model.recordedBy,
      if (model.recordedByName != null) 'recorded_by_name': model.recordedByName,
      if (model.recordedByRole != null) 'recorded_by_role': model.recordedByRole,
      'paid_at': model.paidAt.toUtc().toIso8601String(),
      'created_at': model.createdAt.toUtc().toIso8601String(),
    };
  }

  static String _isoFromFirestore(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toUtc().toIso8601String();
    }
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return DateTime.now().toUtc().toIso8601String();
  }

  // ─── generic Firestore collection → Supabase row ───────────────────────────

  static String camelToSnake(String key) {
    return key.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (match) => '_${match.group(0)!.toLowerCase()}',
    );
  }

  static dynamic _encodeMirrorValue(dynamic value) {
    if (value == null || value is FieldValue) return null;
    if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is DocumentReference) return value.id;
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    if (value is List) {
      return value
          .map((e) => e is Map ? Map<String, dynamic>.from(e) : e)
          .toList();
    }
    return value;
  }

  static String _columnForField(String collection, String firestoreKey) {
    switch (collection) {
      case 'sms_requests':
        if (firestoreKey == 'to') return 'to_number';
        break;
      case 'email_requests':
      case 'court_email_queue':
        if (firestoreKey == 'to') return 'to_email';
        if (firestoreKey == 'from') return 'from_email';
        break;
      case 'system_settings':
        if (firestoreKey == 'maintenanceMode') return 'maintenance_mode';
        break;
    }
    return camelToSnake(firestoreKey);
  }

  static Map<String, dynamic> collectionDocToRow(
    String collection,
    String docId,
    Map<String, dynamic> data,
  ) {
    final row = <String, dynamic>{};

    if (SupabaseMirrorTables.usesEmailPrimaryKey(collection)) {
      row['email'] = docId;
    } else if (collection == 'system_settings') {
      row['id'] = docId;
    } else {
      row['id'] = docId;
    }

    for (final entry in data.entries) {
      final encoded = _encodeMirrorValue(entry.value);
      if (encoded == null) continue;
      final column = _columnForField(collection, entry.key);
      row[column] = encoded;
    }

    _applyCollectionDefaults(collection, row);
    return row;
  }

  static Map<String, dynamic> collectionPatchToRow(
    String collection,
    String docId,
    Map<String, dynamic> patch,
  ) {
    return collectionDocToRow(collection, docId, patch);
  }

  static void _applyCollectionDefaults(
    String collection,
    Map<String, dynamic> row,
  ) {
    final now = DateTime.now().toUtc().toIso8601String();

    switch (collection) {
      case 'sms_requests':
        row.putIfAbsent('to_number', () => '+639000000000');
        row.putIfAbsent('body', () => '');
        row.putIfAbsent('status', () => 'pending');
        row.putIfAbsent('created_at', () => now);
        break;
      case 'notification_requests':
        row.putIfAbsent(
          'fcm_token',
          () => 'pending_sync_placeholder_token',
        );
        row.putIfAbsent('title', () => 'Law Connect');
        row.putIfAbsent('body', () => '');
        row.putIfAbsent('status', () => 'pending');
        row.putIfAbsent('created_at', () => now);
        break;
      case 'email_requests':
        row.putIfAbsent('to_email', () => 'unknown@example.com');
        row.putIfAbsent('subject', () => 'Law Connect');
        row.putIfAbsent('text', () => '');
        row.putIfAbsent('status', () => 'pending');
        row.putIfAbsent('created_at', () => now);
        break;
      case 'users':
        row.putIfAbsent('email', () => '');
        row.putIfAbsent('name', () => '');
        row.putIfAbsent('role', () => 'client');
        row.putIfAbsent('created_at', () => now);
        break;
      case 'notifications':
        row.putIfAbsent('title', () => 'Notification');
        row.putIfAbsent('message', () => '');
        row.putIfAbsent('type', () => 'general');
        row.putIfAbsent('is_read', () => false);
        row.putIfAbsent('created_at', () => now);
        break;
      case 'system_logs':
      case 'activity_logs':
        row.putIfAbsent('action', () => 'unknown');
        row.putIfAbsent('timestamp', () => now);
        row.putIfAbsent('created_at', () => now);
        break;
      case 'pending_signups':
        row.putIfAbsent('role', () => 'client');
        row.putIfAbsent('verified', () => false);
        row.putIfAbsent('created_at', () => now);
        break;
      case 'email_verification_otps':
        row.putIfAbsent('otp', () => '');
        row.putIfAbsent('used', () => false);
        row.putIfAbsent('expires_at', () => now);
        row.putIfAbsent('created_at', () => now);
        break;
      case 'system_settings':
        row.putIfAbsent('updated_at', () => now);
        break;
    }
  }
}
