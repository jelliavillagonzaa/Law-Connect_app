import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../models/case_model.dart';
import '../models/invoice_model.dart';
import '../models/message_model.dart';
import '../models/payment_model.dart';
import '../supabase/supabase_row_mappers.dart';
import '../supabase/supabase_mirror_tables.dart';
import '../supabase/supabase_bootstrap.dart';
import 'supabase_service.dart';

/// Mirrors writes to Supabase for reporting, backup, and SQL access.
///
/// Firestore stays the primary source for real-time UI streams.
/// Writes run in parallel via [HybridDatastore] — Supabase does not wait on Firestore.
class SupabaseHybridSyncService {
  SupabaseHybridSyncService._();
  static final SupabaseHybridSyncService instance = SupabaseHybridSyncService._();

  bool get isAvailable => isSupabaseClientReady;

  Future<String?> mirrorInvoiceChecked(InvoiceModel model) async {
    if (!isAvailable) return 'Supabase not initialized.';
    try {
      await SupabaseService.instance.client
          .from('invoices')
          .upsert(SupabaseRowMappers.invoiceToRow(model));
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> mirrorPaymentChecked(PaymentModel model) async {
    if (!isAvailable) return 'Supabase not initialized.';
    try {
      await SupabaseService.instance.client
          .from('payments')
          .upsert(SupabaseRowMappers.paymentToRow(model));
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> upsertCollectionDocChecked(
    String collection,
    String id,
    Map<String, dynamic> data,
  ) async {
    final table = SupabaseMirrorTables.tableFor(collection);
    if (table == null) return null;
    if (!isAvailable) return 'Supabase not initialized.';
    try {
      final row = SupabaseRowMappers.collectionDocToRow(collection, id, data);
      await SupabaseService.instance.client.from(table).upsert(row);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> deleteCollectionDocChecked(String collection, String id) async {
    final table = SupabaseMirrorTables.tableFor(collection);
    if (table == null) return null;
    if (!isAvailable) return 'Supabase not initialized.';
    try {
      final key =
          SupabaseMirrorTables.usesEmailPrimaryKey(collection) ? 'email' : 'id';
      await SupabaseService.instance.client.from(table).delete().eq(key, id);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> upsertCaseMapChecked(
    String id,
    Map<String, dynamic> data,
  ) async {
    if (!isAvailable) return 'Supabase not initialized.';
    try {
      await SupabaseService.instance.client
          .from('cases')
          .upsert(SupabaseRowMappers.caseMapToRow(id, data));
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> upsertCaseChecked(CaseModel model) async {
    if (!isAvailable) return 'Supabase not initialized.';
    try {
      await SupabaseService.instance.client
          .from('cases')
          .upsert(SupabaseRowMappers.caseToRow(model));
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> upsertCasePatchChecked(
    String id,
    Map<String, dynamic> patch,
  ) async {
    if (!isAvailable) return 'Supabase not initialized.';
    try {
      final row = <String, dynamic>{
        'id': id,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (patch.containsKey('clientId')) row['client_id'] = patch['clientId'];
      if (patch.containsKey('attorneyId')) {
        row['attorney_id'] = patch['attorneyId'];
      }
      if (patch.containsKey('caseTitle')) row['case_title'] = patch['caseTitle'];
      if (patch.containsKey('caseDescription')) {
        row['case_description'] = patch['caseDescription'];
      }
      if (patch.containsKey('caseType')) row['case_type'] = patch['caseType'];
      if (patch.containsKey('status')) row['status'] = patch['status'];
      if (patch.containsKey('documents')) row['documents'] = patch['documents'];
      if (patch.containsKey('progress')) row['progress'] = patch['progress'];
      if (patch.containsKey('staffId')) row['staff_id'] = patch['staffId'];
      if (patch.containsKey('staffAssigned')) {
        row['staff_assigned'] = patch['staffAssigned'];
      }
      if (patch.containsKey('opposingParty')) {
        row['opposing_party'] = patch['opposingParty'];
      }
      if (patch.containsKey('caseResult')) {
        row['case_result'] = patch['caseResult'];
      }
      if (patch.containsKey('hearingDate')) {
        row['hearing_date'] = SupabaseRowMappers.caseMapToRow(id, {
          'hearingDate': patch['hearingDate'],
        })['hearing_date'];
      }
      if (patch.containsKey('isArchived')) {
        row['is_archived'] = patch['isArchived'] == true;
      }
      if (patch.containsKey('archivedAt')) {
        row['archived_at'] = SupabaseRowMappers.caseMapToRow(id, {
          'archivedAt': patch['archivedAt'],
        })['archived_at'];
      }
      await SupabaseService.instance.client.from('cases').upsert(row);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> deleteCaseChecked(String id) async {
    if (!isAvailable) return 'Supabase not initialized.';
    try {
      await SupabaseService.instance.client.from('cases').delete().eq('id', id);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> upsertChatMapChecked(
    String id,
    Map<String, dynamic> data,
  ) async {
    if (!isAvailable) return 'Supabase not initialized.';
    try {
      await SupabaseService.instance.client
          .from('chats')
          .upsert(SupabaseRowMappers.chatMapToRow(id, data));
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> upsertChatPatchChecked(
    String id,
    Map<String, dynamic> patch,
  ) async {
    if (!isAvailable) return 'Supabase not initialized.';
    try {
      final row = <String, dynamic>{
        'id': id,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (patch.containsKey('lastMessage')) {
        row['last_message'] = patch['lastMessage'];
      }
      if (patch.containsKey('deletedFor')) {
        row['deleted_for'] = patch['deletedFor'];
      }
      if (patch.containsKey('clientId')) row['client_id'] = patch['clientId'];
      if (patch.containsKey('attorneyId')) {
        row['attorney_id'] = patch['attorneyId'];
      }
      if (patch.containsKey('staffId')) row['staff_id'] = patch['staffId'];
      if (patch.containsKey('staffEmail')) {
        row['staff_email'] = patch['staffEmail'];
      }
      await SupabaseService.instance.client.from('chats').upsert(row);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> upsertMessageMapChecked(
    String id,
    String chatId,
    Map<String, dynamic> data,
  ) async {
    if (!isAvailable) return 'Supabase not initialized.';
    try {
      await SupabaseService.instance.client.from('chat_messages').upsert(
            SupabaseRowMappers.messageMapToRow(id, chatId, data),
          );
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> upsertMessagePatchChecked(
    String id,
    Map<String, dynamic> patch,
  ) async {
    if (!isAvailable) return 'Supabase not initialized.';
    try {
      final row = <String, dynamic>{'id': id};
      if (patch.containsKey('isSeen')) row['is_seen'] = patch['isSeen'] == true;
      if (patch.containsKey('reactions')) row['reactions'] = patch['reactions'];
      await SupabaseService.instance.client.from('chat_messages').upsert(row);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> deleteMessageChecked(String id) async {
    if (!isAvailable) return 'Supabase not initialized.';
    try {
      await SupabaseService.instance.client
          .from('chat_messages')
          .delete()
          .eq('id', id);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> upsertInvoicePatchChecked(
    String id,
    Map<String, dynamic> patch,
  ) async {
    if (!isAvailable) return 'Supabase not initialized.';
    try {
      final row = <String, dynamic>{
        'id': id,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (patch.containsKey('totalLegalFee')) {
        row['total_legal_fee'] = patch['totalLegalFee'];
      }
      if (patch.containsKey('amountPaid')) row['amount_paid'] = patch['amountPaid'];
      if (patch.containsKey('status')) row['status'] = patch['status'];
      if (patch.containsKey('description')) row['description'] = patch['description'];
      await SupabaseService.instance.client.from('invoices').upsert(row);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> deleteInvoiceChecked(String id) async {
    if (!isAvailable) return 'Supabase not initialized.';
    try {
      await SupabaseService.instance.client
          .from('invoices')
          .delete()
          .eq('id', id);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> deletePaymentChecked(String id) async {
    if (!isAvailable) return 'Supabase not initialized.';
    try {
      await SupabaseService.instance.client
          .from('payments')
          .delete()
          .eq('id', id);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  void _mirror(String label, Future<void> Function() action) {
    if (!isAvailable) return;
    unawaited(
      action().catchError((Object e) {
        if (kDebugMode) {
          debugPrint('Supabase hybrid sync ($label): $e');
        }
      }),
    );
  }

  // ─── cases ─────────────────────────────────────────────────────────────────

  void mirrorCase(CaseModel model) {
    _mirror('case ${model.id}', () async {
      await SupabaseService.instance.client
          .from('cases')
          .upsert(SupabaseRowMappers.caseToRow(model));
    });
  }

  void mirrorCaseMap(String id, Map<String, dynamic> data) {
    _mirror('case $id', () async {
      await SupabaseService.instance.client
          .from('cases')
          .upsert(SupabaseRowMappers.caseMapToRow(id, data));
    });
  }

  void mirrorCasePatch(String id, Map<String, dynamic> patch) {
    _mirror('case patch $id', () async {
      final row = <String, dynamic>{
        'id': id,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (patch.containsKey('clientId')) row['client_id'] = patch['clientId'];
      if (patch.containsKey('attorneyId')) {
        row['attorney_id'] = patch['attorneyId'];
      }
      if (patch.containsKey('caseTitle')) row['case_title'] = patch['caseTitle'];
      if (patch.containsKey('caseDescription')) {
        row['case_description'] = patch['caseDescription'];
      }
      if (patch.containsKey('caseType')) row['case_type'] = patch['caseType'];
      if (patch.containsKey('status')) row['status'] = patch['status'];
      if (patch.containsKey('documents')) row['documents'] = patch['documents'];
      if (patch.containsKey('progress')) row['progress'] = patch['progress'];
      if (patch.containsKey('staffId')) row['staff_id'] = patch['staffId'];
      if (patch.containsKey('staffAssigned')) {
        row['staff_assigned'] = patch['staffAssigned'];
      }
      if (patch.containsKey('opposingParty')) {
        row['opposing_party'] = patch['opposingParty'];
      }
      if (patch.containsKey('caseResult')) {
        row['case_result'] = patch['caseResult'];
      }
      if (patch.containsKey('hearingDate')) {
        row['hearing_date'] = SupabaseRowMappers.caseMapToRow(id, {
          'hearingDate': patch['hearingDate'],
        })['hearing_date'];
      }
      if (patch.containsKey('isArchived')) {
        row['is_archived'] = patch['isArchived'] == true;
      }
      if (patch.containsKey('archivedAt')) {
        row['archived_at'] = SupabaseRowMappers.caseMapToRow(id, {
          'archivedAt': patch['archivedAt'],
        })['archived_at'];
      }
      await SupabaseService.instance.client.from('cases').upsert(row);
    });
  }

  void deleteCase(String id) {
    _mirror('delete case $id', () async {
      await SupabaseService.instance.client.from('cases').delete().eq('id', id);
    });
  }

  // ─── chats ─────────────────────────────────────────────────────────────────

  void mirrorChat(ChatModel model) {
    _mirror('chat ${model.id}', () async {
      await SupabaseService.instance.client
          .from('chats')
          .upsert(SupabaseRowMappers.chatToRow(model));
    });
  }

  void mirrorChatMap(String id, Map<String, dynamic> data) {
    _mirror('chat $id', () async {
      await SupabaseService.instance.client
          .from('chats')
          .upsert(SupabaseRowMappers.chatMapToRow(id, data));
    });
  }

  void mirrorChatPatch(String id, Map<String, dynamic> patch) {
    _mirror('chat patch $id', () async {
      final row = <String, dynamic>{
        'id': id,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (patch.containsKey('lastMessage')) {
        row['last_message'] = patch['lastMessage'];
      }
      if (patch.containsKey('deletedFor')) {
        row['deleted_for'] = patch['deletedFor'];
      }
      if (patch.containsKey('clientId')) row['client_id'] = patch['clientId'];
      if (patch.containsKey('attorneyId')) {
        row['attorney_id'] = patch['attorneyId'];
      }
      if (patch.containsKey('staffId')) row['staff_id'] = patch['staffId'];
      if (patch.containsKey('staffEmail')) {
        row['staff_email'] = patch['staffEmail'];
      }
      await SupabaseService.instance.client.from('chats').upsert(row);
    });
  }

  // ─── chat_messages ─────────────────────────────────────────────────────────

  void mirrorMessage(MessageModel model) {
    _mirror('message ${model.id}', () async {
      await SupabaseService.instance.client
          .from('chat_messages')
          .upsert(SupabaseRowMappers.messageToRow(model));
    });
  }

  void mirrorMessageMap(String id, String chatId, Map<String, dynamic> data) {
    _mirror('message $id', () async {
      await SupabaseService.instance.client.from('chat_messages').upsert(
            SupabaseRowMappers.messageMapToRow(id, chatId, data),
          );
    });
  }

  void mirrorMessagePatch(String id, Map<String, dynamic> patch) {
    _mirror('message patch $id', () async {
      final row = <String, dynamic>{'id': id};
      if (patch.containsKey('isSeen')) row['is_seen'] = patch['isSeen'] == true;
      if (patch.containsKey('reactions')) row['reactions'] = patch['reactions'];
      await SupabaseService.instance.client.from('chat_messages').upsert(row);
    });
  }

  void deleteMessage(String id) {
    _mirror('delete message $id', () async {
      await SupabaseService.instance.client
          .from('chat_messages')
          .delete()
          .eq('id', id);
    });
  }

  // ─── invoices ────────────────────────────────────────────────────────────────

  void mirrorInvoice(InvoiceModel model) {
    _mirror('invoice ${model.id}', () async {
      await SupabaseService.instance.client
          .from('invoices')
          .upsert(SupabaseRowMappers.invoiceToRow(model));
    });
  }

  void mirrorInvoicePatch(String id, Map<String, dynamic> patch) {
    _mirror('invoice patch $id', () async {
      final row = <String, dynamic>{
        'id': id,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (patch.containsKey('totalLegalFee')) {
        row['total_legal_fee'] = patch['totalLegalFee'];
      }
      if (patch.containsKey('amountPaid')) row['amount_paid'] = patch['amountPaid'];
      if (patch.containsKey('status')) row['status'] = patch['status'];
      if (patch.containsKey('description')) row['description'] = patch['description'];
      await SupabaseService.instance.client.from('invoices').upsert(row);
    });
  }

  void deleteInvoice(String id) {
    _mirror('delete invoice $id', () async {
      await SupabaseService.instance.client
          .from('invoices')
          .delete()
          .eq('id', id);
    });
  }

  // ─── payments ────────────────────────────────────────────────────────────────

  void mirrorPayment(PaymentModel model) {
    _mirror('payment ${model.id}', () async {
      await SupabaseService.instance.client
          .from('payments')
          .upsert(SupabaseRowMappers.paymentToRow(model));
    });
  }

  void deletePayment(String id) {
    _mirror('delete payment $id', () async {
      await SupabaseService.instance.client
          .from('payments')
          .delete()
          .eq('id', id);
    });
  }

  // ─── generic Firestore collections ─────────────────────────────────────────

  /// Upsert a Firestore document into the matching Supabase mirror table.
  void mirrorFirestoreDoc({
    required String collection,
    required String id,
    required Map<String, dynamic> data,
  }) {
    final table = SupabaseMirrorTables.tableFor(collection);
    if (table == null) return;
    _mirror('$collection/$id', () async {
      final row = SupabaseRowMappers.collectionDocToRow(collection, id, data);
      await SupabaseService.instance.client.from(table).upsert(row);
    });
  }

  /// Partial upsert after Firestore `.update()`.
  void mirrorFirestorePatch({
    required String collection,
    required String id,
    required Map<String, dynamic> patch,
  }) {
    mirrorFirestoreDoc(collection: collection, id: id, data: patch);
  }

  /// Remove a mirrored row (id or email primary key).
  void deleteFirestoreDoc({
    required String collection,
    required String id,
  }) {
    final table = SupabaseMirrorTables.tableFor(collection);
    if (table == null) return;
    _mirror('delete $collection/$id', () async {
      final key =
          SupabaseMirrorTables.usesEmailPrimaryKey(collection) ? 'email' : 'id';
      await SupabaseService.instance.client.from(table).delete().eq(key, id);
    });
  }
}
