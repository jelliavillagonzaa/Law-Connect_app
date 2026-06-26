import 'package:cloud_firestore/cloud_firestore.dart';

/// Payment status of an invoice (lowercase + underscores, matching cases).
class InvoiceStatus {
  static const String unpaid = 'unpaid';
  static const String partiallyPaid = 'partially_paid';
  static const String paid = 'paid';
  static const String cancelled = 'cancelled';

  /// Derive the status from amounts (used whenever a payment is recorded).
  static String fromAmounts(double totalLegalFee, double amountPaid) {
    if (amountPaid <= 0) return unpaid;
    if (amountPaid >= totalLegalFee - 0.001) return paid;
    return partiallyPaid;
  }
}

/// A legal-fee billing record raised against a client's case.
///
/// `totalLegalFee` is the agreed fee. `amountPaid` is the running total of
/// payments physically received and recorded by the attorney/staff at the
/// office. `remainingBalance` is derived (`totalLegalFee - amountPaid`).
class InvoiceModel {
  final String id;
  final String clientId;
  final String? clientName;
  final String? caseId;
  final String? caseNumber;
  final String? caseTitle;
  final String attorneyId;
  final String? staffId;
  final String? description;
  final double totalLegalFee;
  final double amountPaid;
  final String status; // see InvoiceStatus
  final String? createdBy; // uid of attorney/staff/admin who issued it
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? dueDate;

  InvoiceModel({
    required this.id,
    required this.clientId,
    this.clientName,
    this.caseId,
    this.caseNumber,
    this.caseTitle,
    required this.attorneyId,
    this.staffId,
    this.description,
    required this.totalLegalFee,
    this.amountPaid = 0,
    this.status = InvoiceStatus.unpaid,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.dueDate,
  });

  /// Remaining balance, never negative.
  double get remainingBalance {
    final remaining = totalLegalFee - amountPaid;
    return remaining < 0 ? 0 : remaining;
  }

  bool get isPaid => status == InvoiceStatus.paid || remainingBalance <= 0;
  bool get isPartiallyPaid =>
      !isPaid && amountPaid > 0 && status != InvoiceStatus.cancelled;
  bool get isCancelled => status == InvoiceStatus.cancelled;

  /// True when there is still money owed and the invoice is active.
  bool get hasOutstanding => !isCancelled && remainingBalance > 0;

  /// Best-effort case number for display: the stored caseNumber, otherwise a
  /// short uppercase form of the case document id.
  String get displayCaseNumber {
    if (caseNumber != null && caseNumber!.isNotEmpty) return caseNumber!;
    if (caseId != null && caseId!.isNotEmpty) {
      final id = caseId!;
      return 'CASE-${id.substring(0, id.length < 6 ? id.length : 6).toUpperCase()}';
    }
    return '—';
  }

  /// Human-readable status: Unpaid / Partially Paid / Fully Paid / Cancelled.
  String get statusLabel {
    if (isCancelled) return 'Cancelled';
    if (isPaid) return 'Fully Paid';
    if (amountPaid > 0) return 'Partially Paid';
    return 'Unpaid';
  }

  factory InvoiceModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return InvoiceModel(
      id: doc.id,
      clientId: data['clientId'] ?? '',
      clientName: data['clientName'],
      caseId: data['caseId'],
      caseNumber: data['caseNumber'],
      caseTitle: data['caseTitle'],
      attorneyId: data['attorneyId'] ?? '',
      staffId: data['staffId'],
      description: data['description'],
      totalLegalFee: (data['totalLegalFee'] as num?)?.toDouble() ?? 0,
      amountPaid: (data['amountPaid'] as num?)?.toDouble() ?? 0,
      status: data['status'] ?? InvoiceStatus.unpaid,
      createdBy: data['createdBy'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      dueDate: (data['dueDate'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'clientId': clientId,
      if (clientName != null) 'clientName': clientName,
      if (caseId != null) 'caseId': caseId,
      if (caseNumber != null) 'caseNumber': caseNumber,
      if (caseTitle != null) 'caseTitle': caseTitle,
      'attorneyId': attorneyId,
      if (staffId != null) 'staffId': staffId,
      if (description != null) 'description': description,
      'totalLegalFee': totalLegalFee,
      'amountPaid': amountPaid,
      'status': status,
      if (createdBy != null) 'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      if (dueDate != null) 'dueDate': Timestamp.fromDate(dueDate!),
    };
  }
}
