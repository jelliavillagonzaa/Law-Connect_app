import 'package:flutter_test/flutter_test.dart';
import 'package:law_connect4/services/hearing_calendar_fields.dart';
import 'package:law_connect4/utils/calendar_live_hearing_map.dart';
import 'package:law_connect4/utils/hearing_notification_formatter.dart';
import 'package:law_connect4/utils/hearing_sms_formatter.dart';
import 'package:law_connect4/widgets/common/hearing_calendar_event_body.dart';

void main() {
  group('Full Location Extraction & Formatting', () {
    const fullOrderText = '''
Republic of the Philippines
REGIONAL TRIAL COURT
10th Judicial Region
BRANCH 12 - OROQUIETA CITY

HEIRS OF VICTORIANA CALIB-OG
Plaintiffs,
-versus-
RUBEN MONTEJO, et al.
Defendants.

WHEREFORE, reset the pre-trial on October 28, 2026 at 8:30 in the morning.
SO ORDERED.
''';

    final hearingDataWithBareLocation = {
      'caseNo': '5297',
      'caseTitle': 'HEIRS OF VICTORIANA CALIB-OG vs. RUBEN MONTEJO',
      'clientName': 'RUBEN MONTEJO',
      'location': 'BRANCH 12',
      'courtBranch': 'BRANCH 12',
      'hearingDate': 'October 28, 2026',
      'hearingTime': '8:30 in the morning',
      'fullText': fullOrderText,
    };

    test('resolveVenueForDisplay enriches bare location with full location from full text', () {
      final venue = HearingCalendarFields.resolveVenueForDisplay(
        hearingDataWithBareLocation,
      );
      expect(venue, equals('Branch 12 - OROQUIETA CITY'));
    });

    test('fieldsForHearingNotificationDetail puts full location in Location field', () {
      final fields = HearingNotificationFormatter.fieldsForHearingNotificationDetail(
        hearingDataWithBareLocation,
        parseOrderText: false,
      );
      final locEntry = fields.firstWhere(
        (f) => f.key == 'Location',
        orElse: () => const MapEntry('', ''),
      );
      expect(locEntry.value, equals('Branch 12 - OROQUIETA CITY'));
    });

    test('SMS alert includes full location from full text', () {
      final venue = HearingCalendarFields.resolveVenueForDisplay(
        hearingDataWithBareLocation,
      );
      final sms = HearingSmsFormatter.build(
        caseNo: hearingDataWithBareLocation['caseNo']!,
        caseTitle: hearingDataWithBareLocation['caseTitle']!,
        clientName: hearingDataWithBareLocation['clientName']!,
        hearingDate: hearingDataWithBareLocation['hearingDate']!,
        hearingTime: hearingDataWithBareLocation['hearingTime']!,
        location: venue,
      );
      expect(sms, contains('Location: Branch 12 - OROQUIETA CITY'));
    });

    test('fieldsForCalendarHearing enriches bare location with full location from full text', () {
      final fields = HearingNotificationFormatter.fieldsForCalendarHearing(
        hearingDataWithBareLocation,
      );
      final locEntry = fields.firstWhere(
        (f) => f.key == 'Location',
        orElse: () => const MapEntry('', ''),
      );
      expect(locEntry.value, equals('Branch 12 - OROQUIETA CITY'));
    });

    test('fieldsForCalendarHearing displays full location when only courtBranch is present', () {
      final dataWithoutLocationKey = {
        'caseNo': '5297',
        'caseTitle': 'HEIRS OF VICTORIANA CALIB-OG vs. RUBEN MONTEJO',
        'clientName': 'RUBEN MONTEJO',
        'courtBranch': 'BRANCH 12',
        'hearingDate': 'October 28, 2026',
        'hearingTime': '8:30 in the morning',
        'fullText': fullOrderText,
      };
      final fields = HearingNotificationFormatter.fieldsForCalendarHearing(
        dataWithoutLocationKey,
      );
      final locEntry = fields.firstWhere(
        (f) => f.key == 'Location',
        orElse: () => const MapEntry('', ''),
      );
      expect(locEntry.value, equals('Branch 12 - OROQUIETA CITY'));
    });

    test('CalendarLiveHearingMap.fromHearingDoc includes full location in gridRow', () {
      final row = CalendarLiveHearingMap.fromHearingDoc(
        hearingDataWithBareLocation,
        'doc_5297',
        'attorney_1',
      );
      expect(row, isNotNull);
      expect(row!['location'], equals('Branch 12 - OROQUIETA CITY'));
    });

    test('Push notification popup body includes full location from full text', () {
      final pushBody = HearingNotificationFormatter.buildPopupBody(
        hearingDataWithBareLocation,
      );
      expect(pushBody, contains('Location: Branch 12 - OROQUIETA CITY'));
    });

    test('isPlaceholderCaseNo identifies placeholder case numbers', () {
      expect(HearingCalendarFields.isPlaceholderCaseNo('SAMPLE'), isTrue);
      expect(HearingCalendarFields.isPlaceholderCaseNo('sample'), isTrue);
      expect(HearingCalendarFields.isPlaceholderCaseNo('Civil Case No. SAMPLE'), isTrue);
      expect(HearingCalendarFields.isPlaceholderCaseNo('Case No. TEST'), isTrue);
      expect(HearingCalendarFields.isPlaceholderCaseNo('26-1208-SAMPLE'), isFalse);
      expect(HearingCalendarFields.isPlaceholderCaseNo('Civil Case No. 5297'), isFalse);
    });

    test('mergeHearingSources replaces placeholder caseNo with linked case number', () {
      final placeholderHearing = {
        'caseNo': 'SAMPLE',
        'caseTitle': 'JOREN LIMPAHAN vs. MEATHS BAES JAMBO',
        'clientName': 'MEATHS BAES JAMBO',
        'location': 'Branch 12',
        'courtBranch': 'Branch 12 - OROQUIETA CITY',
      };
      final linkedCase = {
        'id': 'case_1',
        'caseNumber': '26-1208-SAMPLE',
        'caseTitle': 'JOREN LIMPAHAN vs. MEATHS BAES JAMBO',
        'clientName': 'MEATHS BAES JAMBO',
      };
      final merged = HearingCalendarFields.mergeHearingSources(
        [placeholderHearing],
        caseMaps: [linkedCase],
      );
      expect(merged['caseNo'], equals('26-1208-SAMPLE'));
      expect(merged['location'], equals('Branch 12 - OROQUIETA CITY'));
    });

    test('hearingCalendarDisplayTitle prefers real title/client when caseNo is SAMPLE', () {
      final eventWithPlaceholder = {
        'caseNo': 'SAMPLE',
        'caseTitle': 'JOREN LIMPAHAN vs. MEATHS BAES JAMBO',
        'clientName': 'MEATHS BAES JAMBO',
      };
      final title = hearingCalendarDisplayTitle(eventWithPlaceholder);
      expect(title, equals('MEATHS BAES JAMBO'));

      final eventWithRealCase = {
        'caseNo': '26-1208-SAMPLE',
        'caseTitle': 'JOREN LIMPAHAN vs. MEATHS BAES JAMBO',
        'clientName': 'MEATHS BAES JAMBO',
      };
      expect(hearingCalendarDisplayTitle(eventWithRealCase), equals('26-1208-SAMPLE'));
    });

    test('resolveVenueForDisplay prioritizes non-bare courtBranch when location is bare Branch 12', () {
      final data = {
        'location': 'Branch 12',
        'courtBranch': 'Branch 12 - OROQUIETA CITY',
      };
      final venue = HearingCalendarFields.resolveVenueForDisplay(data);
      expect(venue, equals('Branch 12 - OROQUIETA CITY'));
    });

    test('CalendarLiveHearingMap.fromHearingDoc preserves createdAt and updatedAt in gridRow', () {
      final created = DateTime(2026, 10, 19, 8, 30);
      final updated = DateTime(2026, 10, 19, 9, 0);
      final row = CalendarLiveHearingMap.fromHearingDoc(
        {
          ...hearingDataWithBareLocation,
          'createdAt': created,
          'updatedAt': updated,
        },
        'doc_5297',
        'attorney_1',
      );
      expect(row, isNotNull);
      expect(row!['createdAt'], equals(created));
      expect(row['updatedAt'], equals(updated));
    });

    test('cleanCaseDocketNo strips Civil Case No. and returns digits', () {
      expect(HearingCalendarFields.cleanCaseDocketNo('Civil Case No. 5297'), equals('5297'));
      expect(HearingCalendarFields.cleanCaseDocketNo('Criminal Case No. 5297'), equals('5297'));
      expect(HearingCalendarFields.cleanCaseDocketNo('Case No. 5297'), equals('5297'));
      expect(HearingCalendarFields.cleanCaseDocketNo(5297), equals('5297'));
    });

    test('hearingCalendarDisplayTitle strips Civil Case No. to show clean case number', () {
      final ev = {
        'caseNo': 'Civil Case No. 5297',
        'caseTitle': 'HEIRS OF VICTORIANA CALIB-OG',
        'clientName': 'HEIRS OF VICTORIANA CALIB-OG',
      };
      expect(hearingCalendarDisplayTitle(ev), equals('5297'));
    });

    test('resolveCaseTitleForDisplay parses Philippine multi-line court order caption', () {
      const order = '''
Republic of the Philippines
REGIONAL TRIAL COURT
10th Judicial Region
BRANCH 12 - OROQUIETA CITY
HEIRS OF VICTORIANA CALIB-OG
Namely: ELENA G. RAMIREZ,
CRISPINA ACEBES, CANDELARIA
RAMIREZ, MARCELO CALIB-OG
and JANE CALIB-OG,
Plaintiff,
-versus -
Civil Case No. 5297
For: Recovery of
Ownership with
Possession
RUBEN MONTEJO, AXEL JOSEPH
L. BINAORO, DENNIS M. LUMANSOC,
SPS. DANILO & PRESCILLA ARMINGOL,
RUDY ACEBES & RICKY MEDINA,
Defendants.
ORDER
WHEREFORE, reset the pre-trial on October 28, 2026 at 8:30 in the morning.
''';
      final title = HearingCalendarFields.resolveCaseTitleForDisplay({'fullText': order});
      expect(
        title,
        equals('HEIRS OF VICTORIANA CALIB-OG vs. RUBEN MONTEJO, AXEL JOSEPH L. BINAORO, DENNIS M. LUMANSOC, SPS. DANILO & PRESCILLA ARMINGOL, RUDY ACEBES & RICKY MEDINA'),
      );
    });

    test('resolveClientForDisplay resolves answering defendants over plaintiff', () {
      final data = {
        'caseNo': 'Civil Case No. 5297',
        'caseTitle': 'HEIRS OF VICTORIANA CALIB-OG vs. RUBEN MONTEJO, AXEL JOSEPH L. BINAORO, DENNIS M. LUMANSOC, SPS. DANILO & PRESCILLA ARMINGOL, RUDY ACEBES & RICKY MEDINA',
        'clientName': 'HEIRS OF VICTORIANA CALIB-OG',
      };
      final client = HearingCalendarFields.resolveClientForDisplay(data);
      expect(
        client,
        equals('RUBEN MONTEJO, AXEL JOSEPH L. BINAORO, DENNIS M. LUMANSOC, SPS. DANILO & PRESCILLA ARMINGOL, RUDY ACEBES & RICKY MEDINA'),
      );
    });
  });
}
