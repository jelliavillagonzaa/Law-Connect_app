import 'case_status_filter.dart';

/// Client-facing SMS copy for case tracking.
///
/// Hearing alerts use the branded multi-line [HearingSmsFormatter]. Case
/// updates stay one line so they fit a single GSM-7 segment.
class CaseSmsFormatter {
  CaseSmsFormatter._();

  static const String brand = 'LawConnect Case Update:';

  /// Keeps the longest message (completed + result label) under 160 chars.
  static const int maxTitleLength = 70;

  /// Returns null when [status] should not notify the client by SMS.
  static String? statusBody(
    String caseTitle,
    String status, {
    String? resultLabel,
  }) {
    final title = shortTitle(caseTitle);
    final s = status.toLowerCase().trim();

    if (s == 'accepted') {
      return '$brand Your case "$title" has been accepted.';
    }
    if (CaseStatusFilter.isOpen(s)) {
      return '$brand Your case "$title" is now open.';
    }
    if (CaseStatusFilter.isInProgress(s)) {
      return '$brand Your case "$title" is now in progress.';
    }
    if (CaseStatusFilter.isCompleted(s)) {
      final result = (resultLabel ?? '').trim();
      if (result.isNotEmpty) {
        return '$brand Your case "$title" has been completed. Result: $result.';
      }
      return '$brand Your case "$title" has been completed.';
    }
    if (s == 'declined') {
      return '$brand Your case "$title" was declined.';
    }
    return null;
  }

  static String created(String caseTitle) {
    return '$brand Your new case "${shortTitle(caseTitle)}" is now open.';
  }

  static String hearingScheduled(String caseTitle, String hearingDate) {
    return '$brand Hearing for "${shortTitle(caseTitle)}" is set on '
        '$hearingDate.';
  }

  static String generic(String caseTitle, String updateMessage) {
    return '$brand Your case "${shortTitle(caseTitle)}": $updateMessage';
  }

  /// Trims to [maxTitleLength], preferring `et al.` over a mid-name cut.
  static String shortTitle(String caseTitle) {
    final t = caseTitle.trim();
    if (t.length <= maxTitleLength) return t;
    final shortened = etAlCaseTitle(t);
    if (shortened.length <= maxTitleLength) return shortened;
    return '${shortened.substring(0, maxTitleLength - 3)}...';
  }

  /// `A vs. B, C, D` → `A vs. B, et al.`. Unchanged when there is no `vs.`.
  static String etAlCaseTitle(String caseTitle) {
    final vs = RegExp(r'\s+(?:vs\.?|versus)\s+', caseSensitive: false);
    final match = vs.firstMatch(caseTitle);
    if (match == null) return caseTitle;
    final right = caseTitle.substring(match.end).trim();
    if (right.toLowerCase().contains('et al')) return caseTitle;
    final firstParty = right.split(RegExp(r'\s*,\s*')).first.trim();
    if (firstParty.isEmpty) return caseTitle;
    return '${caseTitle.substring(0, match.end)}$firstParty, et al.';
  }
}
