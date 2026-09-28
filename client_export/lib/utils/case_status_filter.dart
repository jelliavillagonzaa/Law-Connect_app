import '../models/case_model.dart';

/// Shared case-tracking filters for attorney and staff.
/// Firestore status values are unchanged; these are UI keys/labels only.
class CaseStatusFilter {
  CaseStatusFilter._();

  static const String all = 'all';
  static const String draft = 'draft';
  static const String open = 'open';
  static const String accepted = 'accepted';
  static const String inProgress = 'in_progress';
  static const String completed = 'completed';

  static const List<String> values = [
    all,
    draft,
    open,
    accepted,
    inProgress,
    completed,
  ];

  static String label(String filter) {
    switch (filter) {
      case draft:
        return 'Draft';
      case open:
        return 'Open';
      case accepted:
        return 'Accepted';
      case inProgress:
        return 'In progress';
      case completed:
        return 'Completed';
      case all:
      default:
        return 'All';
    }
  }

  static String menuLabel(String filter) {
    if (filter == all) return 'All cases';
    return label(filter);
  }

  static String statusLabel(String status) {
    switch (status.toLowerCase().trim()) {
      case 'under_review':
      case 'draft':
        return 'Draft';
      case 'pending':
        return 'Open';
      case 'accepted':
        return 'Accepted';
      case 'in_progress':
        return 'In progress';
      case 'completed':
        return 'Completed';
      case 'declined':
        return 'Declined';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  static bool isDraft(String? status) {
    final s = (status ?? '').toLowerCase().trim();
    return s == 'under_review' || s == 'draft';
  }

  static bool visibleToClient(CaseModel c) {
    return !isDraft(c.status);
  }

  static bool matches(CaseModel c, String filter) {
    final status = c.status.toLowerCase().trim();
    switch (filter) {
      case draft:
        return isDraft(status);
      case open:
        return status == 'pending';
      case accepted:
        return status == 'accepted';
      case inProgress:
        return status == 'in_progress';
      case completed:
        return status == 'completed';
      case all:
      default:
        return true;
    }
  }

  static List<CaseModel> apply(List<CaseModel> cases, String filter) {
    return cases.where((c) => matches(c, filter)).toList();
  }
}
