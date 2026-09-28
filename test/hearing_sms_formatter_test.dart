import 'package:flutter_test/flutter_test.dart';

import 'package:law_connect4/utils/hearing_sms_formatter.dart';

void main() {
  const caseNo = '5297';
  const caseTitle =
      'HEIRS OF VICTORIANA CALIB-OG vs. RUBEN MONTEJO, AXEL JOSEPH L. BINAORO, DENNIS M. LUMANSOC, SPS. DANILO & PRESCILLA ARMINGOL, RUDY ACEBES & RICKY MEDINA';
  const location = 'BRANCH 12';
  const date = 'October 28, 2026';
  const time = '8:30 in the morning';

  test('formats scheduled hearing SMS without Role or concatenated dashes', () {
    final text = HearingSmsFormatter.build(
      caseNo: caseNo,
      caseTitle: caseTitle,
      clientName:
          'RUBEN MONTEJO, AXEL JOSEPH L. BINAORO, DENNIS M. LUMANSOC, SPS. DANILO & PRESCILLA ARMINGOL, RUDY ACEBES & RICKY MEDINA',
      hearingDate: date,
      hearingTime: time,
      location: location,
    );

    expect(text, startsWith('LAWCONNECT HEARING REMINDER'));
    expect(text, contains('Case #5297'));
    expect(text, contains('HEIRS OF VICTORIANA CALIB-OG'));
    expect(text, contains('vs.'));
    expect(text, contains('RUBEN MONTEJO'));
    expect(text, contains('AXEL JOSEPH L. BINAORO'));
    expect(text, contains('Time: 8:30 AM'));
    expect(text, contains('Location: Branch 12'));
    expect(text, contains('Date: October 28, 2026'));
    expect(text, contains('Please be reminded of your scheduled hearing.'));
    expect(text, isNot(contains('Role: Attorney')));
    expect(text, isNot(contains(' - ')));
    expect(text, isNot(contains('in the morning')));
    expect(text, isNot(contains('Client: RUBEN MONTEJO')));
  });

  test('formats 5-day, 2-day, and hearing-day reminder copy', () {
    final five = HearingSmsFormatter.build(
      caseNo: caseNo,
      caseTitle: caseTitle,
      hearingDate: date,
      hearingTime: '8:30 AM',
      location: location,
      reminderKind: 'd5',
    );
    expect(five, contains('Your hearing is in 5 days.'));
    expect(five, contains('Please prepare for your scheduled hearing.'));

    final two = HearingSmsFormatter.build(
      caseNo: caseNo,
      caseTitle: caseTitle,
      hearingDate: date,
      hearingTime: '8:30 AM',
      location: location,
      reminderKind: 'd2',
    );
    expect(two, contains('Your hearing is in 2 days.'));
    expect(two, contains('Please be reminded of your upcoming hearing.'));

    final today = HearingSmsFormatter.build(
      caseNo: caseNo,
      caseTitle: caseTitle,
      hearingDate: date,
      hearingTime: '8:30 AM',
      location: location,
      reminderKind: 'hearing_day',
    );
    expect(today, contains('Your hearing is today.'));
    expect(today, contains('Please be reminded of your hearing today.'));
  });

  test('formats morning and afternoon court times as AM/PM', () {
    expect(HearingSmsFormatter.formatTime('8:30 in the morning'), '8:30 AM');
    expect(HearingSmsFormatter.formatTime('1:00 in the afternoon'), '1:00 PM');
    expect(HearingSmsFormatter.formatTime('8:30 a.m.'), '8:30 AM');
    expect(HearingSmsFormatter.formatTime('8:30 AM'), '8:30 AM');
  });
}
