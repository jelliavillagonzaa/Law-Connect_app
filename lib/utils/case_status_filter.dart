import '../models/case_model.dart';

/// Shared case-tracking filters for attorney and staff.
///
/// UI flow: Draft → Open → In progress → Completed.
/// Firestore still stores `pending` for Open and `under_review` for Draft.
class CaseStatusFilter {
  CaseStatusFilter._();

  static const String all = 'all';
  static const String active = 'active';
  static const String draft = 'draft';
  static const String open = 'open';
  static const String inProgress = 'in_progress';
  static const String completed = 'completed';

  /// Stored Firestore value for a newly opened (non-draft) case.
  static const String openStoredStatus = 'pending';

  static const List<String> values = [
    all,
    draft,
    open,
    inProgress,
    completed,
  ];

  /// Attorney My Cases filter values.
  static const List<String> attorneyMyCaseValues = [
    all,
    active,
    draft,
    open,
    inProgress,
  ];

  static String label(String filter) {
    switch (filter) {
      case all:
        return 'All';
      case active:
        return 'Active';
      case draft:
        return 'Draft';
      case open:
        return 'Open';
      case inProgress:
        return 'In progress';
      case completed:
        return 'Completed';
      default:
        return 'All';
    }
  }

  static String menuLabel(String filter) {
    if (filter == all) return 'All cases';
    if (filter == active) return 'Active cases';
    return label(filter);
  }

  /// Friendly label for a Firestore `status` value.
  static String statusLabel(String status) {
    final s = status.toLowerCase().trim();
    if (isDraft(s)) return 'Draft';
    if (isOpen(s)) return 'Open';
    if (isInProgress(s)) return 'In progress';
    if (s == 'completed') return 'Completed';
    if (s == 'declined') return 'Declined';
    return status.replaceAll('_', ' ');
  }

  static bool isDraft(String? status) {
    final s = (status ?? '').toLowerCase().trim();
    return s == 'under_review' || s == 'draft';
  }

  static bool isOpen(String? status) {
    final s = (status ?? '').toLowerCase().trim();
    return s == 'pending' || s == 'open' || s == 'accepted';
  }

  static bool isInProgress(String? status) {
    final s = (status ?? '').toLowerCase().trim();
    return s == 'in_progress' || s == 'ongoing' || s == 'active';
  }

  static bool isCompleted(String? status) {
    return (status ?? '').toLowerCase().trim() == 'completed';
  }

  static bool visibleToClient(CaseModel c) {
    return !c.isArchived && !isDraft(c.status);
  }

  static bool matches(CaseModel c, String filter) {
    if (c.isArchived) return false;
    final status = c.status;
    switch (filter) {
      case draft:
        return isDraft(status);
      case open:
        return isOpen(status);
      case inProgress:
        return isInProgress(status);
      case completed:
        return isCompleted(status);
      case active:
        return !isCompleted(status);
      case all:
      default:
        return true;
    }
  }

  static List<CaseModel> apply(List<CaseModel> cases, String filter) {
    return cases.where((c) => matches(c, filter)).toList();
  }
}
