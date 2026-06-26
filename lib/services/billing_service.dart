import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../models/invoice_model.dart';
import '../models/payment_model.dart';
import 'firestore_mirror_helper.dart';
import 'supabase_hybrid_sync_service.dart';

/// Result of a billing write, mirroring the `{success, message}` convention
/// used elsewhere in the app.
class BillingResult {
  final bool success;
  final String? message;
  final String? id;

  const BillingResult({required this.success, this.message, this.id});
}

/// Reads/writes `invoices` + `payments` for the case billing system.
///
/// Payments are made physically at the law office. The attorney or staff who
/// handles the case records each payment with [recordPayment], which adds a
/// receipt and increments the invoice's `amountPaid` directly. Clients view
/// their balance and history read-only.
class BillingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SupabaseHybridSyncService _supabase = SupabaseHybridSyncService.instance;

  static const String _invoices = 'invoices';
  static const String _payments = 'payments';

  // ---------------------------------------------------------------------------
  // Invoice streams
  // ---------------------------------------------------------------------------

  Stream<List<InvoiceModel>> streamInvoicesForClient(String clientId) {
    return _firestore
        .collection(_invoices)
        .where('clientId', isEqualTo: clientId)
        .snapshots()
        .map(_mapInvoices);
  }

  Stream<List<InvoiceModel>> streamInvoicesForAttorney(String attorneyId) {
    return _firestore
        .collection(_invoices)
        .where('attorneyId', isEqualTo: attorneyId)
        .snapshots()
        .map(_mapInvoices);
  }

  Stream<List<InvoiceModel>> streamInvoicesForCase(String caseId) {
    return _firestore
        .collection(_invoices)
        .where('caseId', isEqualTo: caseId)
        .snapshots()
        .map(_mapInvoices);
  }

  Stream<InvoiceModel?> streamInvoice(String invoiceId) {
    return _firestore
        .collection(_invoices)
        .doc(invoiceId)
        .snapshots()
        .map((d) => d.exists ? InvoiceModel.fromFirestore(d) : null);
  }

  Future<InvoiceModel?> getInvoice(String invoiceId) async {
    final doc = await _firestore.collection(_invoices).doc(invoiceId).get();
    return doc.exists ? InvoiceModel.fromFirestore(doc) : null;
  }

  List<InvoiceModel> _mapInvoices(QuerySnapshot snap) {
    final invoices = snap.docs
        .map((d) => InvoiceModel.fromFirestore(d))
        .toList();
    invoices.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return invoices;
  }

  // ---------------------------------------------------------------------------
  // Payment streams
  // ---------------------------------------------------------------------------

  Stream<List<PaymentModel>> streamPaymentsForClient(String clientId) {
    return _firestore
        .collection(_payments)
        .where('clientId', isEqualTo: clientId)
        .snapshots()
        .map(_mapPayments);
  }

  Stream<List<PaymentModel>> streamPaymentsForAttorney(String attorneyId) {
    return _firestore
        .collection(_payments)
        .where('attorneyId', isEqualTo: attorneyId)
        .snapshots()
        .map(_mapPayments);
  }

  Stream<List<PaymentModel>> streamPaymentsForInvoice(String invoiceId) {
    return _firestore
        .collection(_payments)
        .where('invoiceId', isEqualTo: invoiceId)
        .snapshots()
        .map(_mapPayments);
  }

  List<PaymentModel> _mapPayments(QuerySnapshot snap) {
    final payments = snap.docs
        .map((d) => PaymentModel.fromFirestore(d))
        .toList();
    payments.sort((a, b) => b.paidAt.compareTo(a.paidAt));
    return payments;
  }

  // ---------------------------------------------------------------------------
  // Invoice writes (attorney / staff / admin)
  // ---------------------------------------------------------------------------

  /// Issues an invoice (sets the total legal fee) for a client's case.
  Future<BillingResult> createInvoice({
    required String clientId,
    required String attorneyId,
    required double totalLegalFee,
    String? clientName,
    String? caseId,
    String? caseNumber,
    String? caseTitle,
    String? description,
    String? staffId,
    String? createdBy,
    DateTime? dueDate,
  }) async {
    try {
      final now = DateTime.now();
      final invoice = InvoiceModel(
        id: '',
        clientId: clientId,
        clientName: clientName,
        caseId: caseId,
        caseNumber: caseNumber,
        caseTitle: caseTitle,
        attorneyId: attorneyId,
        staffId: staffId,
        description: description,
        totalLegalFee: totalLegalFee,
        amountPaid: 0,
        status: InvoiceStatus.unpaid,
        createdBy: createdBy,
        createdAt: now,
        updatedAt: now,
        dueDate: dueDate,
      );
      final data = invoice.toFirestore();
      data['createdAt'] = FieldValue.serverTimestamp();
      data['updatedAt'] = FieldValue.serverTimestamp();

      final result = await HybridDatastore.addInvoice(invoice);
      if (!result.isSuccess || result.id == null) {
        return BillingResult(success: false, message: result.failureMessage);
      }
      return BillingResult(success: true, id: result.id);
    } catch (e) {
      if (kDebugMode) debugPrint('createInvoice failed: $e');
      return BillingResult(
        success: false,
        message: 'Failed to issue invoice: $e',
      );
    }
  }

  /// Adjusts the legal fee / description of an existing invoice.
  Future<BillingResult> updateInvoiceFee({
    required InvoiceModel invoice,
    required double totalLegalFee,
    String? description,
  }) async {
    try {
      final status = InvoiceStatus.fromAmounts(
        totalLegalFee,
        invoice.amountPaid,
      );
      final patch = <String, dynamic>{
        'totalLegalFee': totalLegalFee,
        if (description != null) 'description': description,
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final result = await HybridDatastore.updateInvoice(
        id: invoice.id,
        patch: patch,
      );
      if (!result.isSuccess) {
        return BillingResult(success: false, message: result.failureMessage);
      }
      return const BillingResult(success: true);
    } catch (e) {
      if (kDebugMode) debugPrint('updateInvoiceFee failed: $e');
      return BillingResult(
        success: false,
        message: 'Failed to update invoice: $e',
      );
    }
  }

  Future<BillingResult> cancelInvoice(String invoiceId) async {
    try {
      final result = await HybridDatastore.updateInvoice(
        id: invoiceId,
        patch: {
          'status': InvoiceStatus.cancelled,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      if (!result.isSuccess) {
        return BillingResult(success: false, message: result.failureMessage);
      }
      return const BillingResult(success: true);
    } catch (e) {
      return BillingResult(success: false, message: 'Failed to cancel: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Recording physical payments (attorney / staff / admin)
  // ---------------------------------------------------------------------------

  /// Records a payment physically received from the client.
  ///
  /// Adds a `payments` receipt and, in the same transaction, increases the
  /// invoice's `amountPaid` and recomputes its status. Then notifies the
  /// client that a payment was recorded.
  Future<BillingResult> recordPayment({
    required InvoiceModel invoice,
    required double amount,
    required String method,
    String? referenceNo,
    String? note,
    DateTime? paidAt,
    required String recordedBy,
    String? recordedByName,
    String? recordedByRole,
  }) async {
    if (amount <= 0) {
      return const BillingResult(
        success: false,
        message: 'Enter a valid payment amount.',
      );
    }

    final paymentId = _firestore.collection(_payments).doc().id;
    final when = paidAt ?? DateTime.now();

    // Resolve a name for the audit trail if one wasn't supplied.
    String? resolvedName = recordedByName;
    if ((resolvedName == null || resolvedName.isEmpty) &&
        recordedBy.isNotEmpty) {
      resolvedName = await _lookupUserName(recordedBy);
    }

    try {
      final invoiceRef = _firestore.collection(_invoices).doc(invoice.id);
      final invoiceSnap = await invoiceRef.get();
      if (!invoiceSnap.exists) {
        return const BillingResult(
          success: false,
          message: 'Invoice no longer exists.',
        );
      }
      final current = InvoiceModel.fromFirestore(invoiceSnap);
      if (current.isCancelled) {
        return const BillingResult(
          success: false,
          message: 'This invoice was cancelled.',
        );
      }
      final newPaid = current.amountPaid + amount;
      final newStatus = InvoiceStatus.fromAmounts(
        current.totalLegalFee,
        newPaid,
      );

      final paymentModel = PaymentModel(
        id: paymentId,
        invoiceId: invoice.id,
        clientId: current.clientId,
        clientName: current.clientName,
        caseId: current.caseId,
        caseNumber: current.caseNumber,
        caseTitle: current.caseTitle,
        attorneyId: current.attorneyId,
        amount: amount,
        method: method,
        status: 'completed',
        referenceNo: referenceNo,
        note: note,
        recordedBy: recordedBy,
        recordedByName: resolvedName,
        recordedByRole: recordedByRole,
        paidAt: when,
        createdAt: when,
      );
      final updatedInvoice = InvoiceModel(
        id: current.id,
        clientId: current.clientId,
        clientName: current.clientName,
        caseId: current.caseId,
        caseNumber: current.caseNumber,
        caseTitle: current.caseTitle,
        attorneyId: current.attorneyId,
        staffId: current.staffId,
        description: current.description,
        totalLegalFee: current.totalLegalFee,
        amountPaid: newPaid,
        status: newStatus,
        createdBy: current.createdBy,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
        dueDate: current.dueDate,
      );

      final paymentRef = _firestore.collection(_payments).doc(paymentId);
      var firestoreOk = false;
      var supabaseOk = !_supabase.isAvailable;
      String? firestoreError;
      String? supabaseError;

      await Future.wait<void>([
        _firestore
            .runTransaction((tx) async {
              tx.set(paymentRef, {
                'invoiceId': invoice.id,
                'clientId': current.clientId,
                if (current.clientName != null) 'clientName': current.clientName,
                if (current.caseId != null) 'caseId': current.caseId,
                if (current.caseNumber != null) 'caseNumber': current.caseNumber,
                if (current.caseTitle != null) 'caseTitle': current.caseTitle,
                'attorneyId': current.attorneyId,
                'amount': amount,
                'method': method,
                'status': 'completed',
                if (referenceNo != null && referenceNo.isNotEmpty)
                  'referenceNo': referenceNo,
                if (note != null && note.isNotEmpty) 'note': note,
                'recordedBy': recordedBy,
                if (resolvedName != null && resolvedName.isNotEmpty)
                  'recordedByName': resolvedName,
                if (recordedByRole != null) 'recordedByRole': recordedByRole,
                'paidAt': Timestamp.fromDate(when),
                'createdAt': FieldValue.serverTimestamp(),
              });
              tx.update(invoiceRef, {
                'amountPaid': newPaid,
                'status': newStatus,
                'updatedAt': FieldValue.serverTimestamp(),
              });
            })
            .then((_) => firestoreOk = true)
            .catchError((Object e) {
              firestoreError = e.toString();
            }),
        if (_supabase.isAvailable)
          Future.wait<String?>([
            _supabase.mirrorPaymentChecked(paymentModel),
            _supabase.mirrorInvoiceChecked(updatedInvoice),
          ]).then((results) {
            if (results.every((r) => r == null)) {
              supabaseOk = true;
            } else {
              supabaseError = results.whereType<String>().join(' | ');
            }
          }),
      ]);

      if (!firestoreOk && !supabaseOk) {
        final parts = <String>[];
        if (firestoreError != null) parts.add('Firestore: $firestoreError');
        if (supabaseError != null) parts.add('Supabase: $supabaseError');
        return BillingResult(
          success: false,
          message: parts.isEmpty ? 'Write failed on both backends.' : parts.join(' | '),
        );
      }

      // Notify the client (best-effort; failure does not roll back the payment).
      await _notifyClientOfPayment(
        invoice: invoice,
        amount: amount,
        method: method,
      );

      return BillingResult(success: true, id: paymentId);
    } catch (e) {
      if (kDebugMode) debugPrint('recordPayment failed: $e');
      return BillingResult(
        success: false,
        message: 'Failed to record payment: $e',
      );
    }
  }

  /// Deletes/voids a recorded payment and reverses its amount on the invoice
  /// (recomputing the status). Used to remove erroneous or legacy receipts.
  Future<BillingResult> deletePayment(PaymentModel payment) async {
    final paymentRef = _firestore.collection(_payments).doc(payment.id);
    try {
      InvoiceModel? updatedInvoice;
      if (payment.invoiceId.isNotEmpty) {
        final invoiceSnap = await _firestore
            .collection(_invoices)
            .doc(payment.invoiceId)
            .get();
        if (invoiceSnap.exists) {
          final inv = InvoiceModel.fromFirestore(invoiceSnap);
          final reduced = inv.amountPaid - payment.amount;
          final newPaid = reduced < 0 ? 0.0 : reduced;
          final newStatus = inv.isCancelled
              ? InvoiceStatus.cancelled
              : InvoiceStatus.fromAmounts(inv.totalLegalFee, newPaid);
          updatedInvoice = InvoiceModel(
            id: inv.id,
            clientId: inv.clientId,
            clientName: inv.clientName,
            caseId: inv.caseId,
            caseNumber: inv.caseNumber,
            caseTitle: inv.caseTitle,
            attorneyId: inv.attorneyId,
            staffId: inv.staffId,
            description: inv.description,
            totalLegalFee: inv.totalLegalFee,
            amountPaid: newPaid,
            status: newStatus,
            createdBy: inv.createdBy,
            createdAt: inv.createdAt,
            updatedAt: DateTime.now(),
            dueDate: inv.dueDate,
          );
        }
      }

      var firestoreOk = false;
      var supabaseOk = !_supabase.isAvailable;
      String? firestoreError;
      String? supabaseError;

      await Future.wait<void>([
        _firestore
            .runTransaction((tx) async {
              InvoiceModel? inv;
              DocumentReference<Map<String, dynamic>>? invoiceRef;
              if (payment.invoiceId.isNotEmpty) {
                invoiceRef =
                    _firestore.collection(_invoices).doc(payment.invoiceId);
                final invoiceSnap = await tx.get(invoiceRef);
                if (invoiceSnap.exists) {
                  inv = InvoiceModel.fromFirestore(invoiceSnap);
                }
              }

              tx.delete(paymentRef);

              if (inv != null && invoiceRef != null) {
                final reduced = inv.amountPaid - payment.amount;
                final newPaid = reduced < 0 ? 0.0 : reduced;
                final newStatus = inv.isCancelled
                    ? InvoiceStatus.cancelled
                    : InvoiceStatus.fromAmounts(inv.totalLegalFee, newPaid);
                tx.update(invoiceRef, {
                  'amountPaid': newPaid,
                  'status': newStatus,
                  'updatedAt': FieldValue.serverTimestamp(),
                });
              }
            })
            .then((_) => firestoreOk = true)
            .catchError((Object e) {
              firestoreError = e.toString();
            }),
        if (_supabase.isAvailable)
          Future.wait<String?>([
            _supabase.deletePaymentChecked(payment.id),
            if (updatedInvoice != null)
              _supabase.mirrorInvoiceChecked(updatedInvoice)
            else
              Future<String?>.value(null),
          ]).then((results) {
            if (results.every((r) => r == null)) {
              supabaseOk = true;
            } else {
              supabaseError = results.whereType<String>().join(' | ');
            }
          }),
      ]);

      if (!firestoreOk && !supabaseOk) {
        final parts = <String>[];
        if (firestoreError != null) parts.add('Firestore: $firestoreError');
        if (supabaseError != null) parts.add('Supabase: $supabaseError');
        return BillingResult(
          success: false,
          message: parts.isEmpty ? 'Write failed on both backends.' : parts.join(' | '),
        );
      }
      return const BillingResult(success: true);
    } catch (e) {
      if (kDebugMode) debugPrint('deletePayment failed: $e');
      return BillingResult(
        success: false,
        message: 'Failed to delete payment: $e',
      );
    }
  }

  /// Deletes an invoice and all of its payment receipts. Used to remove an
  /// erroneous or legacy billing record entirely (its fees and payments drop
  /// out of every total).
  Future<BillingResult> deleteInvoice(InvoiceModel invoice) async {
    try {
      final payments = await _firestore
          .collection(_payments)
          .where('invoiceId', isEqualTo: invoice.id)
          .get();

      final paymentIds = payments.docs.map((d) => d.id).toList();
      var firestoreOk = false;
      var supabaseOk = !_supabase.isAvailable;
      String? firestoreError;
      String? supabaseError;

      final batch = _firestore.batch();
      for (final doc in payments.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(_firestore.collection(_invoices).doc(invoice.id));

      await Future.wait<void>([
        batch
            .commit()
            .then((_) => firestoreOk = true)
            .catchError((Object e) {
              firestoreError = e.toString();
            }),
        if (_supabase.isAvailable)
          Future.wait<String?>([
            ...paymentIds.map((id) => _supabase.deletePaymentChecked(id)),
            _supabase.deleteInvoiceChecked(invoice.id),
          ]).then((results) {
            if (results.every((r) => r == null)) {
              supabaseOk = true;
            } else {
              supabaseError = results.whereType<String>().join(' | ');
            }
          }),
      ]);

      if (!firestoreOk && !supabaseOk) {
        final parts = <String>[];
        if (firestoreError != null) parts.add('Firestore: $firestoreError');
        if (supabaseError != null) parts.add('Supabase: $supabaseError');
        return BillingResult(
          success: false,
          message: parts.isEmpty ? 'Write failed on both backends.' : parts.join(' | '),
        );
      }
      return const BillingResult(success: true);
    } catch (e) {
      if (kDebugMode) debugPrint('deleteInvoice failed: $e');
      return BillingResult(
        success: false,
        message: 'Failed to delete invoice: $e',
      );
    }
  }

  Future<String?> _lookupUserName(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final data = doc.data();
      return (data?['fullName'] ?? data?['name'] ?? data?['displayName'])
          as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _notifyClientOfPayment({
    required InvoiceModel invoice,
    required double amount,
    required String method,
  }) async {
    try {
      final caseLabel = (invoice.caseTitle?.isNotEmpty == true)
          ? ' for ${invoice.caseTitle}'
          : '';
      final notifData = <String, dynamic>{
        'userId': invoice.clientId,
        'type': 'payment_recorded',
        'title': 'Payment Recorded',
        'message':
            'A payment of \u20B1${amount.toStringAsFixed(2)}$caseLabel was '
            'recorded by the law office. Please check your updated balance.',
        'data': {
          'invoiceId': invoice.id,
          if (invoice.caseId != null) 'caseId': invoice.caseId,
          'amount': amount,
        },
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
      await FirestoreMirror.add(collection: 'notifications', data: notifData);
    } catch (e) {
      if (kDebugMode) debugPrint('payment notification failed: $e');
    }
  }
}
