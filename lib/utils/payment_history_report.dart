import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/invoice_model.dart';
import '../models/payment_model.dart';
import '../models/user_model.dart';

/// One row in the firm-wide Payment History Report table.
class PaymentReportRow {
  final String clientName;
  final String caseNumber;
  final double totalFee;
  final double totalPaid;
  final double remainingBalance;
  final String statusLabel; // PAID | PARTIAL | UNPAID
  final DateTime? lastPaymentDate;
  final String? lastRecordedBy;
  final InvoiceModel invoice;

  const PaymentReportRow({
    required this.clientName,
    required this.caseNumber,
    required this.totalFee,
    required this.totalPaid,
    required this.remainingBalance,
    required this.statusLabel,
    this.lastPaymentDate,
    this.lastRecordedBy,
    required this.invoice,
  });
}

class PaymentReportSummary {
  final int unpaidCount;
  final double unpaidAmount;
  final int partialCount;
  final double partialAmount;
  final int paidCount;
  final double paidAmount;

  const PaymentReportSummary({
    required this.unpaidCount,
    required this.unpaidAmount,
    required this.partialCount,
    required this.partialAmount,
    required this.paidCount,
    required this.paidAmount,
  });
}

/// Header metadata for the Payment History Report.
class PaymentReportMeta {
  final String firmName;
  final String firmAddress;
  final String firmPhone;
  final String firmEmail;
  final String preparedBy;
  final String reportDate;

  const PaymentReportMeta({
    required this.firmName,
    required this.firmAddress,
    required this.firmPhone,
    required this.firmEmail,
    required this.preparedBy,
    required this.reportDate,
  });
}

class PaymentHistoryReport {
  final PaymentReportMeta meta;
  final List<PaymentReportRow> rows;
  final PaymentReportSummary summary;

  const PaymentHistoryReport({
    required this.meta,
    required this.rows,
    required this.summary,
  });
}

String paymentStatusCode(InvoiceModel invoice) {
  if (invoice.isCancelled) return 'CANCELLED';
  if (invoice.isPaid) return 'PAID';
  if (invoice.isPartiallyPaid) return 'PARTIAL';
  return 'UNPAID';
}

PaymentReportSummary buildPaymentReportSummary(List<PaymentReportRow> rows) {
  var unpaidCount = 0;
  var unpaidAmount = 0.0;
  var partialCount = 0;
  var partialAmount = 0.0;
  var paidCount = 0;
  var paidAmount = 0.0;

  for (final row in rows) {
    switch (row.statusLabel) {
      case 'PAID':
        paidCount++;
        paidAmount += row.totalPaid;
        break;
      case 'PARTIAL':
        partialCount++;
        partialAmount += row.remainingBalance;
        break;
      case 'UNPAID':
        unpaidCount++;
        unpaidAmount += row.remainingBalance;
        break;
    }
  }

  return PaymentReportSummary(
    unpaidCount: unpaidCount,
    unpaidAmount: unpaidAmount,
    partialCount: partialCount,
    partialAmount: partialAmount,
    paidCount: paidCount,
    paidAmount: paidAmount,
  );
}

/// Builds the firm-wide payment history report from invoices + payments.
Future<PaymentHistoryReport> buildPaymentHistoryReport({
  required List<InvoiceModel> invoices,
  required List<PaymentModel> payments,
  required String attorneyId,
}) async {
  final firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? attorneyData;
  try {
    final doc = await firestore.collection('users').doc(attorneyId).get();
    attorneyData = doc.data();
  } catch (_) {}

  final rawName = attorneyData != null
      ? UserModel.resolveDisplayName(attorneyData)
      : 'Attorney';
  final preparedBy = rawName.toLowerCase().startsWith('atty.')
      ? rawName
      : 'Atty. $rawName';
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

  final paymentsByInvoice = <String, List<PaymentModel>>{};
  for (final p in payments) {
    if (p.invoiceId.isEmpty) continue;
    paymentsByInvoice.putIfAbsent(p.invoiceId, () => []).add(p);
  }

  final active = invoices.where((i) => !i.isCancelled).toList()
    ..sort((a, b) => (a.clientName ?? '').compareTo(b.clientName ?? ''));

  final rows = <PaymentReportRow>[];
  for (final invoice in active) {
    final invoicePayments = paymentsByInvoice[invoice.id] ?? [];
    PaymentModel? lastPayment;
    if (invoicePayments.isNotEmpty) {
      invoicePayments.sort((a, b) => b.paidAt.compareTo(a.paidAt));
      lastPayment = invoicePayments.first;
    }

    rows.add(
      PaymentReportRow(
        clientName: invoice.clientName ?? '—',
        caseNumber: invoice.displayCaseNumber,
        totalFee: invoice.totalLegalFee,
        totalPaid: invoice.amountPaid,
        remainingBalance: invoice.remainingBalance,
        statusLabel: paymentStatusCode(invoice),
        lastPaymentDate: lastPayment?.paidAt,
        lastRecordedBy: lastPayment?.recordedByLabel,
        invoice: invoice,
      ),
    );
  }

  return PaymentHistoryReport(
    meta: PaymentReportMeta(
      firmName: firmName,
      firmAddress: firmAddress,
      firmPhone: firmPhone,
      firmEmail: firmEmail,
      preparedBy: preparedBy,
      reportDate: DateFormat('MMMM dd, yyyy').format(DateTime.now()),
    ),
    rows: rows,
    summary: buildPaymentReportSummary(rows),
  );
}

List<PaymentReportRow> filterReportRows(
  List<PaymentReportRow> rows,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return rows;
  return rows.where((r) {
    return r.clientName.toLowerCase().contains(q) ||
        r.caseNumber.toLowerCase().contains(q) ||
        r.statusLabel.toLowerCase().contains(q) ||
        (r.lastRecordedBy ?? '').toLowerCase().contains(q);
  }).toList();
}
