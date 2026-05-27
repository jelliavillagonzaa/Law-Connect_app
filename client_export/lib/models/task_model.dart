import 'package:cloud_firestore/cloud_firestore.dart';

class TaskModel {
  final String id;
  final String title;
  final String description;
  final String assignedTo; // staffId
  final String attorneyId;
  final String? caseId;
  final String status; // pending, in_progress, completed
  final DateTime? dueDate;
  final int? priority; // 1 = Urgent, 2 = High, 3 = Normal, 4 = Low
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;
  final String? notes;
  final List<String>? attachments; // URLs to Firebase Storage
  final String? createdBy; // userId of who created the task (attorney/admin)
  final String? createdByRole; // role of creator (attorney/admin)

  TaskModel({
    required this.id,
    required this.title,
    required this.description,
    required this.assignedTo,
    required this.attorneyId,
    this.caseId,
    required this.status,
    this.dueDate,
    this.priority,
    required this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.notes,
    this.attachments,
    this.createdBy,
    this.createdByRole,
  });

  factory TaskModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TaskModel(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      assignedTo: data['assignedTo'] ?? '',
      attorneyId: data['attorneyId'] ?? '',
      caseId: data['caseId'],
      status: data['status'] ?? 'pending',
      dueDate: (data['dueDate'] as Timestamp?)?.toDate(),
      priority: data['priority'] as int?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      notes: data['notes'],
      attachments: data['attachments'] != null
          ? List<String>.from(data['attachments'])
          : null,
      createdBy: data['createdBy'],
      createdByRole: data['createdByRole'],
    );
  }

  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      'title': title,
      'description': description,
      'assignedTo': assignedTo,
      'attorneyId': attorneyId,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
    };

    if (caseId != null) map['caseId'] = caseId;
    if (dueDate != null) map['dueDate'] = Timestamp.fromDate(dueDate!);
    if (priority != null) map['priority'] = priority;
    if (updatedAt != null) map['updatedAt'] = Timestamp.fromDate(updatedAt!);
    if (completedAt != null) map['completedAt'] = Timestamp.fromDate(completedAt!);
    if (notes != null && notes!.isNotEmpty) map['notes'] = notes;
    if (attachments != null && attachments!.isNotEmpty) map['attachments'] = attachments;
    if (createdBy != null) map['createdBy'] = createdBy;
    if (createdByRole != null) map['createdByRole'] = createdByRole;

    return map;
  }

  TaskModel copyWith({
    String? id,
    String? title,
    String? description,
    String? assignedTo,
    String? attorneyId,
    String? caseId,
    String? status,
    DateTime? dueDate,
    int? priority,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
    String? notes,
    List<String>? attachments,
    String? createdBy,
    String? createdByRole,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      assignedTo: assignedTo ?? this.assignedTo,
      attorneyId: attorneyId ?? this.attorneyId,
      caseId: caseId ?? this.caseId,
      status: status ?? this.status,
      dueDate: dueDate ?? this.dueDate,
      priority: priority ?? this.priority,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
      notes: notes ?? this.notes,
      attachments: attachments ?? this.attachments,
      createdBy: createdBy ?? this.createdBy,
      createdByRole: createdByRole ?? this.createdByRole,
    );
  }
}

