import 'package:cloud_firestore/cloud_firestore.dart';

/// How a payment was tendered at the office.
class PaymentMethod {
  static const String cash = 'cash';
  static const String check = 'check';
  static const String bankTransfer = 'bank_transfer';
  static const String gcash = 'gcash';
  static const String other = 'other';

  /// Methods offered when recording a payment manually, in display order.
  static const List<String> all = [cash, check, bankTransfer, gcash];

  static String label(String method) {
    switch (method) {
      case cash:
        return 'Cash';
      case check:
        return 'Check';
      case bankTransfer:
        return 'Bank Transfer';
      case gcash:
        return 'GCash';
      case other:
        return 'Other';
      default:
        return method;
    }
  }
}

/// A single payment receipt recorded by the office (attorney or staff) for a
/// payment physically received from the client.
class PaymentModel {
  final String id;
  final String invoiceId;
  final String clientId;
  final String? clientName;
  final String? caseId;
  final String? caseNumber;
  final String? caseTitle;
  final String attorneyId;
  final double amount;
  final String method; // see PaymentMethod
  final String status; // 'completed' (settled) — receipts are recorded as paid
  final String? referenceNo; // OR / receipt / reference number
  final String? note;
  final String? recordedBy; // uid of the attorney/staff who recorded it
  final String? recordedByName;
  final String? recordedByRole; // 'attorney' | 'staff' | 'admin'
  final DateTime paidAt; // when the payment was received
  final DateTime createdAt;

  PaymentModel({
    required this.id,
    required this.invoiceId,
    required this.clientId,
    this.clientName,
    this.caseId,
    this.caseNumber,
    this.caseTitle,
    required this.attorneyId,
    required this.amount,
    this.method = PaymentMethod.cash,
    this.status = 'completed',
    this.referenceNo,
    this.note,
    this.recordedBy,
    this.recordedByName,
    this.recordedByRole,
    required this.paidAt,
    required this.createdAt,
  });

  String get methodLabel => PaymentMethod.label(method);

  /// True for settled payments (recorded receipts are `completed`/`paid`).
  bool get isSuccessful => status == 'completed' || status == 'paid';

  /// Short payment id for receipts: `PAY-AB12CD`.
  String get displayPaymentId => id.isEmpty
      ? '—'
      : 'PAY-${id.substring(0, id.length < 6 ? id.length : 6).toUpperCase()}';

  /// Best-effort case number for display.
  String get displayCaseNumber {
    if (caseNumber != null && caseNumber!.isNotEmpty) return caseNumber!;
    if (caseId != null && caseId!.isNotEmpty) {
      final cid = caseId!;
      return 'CASE-${cid.substring(0, cid.length < 6 ? cid.length : 6).toUpperCase()}';
    }
    return '—';
  }

  /// "Maria Santos (Staff)" — who recorded this payment, for the audit trail.
  String get recordedByLabel {
    final name =
        (recordedByName?.isNotEmpty == true) ? recordedByName! : 'Unknown';
    final role = (recordedByRole?.isNotEmpty == true)
        ? recordedByRole![0].toUpperCase() + recordedByRole!.substring(1)
        : '';
    return role.isEmpty ? name : '$name ($role)';
  }

  factory PaymentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PaymentModel(
      id: doc.id,
      invoiceId: data['invoiceId'] ?? '',
      clientId: data['clientId'] ?? '',
      clientName: data['clientName'],
      caseId: data['caseId'],
      caseNumber: data['caseNumber'],
      caseTitle: data['caseTitle'],
      attorneyId: data['attorneyId'] ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      method: data['method'] ?? PaymentMethod.cash,
      status: data['status'] ?? 'completed',
      referenceNo: data['referenceNo'] ?? data['reference'],
      note: data['note'],
      recordedBy: data['recordedBy'],
      recordedByName: data['recordedByName'],
      recordedByRole: data['recordedByRole'],
      paidAt: (data['paidAt'] as Timestamp?)?.toDate() ??
          (data['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'invoiceId': invoiceId,
      'clientId': clientId,
      if (clientName != null) 'clientName': clientName,
      if (caseId != null) 'caseId': caseId,
      if (caseNumber != null) 'caseNumber': caseNumber,
      if (caseTitle != null) 'caseTitle': caseTitle,
      'attorneyId': attorneyId,
      'amount': amount,
      'method': method,
      'status': status,
      if (referenceNo != null) 'referenceNo': referenceNo,
      if (note != null) 'note': note,
      if (recordedBy != null) 'recordedBy': recordedBy,
      if (recordedByName != null) 'recordedByName': recordedByName,
      if (recordedByRole != null) 'recordedByRole': recordedByRole,
      'paidAt': Timestamp.fromDate(paidAt),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
