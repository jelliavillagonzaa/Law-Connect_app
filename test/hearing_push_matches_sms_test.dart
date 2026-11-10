import 'package:flutter_test/flutter_test.dart';
import 'package:law_connect4/utils/hearing_notification_formatter.dart';
import 'package:law_connect4/utils/hearing_sms_formatter.dart';

void main() {
  const hearing = {
    'caseNo': '5297',
    'caseTitle': 'HEIRS OF VICTORIANA CALIB-OG vs. RUBEN MONTEJO',
    'clientName': 'RUBEN MONTEJO',
    'courtBranch': 'BRANCH 12',
    'hearingDate': 'October 28, 2026',
    'hearingTime': '8:30 in the morning',
  };

  test('hearing SMS keeps branded layout with Date after case number', () {
    final sms = HearingSmsFormatter.build(
      caseNo: hearing['caseNo']!,
      caseTitle: hearing['caseTitle']!,
      clientName: hearing['clientName']!,
      hearingDate: hearing['hearingDate']!,
      hearingTime: hearing['hearingTime']!,
      location: hearing['courtBranch']!,
    );

    expect(sms, startsWith('LAWCONNECT HEARING REMINDER'));
    expect(sms, contains('Case #5297'));
    expect(sms, contains('Date: October 28, 2026'));
    expect(sms, contains('Time: 8:30 AM'));
    expect(sms, contains('Location: Branch 12'));
  });

  test('hearing push body matches SMS body exactly', () {
    final sms = HearingSmsFormatter.build(
      caseNo: hearing['caseNo']!,
      caseTitle: hearing['caseTitle']!,
      clientName: hearing['clientName']!,
      hearingDate: hearing['hearingDate']!,
      hearingTime: hearing['hearingTime']!,
      location: hearing['courtBranch']!,
    );
    final push = HearingNotificationFormatter.buildPopupBody(hearing);
    expect(push, sms);
    expect(push, contains('Date: October 28, 2026'));
    expect(push, startsWith('LAWCONNECT HEARING REMINDER'));
  });

  test('hearing push title includes the date', () {
    final title = HearingNotificationFormatter.buildPopupTitle(
      hearing,
      fallback: 'Court hearing / order — 5297',
    );
    expect(title, contains('October 28, 2026'));
    expect(title, contains('5297'));
  });

  test('rebuilds truncated brand body when Date is missing', () {
    final truncated =
        'LAWCONNECT HEARING REMINDER\n\nCase #5297\nHEIRS OF VICTORIANA';
    final body = HearingNotificationFormatter.buildPopupBody({
      ...hearing,
      'message': truncated,
    });
    expect(body, contains('Date: October 28, 2026'));
    expect(body, contains('Time: 8:30 AM'));
    expect(body, startsWith('LAWCONNECT HEARING REMINDER'));
  });

  test('reminder push matches reminder SMS', () {
    final sms = HearingSmsFormatter.build(
      caseNo: hearing['caseNo']!,
      caseTitle: hearing['caseTitle']!,
      hearingDate: hearing['hearingDate']!,
      hearingTime: '8:30 AM',
      location: 'BRANCH 12',
      reminderKind: 'd5',
    );
    final push = HearingSmsFormatter.build(
      caseNo: hearing['caseNo']!,
      caseTitle: hearing['caseTitle']!,
      hearingDate: hearing['hearingDate']!,
      hearingTime: '8:30 AM',
      location: 'BRANCH 12',
      reminderKind: 'd5',
    );

    expect(push, sms);
    expect(push, contains('Date: October 28, 2026'));
    expect(push, contains('Your hearing is in 5 days.'));
  });
}
