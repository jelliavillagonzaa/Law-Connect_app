import 'package:cloud_firestore/cloud_firestore.dart';

class AppointmentModel {
  final String id;
  final String clientId;
  final String clientName;
  final String? attorneyId;
  final String? attorneyName;
  final String? caseId;
  final String? caseTitle;
  final DateTime appointmentDateTime;
  final String appointmentType; // 'in_office', 'phone_call', 'online_meeting'
  final String? notes;
  final String status; // 'pending', 'confirmed', 'completed', 'cancelled', etc.
  final DateTime createdAt;
  final DateTime updatedAt;

  // Optional linkage fields to support the request_appointment ↔ appointment flow
  final String? requestId; // For confirmed appointments: back-link to request
  final String?
  linkedAppointmentId; // For requests: ID of confirmed appointment
  final String? declineReason;

  AppointmentModel({
    required this.id,
    required this.clientId,
    required this.clientName,
    this.attorneyId,
    this.attorneyName,
    this.caseId,
    this.caseTitle,
    required this.appointmentDateTime,
    required this.appointmentType,
    this.notes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.requestId,
    this.linkedAppointmentId,
    this.declineReason,
  });

  factory AppointmentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Parse date and time
    DateTime appointmentDateTime;
    if (data['appointmentDateTime'] != null) {
      appointmentDateTime = (data['appointmentDateTime'] as Timestamp).toDate();
    } else if (data['appointmentDate'] != null &&
        data['appointmentTime'] != null) {
      // Fallback to old format - some legacy records may store times like "5:0am"
      // Wrap parsing in try/catch so a bad legacy value doesn't crash the UI.
      try {
        final dateStr = data['appointmentDate'] as String;
        final timeStr = (data['appointmentTime'] as String)
            .toLowerCase()
            .trim();

        // Expect date as "yyyy-MM-dd"
        final dateParts = dateStr.split('-');

        // Strip non‑digits from hour/minute portions (handles "0am", "30pm", etc.)
        final rawTimeParts = timeStr.split(':');
        String hourStr = rawTimeParts[0].replaceAll(RegExp(r'[^0-9]'), '');
        String minuteStr = rawTimeParts.length > 1
            ? rawTimeParts[1].replaceAll(RegExp(r'[^0-9]'), '')
            : '0';

        if (hourStr.isEmpty) hourStr = '0';
        if (minuteStr.isEmpty) minuteStr = '0';

        appointmentDateTime = DateTime(
          int.parse(dateParts[0]),
          int.parse(dateParts[1]),
          int.parse(dateParts[2]),
          int.parse(hourStr),
          int.parse(minuteStr),
        );
      } catch (_) {
        // On any parse error, fall back to "now" rather than throwing.
        appointmentDateTime = DateTime.now();
      }
    } else {
      appointmentDateTime = DateTime.now();
    }

    return AppointmentModel(
      id: doc.id,
      clientId: data['clientId'] ?? '',
      clientName: data['clientName'] ?? '',
      attorneyId: data['attorneyId'],
      attorneyName: data['attorneyName'],
      caseId: data['caseId'],
      caseTitle: data['caseTitle'],
      appointmentDateTime: appointmentDateTime,
      appointmentType: data['appointmentType'] ?? 'in_office',
      notes: data['notes'],
      status: data['status'] ?? 'upcoming',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      requestId: data['requestId'],
      linkedAppointmentId: data['linkedAppointmentId'],
      declineReason: data['declineReason'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'clientId': clientId,
      'clientName': clientName,
      if (attorneyId != null) 'attorneyId': attorneyId,
      if (attorneyName != null) 'attorneyName': attorneyName,
      if (caseId != null) 'caseId': caseId,
      if (caseTitle != null) 'caseTitle': caseTitle,
      'appointmentDateTime': Timestamp.fromDate(appointmentDateTime),
      'appointmentType': appointmentType,
      if (notes != null) 'notes': notes,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      if (requestId != null) 'requestId': requestId,
      if (linkedAppointmentId != null)
        'linkedAppointmentId': linkedAppointmentId,
      if (declineReason != null && declineReason!.trim().isNotEmpty)
        'declineReason': declineReason,
    };
  }

  AppointmentModel copyWith({
    String? id,
    String? clientId,
    String? clientName,
    String? attorneyId,
    String? attorneyName,
    String? caseId,
    String? caseTitle,
    DateTime? appointmentDateTime,
    String? appointmentType,
    String? notes,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? requestId,
    String? linkedAppointmentId,
    String? declineReason,
  }) {
    return AppointmentModel(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      clientName: clientName ?? this.clientName,
      attorneyId: attorneyId ?? this.attorneyId,
      attorneyName: attorneyName ?? this.attorneyName,
      caseId: caseId ?? this.caseId,
      caseTitle: caseTitle ?? this.caseTitle,
      appointmentDateTime: appointmentDateTime ?? this.appointmentDateTime,
      appointmentType: appointmentType ?? this.appointmentType,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      requestId: requestId ?? this.requestId,
      linkedAppointmentId: linkedAppointmentId ?? this.linkedAppointmentId,
      declineReason: declineReason ?? this.declineReason,
    );
  }
}
