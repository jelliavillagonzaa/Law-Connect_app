import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../models/case_model.dart';
import '../models/hybrid_write_result.dart';
import '../models/invoice_model.dart';
import '../models/payment_model.dart';
import 'supabase_hybrid_sync_service.dart';

/// Writes to Firestore and Supabase **in parallel** — neither depends on the other.
///
/// If Firestore fails, Supabase still receives the data (and vice versa).
/// [HybridWriteResult.isSuccess] is true when at least one backend succeeded.
class HybridDatastore {
  HybridDatastore._();

  static final _db = FirebaseFirestore.instance;
  static final _hybrid = SupabaseHybridSyncService.instance;

  static Future<HybridWriteResult> _parallel({
    required Future<void> Function() firestore,
    required Future<String?> Function() supabase,
    String? id,
  }) async {
    final supabaseRequired = _hybrid.isAvailable;
    var firestoreOk = false;
    var supabaseOk = !supabaseRequired;
    String? firestoreError;
    String? supabaseError;

    await Future.wait<void>([
      () async {
        try {
          await firestore();
          firestoreOk = true;
        } catch (e) {
          firestoreError = e.toString();
        }
      }(),
      if (supabaseRequired)
        supabase().then((String? err) {
          if (err == null) {
            supabaseOk = true;
          } else {
            supabaseError = err;
          }
        }),
    ]);

    if (kDebugMode && (!firestoreOk || !supabaseOk)) {
      if (!firestoreOk) {
        debugPrint('HybridDatastore Firestore: $firestoreError');
      }
      if (!supabaseOk) {
        debugPrint('HybridDatastore Supabase: $supabaseError');
      }
    }

    return HybridWriteResult(
      firestoreOk: firestoreOk,
      supabaseOk: supabaseOk,
      supabaseRequired: supabaseRequired,
      id: id,
      firestoreError: firestoreError,
      supabaseError: supabaseError,
    );
  }

  /// Full document set on both backends (same document id).
  static Future<HybridWriteResult> set({
    required String collection,
    required String id,
    required Map<String, dynamic> data,
    SetOptions? options,
  }) {
    return _parallel(
      id: id,
      firestore: () {
        final docRef = _db.collection(collection).doc(id);
        if (options != null) {
          return docRef.set(data, options);
        }
        return docRef.set(data);
      },
      supabase: () => _hybrid.upsertCollectionDocChecked(collection, id, data),
    );
  }

  /// Partial update on both backends.
  static Future<HybridWriteResult> update({
    required String collection,
    required String id,
    required Map<String, dynamic> patch,
  }) {
    return _parallel(
      id: id,
      firestore: () => _db.collection(collection).doc(id).update(patch),
      supabase: () => _hybrid.upsertCollectionDocChecked(collection, id, patch),
    );
  }

  /// Create with auto-generated id (same id on both backends).
  static Future<HybridWriteResult> add({
    required String collection,
    required Map<String, dynamic> data,
  }) async {
    final id = _db.collection(collection).doc().id;
    return set(collection: collection, id: id, data: data);
  }

  /// Delete from both backends.
  static Future<HybridWriteResult> delete({
    required String collection,
    required String id,
  }) {
    return _parallel(
      id: id,
      firestore: () => _db.collection(collection).doc(id).delete(),
      supabase: () => _hybrid.deleteCollectionDocChecked(collection, id),
    );
  }

  // ─── typed collections (cases, chats, billing) ───────────────────────────

  static Future<HybridWriteResult> addCase({
    required Map<String, dynamic> data,
    required CaseModel mirrorModel,
  }) async {
    final id = mirrorModel.id.isNotEmpty
        ? mirrorModel.id
        : _db.collection('cases').doc().id;
    final model = CaseModel(
      id: id,
      clientId: mirrorModel.clientId,
      attorneyId: mirrorModel.attorneyId,
      caseTitle: mirrorModel.caseTitle,
      caseType: mirrorModel.caseType,
      caseDescription: mirrorModel.caseDescription,
      status: mirrorModel.status,
      createdAt: mirrorModel.createdAt,
      updatedAt: mirrorModel.updatedAt,
      documents: mirrorModel.documents,
      progress: mirrorModel.progress,
      staffId: mirrorModel.staffId,
      staffAssigned: mirrorModel.staffAssigned,
      opposingParty: mirrorModel.opposingParty,
      caseResult: mirrorModel.caseResult,
      hearingDate: mirrorModel.hearingDate,
      isArchived: mirrorModel.isArchived,
      archivedAt: mirrorModel.archivedAt,
    );
    return _parallel(
      id: id,
      firestore: () => _db.collection('cases').doc(id).set(data),
      supabase: () => _hybrid.upsertCaseChecked(model),
    );
  }

  static Future<HybridWriteResult> updateCase({
    required String id,
    required Map<String, dynamic> patch,
  }) {
    return _parallel(
      id: id,
      firestore: () => _db.collection('cases').doc(id).update(patch),
      supabase: () => _hybrid.upsertCasePatchChecked(id, patch),
    );
  }

  static Future<HybridWriteResult> deleteCase(String id) {
    return _parallel(
      id: id,
      firestore: () => _db.collection('cases').doc(id).delete(),
      supabase: () => _hybrid.deleteCaseChecked(id),
    );
  }

  /// Firestore collection is `messages` (Supabase table `chats`).
  static const String _chatCollection = 'messages';

  static Future<HybridWriteResult> setChat({
    required String id,
    required Map<String, dynamic> data,
  }) {
    return _parallel(
      id: id,
      firestore: () => _db.collection(_chatCollection).doc(id).set(data),
      supabase: () => _hybrid.upsertChatMapChecked(id, data),
    );
  }

  static Future<HybridWriteResult> addChat({
    required Map<String, dynamic> data,
  }) async {
    final id = _db.collection(_chatCollection).doc().id;
    return setChat(id: id, data: data);
  }

  static Future<HybridWriteResult> updateChat({
    required String id,
    required Map<String, dynamic> patch,
  }) {
    return _parallel(
      id: id,
      firestore: () => _db.collection(_chatCollection).doc(id).update(patch),
      supabase: () => _hybrid.upsertChatPatchChecked(id, patch),
    );
  }

  static Future<HybridWriteResult> addChatMessage({
    required String chatId,
    required Map<String, dynamic> data,
  }) async {
    final id = _db
        .collection(_chatCollection)
        .doc(chatId)
        .collection('messages')
        .doc()
        .id;
    return _parallel(
      id: id,
      firestore: () => _db
          .collection(_chatCollection)
          .doc(chatId)
          .collection('messages')
          .doc(id)
          .set(data),
      supabase: () => _hybrid.upsertMessageMapChecked(id, chatId, data),
    );
  }

  static Future<HybridWriteResult> updateChatMessage({
    required String chatId,
    required String id,
    required Map<String, dynamic> patch,
  }) {
    return _parallel(
      id: id,
      firestore: () => _db
          .collection(_chatCollection)
          .doc(chatId)
          .collection('messages')
          .doc(id)
          .update(patch),
      supabase: () => _hybrid.upsertMessagePatchChecked(id, patch),
    );
  }

  static Future<HybridWriteResult> deleteChatMessage({
    required String chatId,
    required String id,
  }) {
    return _parallel(
      id: id,
      firestore: () => _db
          .collection(_chatCollection)
          .doc(chatId)
          .collection('messages')
          .doc(id)
          .delete(),
      supabase: () => _hybrid.deleteMessageChecked(id),
    );
  }

  // ─── billing ───────────────────────────────────────────────────────────────

  static Future<HybridWriteResult> addInvoice(InvoiceModel model) async {
    final id = _db.collection('invoices').doc().id;
    final data = model.toFirestore();
    final withId = InvoiceModel(
      id: id,
      clientId: model.clientId,
      clientName: model.clientName,
      caseId: model.caseId,
      caseNumber: model.caseNumber,
      caseTitle: model.caseTitle,
      attorneyId: model.attorneyId,
      staffId: model.staffId,
      description: model.description,
      totalLegalFee: model.totalLegalFee,
      amountPaid: model.amountPaid,
      status: model.status,
      createdBy: model.createdBy,
      createdAt: model.createdAt,
      updatedAt: model.updatedAt,
      dueDate: model.dueDate,
    );
    return _parallel(
      id: id,
      firestore: () => _db.collection('invoices').doc(id).set(data),
      supabase: () => _hybrid.mirrorInvoiceChecked(withId),
    );
  }

  static Future<HybridWriteResult> updateInvoice({
    required String id,
    required Map<String, dynamic> patch,
    InvoiceModel? fullModel,
  }) {
    return _parallel(
      id: id,
      firestore: () => _db.collection('invoices').doc(id).update(patch),
      supabase: () {
        if (fullModel != null) {
          return _hybrid.mirrorInvoiceChecked(fullModel);
        }
        return _hybrid.upsertInvoicePatchChecked(id, patch);
      },
    );
  }

  static Future<HybridWriteResult> deleteInvoice(String id) {
    return _parallel(
      id: id,
      firestore: () => _db.collection('invoices').doc(id).delete(),
      supabase: () => _hybrid.deleteInvoiceChecked(id),
    );
  }

  static Future<HybridWriteResult> addPayment(PaymentModel model) async {
    final id = _db.collection('payments').doc().id;
    final data = model.toFirestore();
    final withId = PaymentModel(
      id: id,
      invoiceId: model.invoiceId,
      clientId: model.clientId,
      clientName: model.clientName,
      caseId: model.caseId,
      caseNumber: model.caseNumber,
      caseTitle: model.caseTitle,
      attorneyId: model.attorneyId,
      amount: model.amount,
      method: model.method,
      status: model.status,
      referenceNo: model.referenceNo,
      note: model.note,
      recordedBy: model.recordedBy,
      recordedByName: model.recordedByName,
      recordedByRole: model.recordedByRole,
      paidAt: model.paidAt,
      createdAt: model.createdAt,
    );
    return _parallel(
      id: id,
      firestore: () => _db.collection('payments').doc(id).set(data),
      supabase: () => _hybrid.mirrorPaymentChecked(withId),
    );
  }

  static Future<HybridWriteResult> deletePayment(String id) {
    return _parallel(
      id: id,
      firestore: () => _db.collection('payments').doc(id).delete(),
      supabase: () => _hybrid.deletePaymentChecked(id),
    );
  }

  /// Batch merge-set (e.g. hearing notification fan-out).
  static Future<HybridWriteResult> setManyMerge({
    required String collection,
    required Map<String, Map<String, dynamic>> docs,
  }) async {
    if (docs.isEmpty) {
      return const HybridWriteResult(firestoreOk: true, supabaseOk: true);
    }

    var firestoreOk = false;
    var supabaseRequired = _hybrid.isAvailable;
    var supabaseOk = !supabaseRequired;
    String? firestoreError;
    String? supabaseError;

    await Future.wait<void>([
      () async {
        try {
          final entries = docs.entries.toList();
          for (var i = 0; i < entries.length; i += 400) {
            final batch = _db.batch();
            for (final e in entries.skip(i).take(400)) {
              batch.set(
                _db.collection(collection).doc(e.key),
                e.value,
                SetOptions(merge: true),
              );
            }
            await batch.commit();
          }
          firestoreOk = true;
        } catch (e) {
          firestoreError = e.toString();
        }
      }(),
      if (supabaseRequired)
        () async {
          try {
            for (final e in docs.entries) {
              final err = await _hybrid.upsertCollectionDocChecked(
                collection,
                e.key,
                e.value,
              );
              if (err != null) throw Exception(err);
            }
            supabaseOk = true;
          } catch (e) {
            supabaseError = e.toString();
          }
        }(),
    ]);

    if (kDebugMode && (!firestoreOk || !supabaseOk)) {
      if (!firestoreOk) {
        debugPrint('HybridDatastore setMany Firestore: $firestoreError');
      }
      if (!supabaseOk) {
        debugPrint('HybridDatastore setMany Supabase: $supabaseError');
      }
    }

    return HybridWriteResult(
      firestoreOk: firestoreOk,
      supabaseOk: supabaseOk,
      supabaseRequired: supabaseRequired,
      firestoreError: firestoreError,
      supabaseError: supabaseError,
    );
  }
}
