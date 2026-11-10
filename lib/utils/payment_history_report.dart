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
  final String preparedByTitle;
  final String reportDate;
  final String periodNote;

  const PaymentReportMeta({
    required this.firmName,
    required this.firmAddress,
    required this.firmPhone,
    required this.firmEmail,
    required this.preparedBy,
    this.preparedByTitle = 'Attorney at Law',
    required this.reportDate,
    this.periodNote =
        'NOTE: This report shows all clients and their payment status '
        'as of the report date.',
  });

  PaymentReportMeta copyWith({
    String? preparedBy,
    String? preparedByTitle,
    String? reportDate,
    String? periodNote,
  }) {
    return PaymentReportMeta(
      firmName: firmName,
      firmAddress: firmAddress,
      firmPhone: firmPhone,
      firmEmail: firmEmail,
      preparedBy: preparedBy ?? this.preparedBy,
      preparedByTitle: preparedByTitle ?? this.preparedByTitle,
      reportDate: reportDate ?? this.reportDate,
      periodNote: periodNote ?? this.periodNote,
    );
  }
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
  if (invoice.amountPaid >= invoice.totalLegalFee - 0.001 &&
      invoice.totalLegalFee > 0) {
    return 'PAID';
  }
  if (invoice.amountPaid > 0) return 'PARTIAL';
  return 'UNPAID';
}

/// Active invoices stay on the report. Archived invoices stay if they have
/// payment receipts so history is never wiped by the billing trash icon.
bool includeInvoiceInPaymentHistory(
  InvoiceModel invoice,
  Iterable<PaymentModel> payments,
) {
  if (!invoice.isCancelled) return true;
  return payments.any((p) => p.invoiceId == invoice.id);
}

/// Inclusive month range for Payment History. Null fields mean "all time".
class PaymentHistoryPeriod {
  final int? fromYear;
  final int? fromMonth;
  final int? toYear;
  final int? toMonth;

  const PaymentHistoryPeriod({
    this.fromYear,
    this.fromMonth,
    this.toYear,
    this.toMonth,
  });

  const PaymentHistoryPeriod.all()
      : fromYear = null,
        fromMonth = null,
        toYear = null,
        toMonth = null;

  factory PaymentHistoryPeriod.thisMonth(DateTime now) =>
      PaymentHistoryPeriod.lastMonths(now, 1);

  factory PaymentHistoryPeriod.lastMonths(DateTime now, int count) {
    final to = DateTime(now.year, now.month);
    final from = DateTime(to.year, to.month - (count - 1));
    return PaymentHistoryPeriod(
      fromYear: from.year,
      fromMonth: from.month,
      toYear: to.year,
      toMonth: to.month,
    );
  }

  bool get isAll =>
      fromYear == null &&
      fromMonth == null &&
      toYear == null &&
      toMonth == null;

  DateTime? get _start {
    final year = fromYear ?? toYear;
    if (year == null) return null;
    return DateTime(year, fromMonth ?? 1);
  }

  DateTime? get _end {
    final year = toYear ?? fromYear;
    if (year == null) return null;
    return DateTime(year, toMonth ?? 12);
  }

  bool contains(DateTime paidAt) {
    if (isAll) return true;
    final key = paidAt.year * 12 + paidAt.month;
    final start = _start;
    final end = _end;
    if (start != null && key < start.year * 12 + start.month) return false;
    if (end != null && key > end.year * 12 + end.month) return false;
    return true;
  }

  String get fileSlug {
    if (isAll) return 'all';
    final start = _start ?? DateTime(_end!.year, _end!.month);
    final end = _end ?? start;
    final a = DateFormat('yyyyMM').format(start);
    final b = DateFormat('yyyyMM').format(end);
    return a == b ? a : '$a-$b';
  }
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

/// Label for the person who opened the report. Staff keeps their own name.
String paymentHistoryPreparedBy({
  required String recorderRole,
  String? recorderName,
  required String attorneyDisplayName,
}) {
  if (recorderRole == 'staff') {
    final name = (recorderName ?? '').trim();
    return name.isNotEmpty ? name : 'Staff';
  }
  final raw = attorneyDisplayName.trim().isNotEmpty
      ? attorneyDisplayName.trim()
      : 'Attorney';
  return raw.toLowerCase().startsWith('atty.') ? raw : 'Atty. $raw';
}

String paymentHistoryPreparedByTitle(String recorderRole) {
  return recorderRole == 'staff' ? 'Staff' : 'Attorney at Law';
}

String paymentHistoryContactPhone(Map<String, dynamic>? data) {
  return (data?['phone'] ?? data?['phoneNumber'] ?? '').toString().trim();
}

String paymentHistoryContactEmail(Map<String, dynamic>? data) {
  return (data?['email'] ?? '').toString().trim();
}

/// Firm letterhead stays the attorney office. Phone/email follow the preparer.
({String phone, String email}) paymentHistoryHeaderContact({
  required String recorderRole,
  Map<String, dynamic>? attorneyData,
  Map<String, dynamic>? recorderData,
}) {
  final source = recorderRole == 'staff' && recorderData != null
      ? recorderData
      : attorneyData;
  return (
    phone: paymentHistoryContactPhone(source),
    email: paymentHistoryContactEmail(source),
  );
}

bool paymentMatchesPeriod(
  DateTime paidAt, {
  int? year,
  int? month,
  PaymentHistoryPeriod? period,
}) {
  final resolved = period ??
      PaymentHistoryPeriod(
        fromYear: year,
        fromMonth: month,
        toYear: year,
        toMonth: month,
      );
  return resolved.contains(paidAt);
}

String paymentHistoryPeriodNote(PaymentHistoryPeriod period) {
  if (period.isAll) {
    return 'NOTE: This report shows all clients and their payment status '
        'as of the report date.';
  }
  final start = period._start;
  final end = period._end;
  if (start == null || end == null) {
    return 'NOTE: This report shows all clients and their payment status '
        'as of the report date.';
  }
  if (start.year == end.year && start.month == end.month) {
    final label = DateFormat('MMMM yyyy').format(start);
    return 'NOTE: This report shows clients with payments in $label.';
  }
  return 'NOTE: This report shows clients with payments from '
      '${DateFormat('MMMM yyyy').format(start)} to '
      '${DateFormat('MMMM yyyy').format(end)}.';
}

List<int> paymentHistoryFilterYears(
  List<PaymentModel> payments, {
  DateTime? now,
}) {
  final current = (now ?? DateTime.now()).year;
  final years = <int>{
    for (var year = current - 3; year <= current + 1; year++) year,
  };
  for (final payment in payments) {
    years.add(payment.paidAt.year);
  }
  return years.toList()..sort((a, b) => b.compareTo(a));
}

/// Builds the firm-wide payment history report from invoices + payments.
Future<PaymentHistoryReport> buildPaymentHistoryReport({
  required List<InvoiceModel> invoices,
  required List<PaymentModel> payments,
  required String attorneyId,
  String recorderRole = 'attorney',
  String? recorderName,
  String? recorderId,
}) async {
  final firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? attorneyData;
  try {
    final doc = await firestore.collection('users').doc(attorneyId).get();
    attorneyData = doc.data();
  } catch (_) {}

  Map<String, dynamic>? recorderData;
  if (recorderRole == 'staff') {
    final staffId = (recorderId ?? '').trim();
    if (staffId.isNotEmpty && staffId != attorneyId) {
      try {
        final doc = await firestore.collection('users').doc(staffId).get();
        recorderData = doc.data();
      } catch (_) {}
    }
  }

  final rawName = attorneyData != null
      ? UserModel.resolveDisplayName(attorneyData)
      : 'Attorney';
  final staffName = recorderData != null
      ? UserModel.resolveDisplayName(recorderData)
      : '';
  final preparedBy = paymentHistoryPreparedBy(
    recorderRole: recorderRole,
    recorderName: (recorderName ?? '').trim().isNotEmpty
        ? recorderName
        : (staffName.isNotEmpty ? staffName : recorderName),
    attorneyDisplayName: rawName,
  );
  final firmName = (attorneyData?['firmName'] ??
          attorneyData?['officeName'] ??
          'Law Connect Law Firm')
      .toString();
  final firmAddress =
      (attorneyData?['address'] ?? 'Legal Services Office').toString();
  final contact = paymentHistoryHeaderContact(
    recorderRole: recorderRole,
    attorneyData: attorneyData,
    recorderData: recorderData,
  );
  final firmPhone = contact.phone;
  final firmEmail = contact.email;

  final paymentsByInvoice = <String, List<PaymentModel>>{};
  for (final p in payments) {
    if (p.invoiceId.isEmpty) continue;
    paymentsByInvoice.putIfAbsent(p.invoiceId, () => []).add(p);
  }

  final listed = invoices
      .where((i) => includeInvoiceInPaymentHistory(i, payments))
      .toList()
    ..sort((a, b) => (a.clientName ?? '').compareTo(b.clientName ?? ''));

  final rows = <PaymentReportRow>[];
  for (final invoice in listed) {
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
      preparedByTitle: paymentHistoryPreparedByTitle(recorderRole),
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

/// Cases that received at least one payment in the selected month range.
List<PaymentReportRow> filterReportRowsByPaidPeriod(
  List<PaymentReportRow> rows,
  List<PaymentModel> payments, {
  int? year,
  int? month,
  PaymentHistoryPeriod? period,
}) {
  final resolved = period ??
      PaymentHistoryPeriod(
        fromYear: year,
        fromMonth: month,
        toYear: year,
        toMonth: month,
      );
  if (resolved.isAll) return rows;
  final invoiceIds = <String>{
    for (final payment in payments)
      if (payment.invoiceId.isNotEmpty && resolved.contains(payment.paidAt))
        payment.invoiceId,
  };
  return rows.where((row) => invoiceIds.contains(row.invoice.id)).toList();
}
