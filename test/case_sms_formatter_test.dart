import 'package:flutter_test/flutter_test.dart';

import 'package:law_connect4/utils/case_sms_formatter.dart';

void main() {
  const caseTitle =
      'HEIRS OF VICTORIANA CALIB-OG vs. RUBEN MONTEJO, AXEL JOSEPH L. BINAORO, DENNIS M. LUMANSOC, SPS. DANILO & PRESCILLA ARMINGOL';

  test('shortens long case titles with et al. instead of a mid-name cut', () {
    final title = CaseSmsFormatter.shortTitle(caseTitle);
    expect(title, 'HEIRS OF VICTORIANA CALIB-OG vs. RUBEN MONTEJO, et al.');
    expect(title, isNot(contains('...')));
  });

  test('keeps short titles untouched', () {
    expect(CaseSmsFormatter.shortTitle('  SANTOS vs. CRUZ  '), 'SANTOS vs. CRUZ');
  });

  test('maps every client-visible status to copy', () {
    String body(String status, {String? resultLabel}) =>
        CaseSmsFormatter.statusBody(caseTitle, status,
            resultLabel: resultLabel)!;

    expect(body('pending'), endsWith('is now open.'));
    expect(body('open'), endsWith('is now open.'));
    expect(body('accepted'), endsWith('has been accepted.'));
    expect(body('in_progress'), endsWith('is now in progress.'));
    expect(body('ongoing'), endsWith('is now in progress.'));
    expect(body('active'), endsWith('is now in progress.'));
    expect(body('completed'), endsWith('has been completed.'));
    expect(
      body('completed', resultLabel: 'Dismissed / withdrawn'),
      endsWith('has been completed. Result: Dismissed / withdrawn.'),
    );
    expect(body('declined'), endsWith('was declined.'));
  });

  test('stays silent for draft and unknown statuses', () {
    expect(CaseSmsFormatter.statusBody(caseTitle, 'under_review'), isNull);
    expect(CaseSmsFormatter.statusBody(caseTitle, 'draft'), isNull);
    expect(CaseSmsFormatter.statusBody(caseTitle, ''), isNull);
  });

  test('every message fits one GSM-7 segment', () {
    final messages = <String>[
      CaseSmsFormatter.created(caseTitle),
      CaseSmsFormatter.hearingScheduled(caseTitle, 'October 28, 2026'),
      for (final status in const [
        'pending',
        'accepted',
        'in_progress',
        'completed',
        'declined',
      ])
        CaseSmsFormatter.statusBody(caseTitle, status,
            resultLabel: 'Dismissed / withdrawn')!,
    ];

    for (final message in messages) {
      expect(message, startsWith(CaseSmsFormatter.brand));
      expect(message.length, lessThanOrEqualTo(160), reason: message);
      expect(message, isNot(contains('—')));
    }
  });
}
