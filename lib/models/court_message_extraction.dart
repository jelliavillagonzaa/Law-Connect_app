/// Structured fields extracted from a court notice (OCR + rules + optional LLM).
class CourtMessageExtraction {
  final DateTime? hearingDateTime;
  final String? courtName;
  final String? judge;
  final String? caseNumber;
  final String? plaintiff;
  final String? defendant;
  final String? attorneyMentioned;
  final String? clientMentioned;
  final String? roomOrBranch;
  final String? summaryNotes;

  const CourtMessageExtraction({
    this.hearingDateTime,
    this.courtName,
    this.judge,
    this.caseNumber,
    this.plaintiff,
    this.defendant,
    this.attorneyMentioned,
    this.clientMentioned,
    this.roomOrBranch,
    this.summaryNotes,
  });

  CourtMessageExtraction copyWith({
    DateTime? hearingDateTime,
    String? courtName,
    String? judge,
    String? caseNumber,
    String? plaintiff,
    String? defendant,
    String? attorneyMentioned,
    String? clientMentioned,
    String? roomOrBranch,
    String? summaryNotes,
  }) {
    return CourtMessageExtraction(
      hearingDateTime: hearingDateTime ?? this.hearingDateTime,
      courtName: courtName ?? this.courtName,
      judge: judge ?? this.judge,
      caseNumber: caseNumber ?? this.caseNumber,
      plaintiff: plaintiff ?? this.plaintiff,
      defendant: defendant ?? this.defendant,
      attorneyMentioned: attorneyMentioned ?? this.attorneyMentioned,
      clientMentioned: clientMentioned ?? this.clientMentioned,
      roomOrBranch: roomOrBranch ?? this.roomOrBranch,
      summaryNotes: summaryNotes ?? this.summaryNotes,
    );
  }

  /// One-line title for calendar event.
  String suggestedTitle() {
    final parts = <String>[];
    if (courtName != null && courtName!.trim().isNotEmpty) {
      parts.add(courtName!.trim());
    }
    parts.add('Hearing');
    if (caseNumber != null && caseNumber!.trim().isNotEmpty) {
      parts.add('(${caseNumber!.trim()})');
    }
    return parts.join(' ');
  }

  /// Longer description for Firestore `description` on calendar_events.
  String buildDescription() {
    final b = StringBuffer();
    if (judge != null && judge!.trim().isNotEmpty) {
      b.writeln('Judge: ${judge!.trim()}');
    }
    if (roomOrBranch != null && roomOrBranch!.trim().isNotEmpty) {
      b.writeln('Room / branch: ${roomOrBranch!.trim()}');
    }
    if (plaintiff != null && plaintiff!.trim().isNotEmpty) {
      b.writeln('Plaintiff: ${plaintiff!.trim()}');
    }
    if (defendant != null && defendant!.trim().isNotEmpty) {
      b.writeln('Defendant: ${defendant!.trim()}');
    }
    if (attorneyMentioned != null && attorneyMentioned!.trim().isNotEmpty) {
      b.writeln('Attorney (notice): ${attorneyMentioned!.trim()}');
    }
    if (clientMentioned != null && clientMentioned!.trim().isNotEmpty) {
      b.writeln('Client (notice): ${clientMentioned!.trim()}');
    }
    if (summaryNotes != null && summaryNotes!.trim().isNotEmpty) {
      b.writeln(summaryNotes!.trim());
    }
    return b.toString().trim();
  }
}
