import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/invoice_model.dart';
import '../models/payment_model.dart';
import '../models/user_model.dart';
import '../utils/payment_history_statement_pdf.dart';

/// Builds [PaymentStatementData] rows grouped by invoice for statements.
Future<List<PaymentStatementData>> buildPaymentStatements({
  required List<PaymentModel> payments,
  required List<InvoiceModel> invoices,
  required String attorneyId,
}) async {
  if (payments.isEmpty) return [];

  final firestore = FirebaseFirestore.instance;
  final invoiceById = {for (final i in invoices) i.id: i};

  Map<String, dynamic>? attorneyData;
  try {
    final attorneyDoc =
        await firestore.collection('users').doc(attorneyId).get();
    attorneyData = attorneyDoc.data();
  } catch (_) {}

  final attorneyName = attorneyData != null
      ? 'Atty. ${UserModel.resolveDisplayName(attorneyData)}'
      : 'Attorney';
  final firmName = (attorneyData?['firmName'] ??
          attorneyData?['officeName'] ??
          'Law Connect Law Firm')
      .toString();
  final firmAddress =
      (attorneyData?['address'] ?? 'Legal Services Office').toString();
  final firmPhone =
      (attorneyData?['phone'] ?? attorneyData?['phoneNumber'] ?? '')
          .toString();
  final firmEmail = (attorneyData?['email'] ?? '').toString();

  final clientCache = <String, Map<String, dynamic>>{};
  Future<Map<String, dynamic>?> clientData(String clientId) async {
    if (clientId.isEmpty) return null;
    if (clientCache.containsKey(clientId)) return clientCache[clientId];
    try {
      final doc = await firestore.collection('users').doc(clientId).get();
      final data = doc.data();
      if (data != null) clientCache[clientId] = data;
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<InvoiceModel> resolveInvoice(
    String invoiceId,
    List<PaymentModel> group,
  ) async {
    if (invoiceId.isNotEmpty && invoiceById.containsKey(invoiceId)) {
      return invoiceById[invoiceId]!;
    }

    if (invoiceId.isNotEmpty) {
      try {
        final doc = await firestore.collection('invoices').doc(invoiceId).get();
        if (doc.exists) {
          final loaded = InvoiceModel.fromFirestore(doc);
          invoiceById[invoiceId] = loaded;
          return loaded;
        }
      } catch (_) {}
    }

    return _invoiceFromPayments(invoiceId, group);
  }

  final byInvoice = <String, List<PaymentModel>>{};
  for (final p in payments) {
    final key = p.invoiceId.isNotEmpty ? p.invoiceId : '_orphan_${p.id}';
    byInvoice.putIfAbsent(key, () => []).add(p);
  }

  final statements = <PaymentStatementData>[];
  for (final entry in byInvoice.entries) {
    final group = entry.value..sort((a, b) => b.paidAt.compareTo(a.paidAt));
    final first = group.first;
    final invoice = await resolveInvoice(entry.key, group);

    final clientId = invoice.clientId.isNotEmpty ? invoice.clientId : first.clientId;
    final cdata = await clientData(clientId);
    final clientName = invoice.clientName ??
        first.clientName ??
        (cdata != null ? UserModel.resolveDisplayName(cdata) : 'Client');

    statements.add(
      PaymentStatementData(
        firmName: firmName,
        firmAddress: firmAddress,
        firmPhone: firmPhone,
        firmEmail: firmEmail,
        clientName: clientName,
        clientId: clientId.isEmpty
            ? '—'
            : 'CL-${clientId.substring(0, clientId.length < 6 ? clientId.length : 6).toUpperCase()}',
        clientPhone:
            (cdata?['phone'] ?? cdata?['phoneNumber'] ?? '').toString(),
        clientEmail: (cdata?['email'] ?? '').toString(),
        caseNumber: invoice.displayCaseNumber != '—'
            ? invoice.displayCaseNumber
            : first.displayCaseNumber,
        caseTitle: invoice.caseTitle ?? first.caseTitle ?? 'Legal Case',
        practiceArea: invoice.description ?? 'Legal Services',
        attorneyName: attorneyName,
        invoice: invoice,
        payments: group,
      ),
    );
  }

  statements.sort((a, b) => b.invoice.updatedAt.compareTo(a.invoice.updatedAt));
  return statements;
}

/// Reconstructs invoice totals from payment receipts when the invoice doc
/// is missing from the passed list (e.g. after hot reload).
InvoiceModel _invoiceFromPayments(String invoiceId, List<PaymentModel> group) {
  final first = group.first;
  final totalPaid = group.fold<double>(0, (total, p) => total + p.amount);
  final latest = group.map((p) => p.paidAt).reduce((a, b) => a.isAfter(b) ? a : b);
  final id = invoiceId.startsWith('_orphan_') ? first.id : invoiceId;

  return InvoiceModel(
    id: id,
    clientId: first.clientId,
    clientName: first.clientName,
    caseId: first.caseId,
    caseNumber: first.caseNumber,
    caseTitle: first.caseTitle,
    attorneyId: first.attorneyId,
    totalLegalFee: totalPaid,
    amountPaid: totalPaid,
    status: InvoiceStatus.paid,
    createdAt: latest,
    updatedAt: latest,
  );
}
