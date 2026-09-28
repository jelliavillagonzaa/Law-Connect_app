import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/case_model.dart';
import 'case_result.dart';
import 'case_status_filter.dart';

class CaseHistoryEvent {
  const CaseHistoryEvent({required this.label, this.at});

  final String label;
  final DateTime? at;

  String get dateLabel {
    if (at == null) return '';
    return DateFormat('MMM d, yyyy').format(at!);
  }
}

/// Readable case history from `progress.timeline` (no UIDs or raw maps).
class CaseHistory {
  CaseHistory._();

  static const opened = 'Case opened';
  static const draftCreated = 'Draft created';
  static const workStarted = 'Work started';
  static const completed = 'Case completed';

  static String completedWith(String? result) {
    final label = CaseResult.label(result);
    if (label.isEmpty) return completed;
    return '$completed — $label';
  }

  static String? actionForStatus(String status, {String? caseResult}) {
    if (CaseStatusFilter.isDraft(status)) return draftCreated;
    if (CaseStatusFilter.isOpen(status)) return opened;
    if (CaseStatusFilter.isInProgress(status)) return workStarted;
    if (CaseStatusFilter.isCompleted(status)) {
      return completedWith(caseResult);
    }
    return null;
  }

  static String? labelForAction(String? raw, {String? caseResult}) {
    final action = (raw ?? '').trim().toLowerCase();
    if (action.isEmpty) return null;
    if (action.contains('draft')) return draftCreated;
    if (action.contains('created') || action.contains('opened')) return opened;
    if (action.contains('start') ||
        action.contains('in progress') ||
        action.contains('in_progress') ||
        action.contains('work started')) {
      return workStarted;
    }
    if (action.contains('complete')) {
      String? fromAction;
      if (action.contains('won')) fromAction = CaseResult.won;
      if (action.contains('lost')) fromAction = CaseResult.lost;
      if (action.contains('settled')) fromAction = CaseResult.settled;
      if (action.contains('dismissed') || action.contains('withdrawn')) {
        fromAction = CaseResult.dismissed;
      }
      return completedWith(fromAction ?? caseResult);
    }
    if (action == opened.toLowerCase()) return opened;
    return null;
  }

  static List<CaseHistoryEvent> fromCase(CaseModel caseModel) {
    final events = <CaseHistoryEvent>[];
    final timeline = caseModel.progress?['timeline'];
    if (timeline is List) {
      for (final item in timeline) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final label = labelForAction(
          map['action']?.toString(),
          caseResult: map['result']?.toString() ?? caseModel.caseResult,
        );
        if (label == null) continue;
        events.add(CaseHistoryEvent(label: label, at: _parseDate(map['date'])));
      }
    }

    if (events.isEmpty) {
      events.add(
        CaseHistoryEvent(
          label: CaseStatusFilter.isDraft(caseModel.status)
              ? draftCreated
              : opened,
          at: caseModel.createdAt,
        ),
      );
    }

    events.sort((a, b) {
      final aMs = a.at?.millisecondsSinceEpoch ?? 0;
      final bMs = b.at?.millisecondsSinceEpoch ?? 0;
      return aMs.compareTo(bMs);
    });
    return events;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return null;
    }
  }
}
