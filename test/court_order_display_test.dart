import 'package:flutter_test/flutter_test.dart';
import 'package:law_connect4/services/hearing_calendar_fields.dart';
import 'package:law_connect4/utils/court_order_display.dart';

void main() {
  const ocr = '''
Republic of the Philippines
REGIONAL TRIAL COURT
10th Judicial Region
BRANCH 12 - OROQUIETA CITY
Email Address: rtclorg012@judiciary.gov.ph
Contact Number: 09708694723
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
L. RINAORO, DENNIS M. LUMASOC,
SPS. DANILO & PRESCILLA ARMINGOL,
RUDY ACEBES & RICKY MEDINA,
Defendants.
x-------------------------------------------------x
ORDER
When this case was called for pre-trial, only Atty.
Diogenes B. Apao, Jr. appeared in court for the answering
defendants. Answering defendants' Rudy Acebes, Dennis
Lumasoc and Ricky Medina are present inside the courtroom.
Plaintiffs and their counsel failed to appear despite due notice.
In view of the absence of the plaintiff and their counsel
and the failure of the summons, the court could not
proceed for today's pre-trial.
WHEREFORE, reset the pre-trial on October 28, 2026 at
8:30 in the morning.
The plaintiffs and counsel are directed to file the
necessary pleading in order for the court to acquire
jurisdiction over the named defendants who were not duly
served of the summons issued to them.
SO ORDERED.
Done in open court this 8th day of September, 2026 at
Oroquieta City, Philippines.
JASMIN C. GUIO-DAY
Presiding Judge
PRE-TRIAL ORDER
Civil Case No. 5297
September 8, 2026
Page 2 of 2
cc: Atty. Annemarie A. Quiros
/jmd
''';

  test('lays a scanned order out as a pleading', () {
    final doc = CourtOrderDisplay.parse(ocr);

    expect(doc.isPleading, isTrue);
    expect(doc.header.first, 'Republic of the Philippines');
    expect(doc.header, contains('BRANCH 12 - OROQUIETA CITY'));
    expect(
      doc.caseMeta,
      containsAll([
        'Civil Case No. 5297',
        'For: Recovery of Ownership with Possession',
      ]),
    );

    final heirs = doc.parties.first.text;
    expect(heirs, contains('HEIRS OF VICTORIANA CALIB-OG'));
    expect(heirs, contains('CRISPINA ACEBES, CANDELARIA RAMIREZ'));
    expect(heirs, contains('and JANE CALIB-OG'));
    expect(
      doc.parties.map((line) => line.text),
      containsAll(['Plaintiff,', '- versus -', 'Defendants.']),
    );
    expect(
      doc.parties.map((line) => line.text).join('\n'),
      contains('RUBEN MONTEJO, AXEL JOSEPH L. RINAORO'),
    );

    expect(doc.heading, 'ORDER');
    expect(doc.paragraphs.first, contains('only Atty. Diogenes B. Apao, Jr.'));
    expect(doc.paragraphs.first, contains('due notice.'));
    expect(
      doc.paragraphs.any((p) => p.startsWith('In view of the absence')),
      isTrue,
    );
    expect(
      doc.paragraphs.any(
        (p) => p.contains('WHEREFORE, reset the pre-trial') && p.contains('8:30 in the morning.'),
      ),
      isTrue,
    );
    expect(doc.paragraphs.join('\n'), isNot(contains('Page 2 of 2')));
    expect(doc.paragraphs.join('\n'), isNot(contains('PRE-TRIAL ORDER')));
    expect(doc.soOrdered, isTrue);
    expect(doc.closing, contains('Oroquieta City, Philippines.'));
    expect(doc.signature, contains('JASMIN C. GUIO-DAY'));
    expect(doc.signature, contains('Presiding Judge'));
    expect(doc.footnotes.single, contains('Atty. Annemarie A. Quiros'));
  });

  test('appends a later page that was stored separately', () {
    const pageOne = '''
Republic of the Philippines
REGIONAL TRIAL COURT
BRANCH 12 - OROQUIETA CITY
HEIRS OF VICTORIANA CALIB-OG
Plaintiff,
-versus-
RUBEN MONTEJO,
Defendants.
ORDER
The plaintiffs and counsel are directed to file the necessary pleading in order for the court to acquire jurisdiction over the named defendants who were not duly served of the summons issued to them.
''';
    const pageTwo = '''
Atty. Quiros is hereby directed to pay a fine of Php1,000.00 for failure to appear in today's hearing despite due notice and without justifiable ground, thereby delaying the proceedings of this case.
Parties present and counsel are notified in open court. Let them sign in the minutes of the proceedings to dispense with formal notice.
Notify Atty. Quiros for her information and immediate compliance of the court directives.
SO ORDERED.
Done in open court this 8th day of September, 2026 at Oroquieta City, Philippines.
JASMIN C. GUIO-DIAZ
Presiding Judge
cc: Atty. Annemarie A. Quiros
Atty. Diogenes B. Apao, Jr.
''';

    final merged = CourtOrderTextSources.joinPieces([pageOne, pageTwo]);
    final doc = CourtOrderDisplay.parse(merged);

    expect(doc.paragraphs.join('\n'), contains('Php1,000.00'));
    expect(doc.paragraphs.join('\n'), contains('notified in open court'));
    expect(doc.soOrdered, isTrue);
    expect(doc.closing, contains('Oroquieta City, Philippines.'));
    expect(doc.signature, contains('JASMIN C. GUIO-DIAZ'));
    expect(doc.signature, contains('Presiding Judge'));
    expect(doc.footnotes.join('\n'), contains('Atty. Annemarie A. Quiros'));
    expect(doc.footnotes.join('\n'), contains('Atty. Diogenes B. Apao, Jr.'));
  });

  test('does not paste the inbox summary onto the order', () {
    const order = '''
Republic of the Philippines
REGIONAL TRIAL COURT
10th Judicial Region
BRANCH 12 - OROQUIETA CITY
HEIRS OF VICTORIANA CALIB-OG
Plaintiff,
-versus -
RUBEN MONTEJO,
Defendants.
ORDER
The plaintiffs and counsel are directed to file the necessary pleading in order for the court to acquire jurisdiction over the named defendants who were not duly served of the summons issued to them.
''';
    final wrapped = '''
Case No.: 5297
Client: RUBEN MONTEJO, AXEL JOSEPH L. BINAORO
Court / Branch: BRANCH 12
Order / notice:
$order
Hearing date/time: 2026-10-28T00:30:00.000Z
Matter: HEIRS OF VICTORIANA CALIB-OG
Case record ID: abc123
''';

    final text = CourtOrderTextSources.combine({
      'fullText': order,
      'message': wrapped,
    });
    final doc = CourtOrderDisplay.parse(text);

    expect(text, isNot(contains('Hearing date/time')));
    expect(text, isNot(contains('Case No.:')));
    expect(text, isNot(contains('Client:')));
    expect(doc.header, contains('Republic of the Philippines'));
    expect(doc.paragraphs.join('\n'), contains('summons issued to them.'));
    expect(doc.paragraphs.join('\n'), isNot(contains('Hearing date/time')));
    expect(doc.paragraphs.join('\n'), isNot(contains('Matter:')));
  });

  test('reflows ordinary text without pretending it is a pleading', () {
    final doc = CourtOrderDisplay.parse(
      'Please file the pleading today so the\ncourt can act on the motion.',
    );

    expect(doc.isPleading, isFalse);
    expect(doc.paragraphs.single, contains('Please file the pleading today so the court can act'));
  });

  test('keeps court email in header, not in plaintiff name', () {
    const sample = '''
Republic of the Philippines
REGIONAL TRIAL COURT
10th Judicial Region
BRANCH 12 - OROQUIETA CITY
limpahanloren42@gmail.com
JOREN LIMPAHAN
Plaintiff,
- versus -
MEATHS BAES JAMBO
Defendant.
Civil Case No. SAMPLE
For: Sample Case
ORDER
This page is a sample template prepared using the names Joren Limpahan and Meaths Baes Jambo.
''';
    final doc = CourtOrderDisplay.parse(sample);
    final partyTexts = doc.parties.map((line) => line.text).join('\n');

    expect(doc.header, contains('limpahanloren42@gmail.com'));
    expect(partyTexts, contains('JOREN LIMPAHAN'));
    expect(partyTexts, isNot(contains('@')));
    expect(partyTexts, isNot(contains('gmail')));
  });

  test('cleans SAMPLE mashed caption into a proper pleading layout', () {
    const sample = '''
SAMPLE - NOT AN OFFICIAL COURT DOCUMENT Republic of the Philippines REGIONAL TRIAL COURT 10th Judicial Region BRANCH 12 - OROQUIETA CITY
Sample document layout only JOREN LIMPAHAN
Plaintiff,
- versus -
MEATHS BAES JAMBO
Defendant.
Civil Case No. SAMPLE
For: Sample Case
ORDER
This page is a sample template prepared using the names Joren Limpahan and Meaths Baes Jambo. The wording below is placeholder text for layout demonstration only.
''';

    final doc = CourtOrderDisplay.parse(sample);
    final partyTexts = doc.parties.map((line) => line.text).toList();

    expect(doc.isPleading, isTrue);
    expect(doc.header.first, 'Republic of the Philippines');
    expect(doc.header, contains('REGIONAL TRIAL COURT'));
    expect(doc.header, contains('BRANCH 12 - OROQUIETA CITY'));
    expect(doc.header.join('\n'), isNot(contains('SAMPLE')));
    expect(doc.header.join('\n'), isNot(contains('JOREN')));
    expect(doc.caseMeta, contains('Civil Case No. SAMPLE'));
    expect(partyTexts.first, contains('JOREN LIMPAHAN'));
    expect(partyTexts, containsAll(['Plaintiff,', '- versus -', 'Defendant.']));
    expect(
      partyTexts.indexOf('JOREN LIMPAHAN'),
      lessThan(partyTexts.indexOf('Plaintiff,')),
    );
    expect(
      partyTexts.indexOf('MEATHS BAES JAMBO'),
      greaterThan(partyTexts.indexOf('- versus -')),
    );
    expect(
      partyTexts.indexOf('MEATHS BAES JAMBO'),
      lessThan(partyTexts.indexOf('Defendant.')),
    );
    expect(doc.heading, 'ORDER');
  });

  test('summary stops at the WHEREFORE sentence, not mid-word', () {
    const order = '''
WHEREFORE, reset the pre-trial on October 28, 2026 at
8:30 in the morning.
The plaintiffs and counsel are directed to file the
necessary pleading in order for the court to acquire
jurisdiction over the named defendants who were not duly
served of the summons issued to them.
Page 2 of 2
Atty. Quiros is hereby fined.
SO ORDERED.
''';
    final summary = HearingCalendarFields.extractSummaryFromOrderText(order);
    expect(summary, endsWith('them.'));
    expect(summary, isNot(contains('Pa')));
    expect(summary, contains('8:30 in the morning.'));

    final stored = '${summary.substring(0, summary.length - 2)}Pa…';
    final row = <String, dynamic>{
      'caseNo': '5297',
      'clientName': 'RUBEN MONTEJO',
      'hearingDate': 'October 28, 2026',
      'fullText': order,
      'summary': stored,
    };
    HearingCalendarFields.fillStructuredFieldsFromOrderText(row);
    expect(row['summary'], endsWith('them.'));
    expect(row['summary'], isNot(contains('Pa')));
  });

  test('spam check does not scan an entire court order', () {
    final order = StringBuffer('REGIONAL TRIAL COURT\n');
    for (var i = 0; i < 4000; i++) {
      order.writeln('The court reiterates the previous order of this Branch.');
    }
    order.writeln('SO ORDERED.');
    final row = <String, dynamic>{
      'caseNo': '5297',
      'fullText': order.toString(),
      'source': 'n8n',
      'activityType': 'court_import',
    };
    final started = DateTime.now();
    expect(HearingCalendarFields.isNonCourtHearingSpam(row), isFalse);
    expect(HearingCalendarFields.hasNonEmptyText(row['fullText']), isTrue);
    expect(
      DateTime.now().difference(started),
      lessThan(const Duration(milliseconds: 200)),
    );
    expect(
      HearingCalendarFields.isNonCourtHearingSpam({
        'title': 'Your BlastTV voucher code is ready',
        'message': 'Enjoy your 30-day voucher redemption',
      }),
      isTrue,
    );
  });

  test('corrects mashed two-column OCR layout into proper pleading form', () {
    const rawOcr = '''
Republic of the Philippines
REGIONAL TRIAL COURT
10th Judicial Region
BRANCH 12 - OROQUIETA CITY
Email Address: rtclorq012@judiciary.gov.ph
Contact Number: 09708694723

HEIRS OF VICTORIANA CALIB-OG
Namely: ELENA G. RAMIREZ, CRISPINA ACEBES, CANDELARIA RAMIREZ, MARCELO CALIB-OG and JANE CALIB-OG,
RUBEN MONTEJO, AXEL JOSEPH Possession L. BINAORO, DENNIS M. LUMANSOC, SPS. DANILO & PRESCILLA ARMINGOL, RUDY ACEBES & RICKY MEDINA,
Civil Case No. 5297 versus -
For: Recovery of Ownership with
Plaintiff,
- versus -
Defendants.
When this case was called for pre-trial, only Atty. Diogenes B. Apao, Jr. appeared in court for the answering defendants. Answering defendants' Rudy Acebes, Dennis Lumansoc and Ricky Medina, as well as other defendants' Florencia Ramirez, Herculano Acebes, Joy Sayson, Hilario Pausanos, Jr., Alberta Mabalod and Romeo Damas are all present inside the courtroom. Plaintiffs and their counsel failed to appear despite due notice.
In view of the absence of the plaintiff and their counsel and the fact that the summons issued to defendants' Cesar M. Acebes, Feliciana M. Bari, Rene Mabalod, Sabino M. Mabalod, Jr., Rosabilla M. Galicia, Zenaida M. Dagami, Mely M. Medina and Joan M. Medina were unserved, the court could not proceed for today's pre-trial.
WHEREFORE, reset the pre-trial on October 28, 2026 at 8:30 in the morning.
The plaintiffs and counsel are directed to file the necessary pleading in order for the court to acquire jurisdiction over the named defendants who were not duly served of the summons issued to them. — Page 2 — Parties present and counsel are notified in open court.
Let them sign in the minutes of the Proceedings to dispense with formal notice.
SO ORDERED.
Done in Open court this 9th day of September, 2026 at Oroquieta City, Philippines. ce: Atty. Annemarie A. Quiros Atty. Diogenes B. Apao, Jr.
''';

    final doc = CourtOrderDisplay.parse(rawOcr);
    expect(doc.isPleading, isTrue);
    expect(doc.heading, 'ORDER');
    expect(doc.caseMeta, contains('Civil Case No. 5297'));
    expect(doc.caseMeta, contains('For: Recovery of Ownership with Possession'));

    final partyTexts = doc.parties.map((p) => p.text).toList();
    expect(partyTexts.first, contains('HEIRS OF VICTORIANA CALIB-OG'));
    expect(partyTexts, contains('Plaintiff,'));
    expect(partyTexts, contains('- versus -'));
    expect(partyTexts, contains('Defendants.'));

    final defendants = doc.parties.lastWhere((p) => !p.centered).text;
    expect(defendants, contains('RUBEN MONTEJO'));
    expect(defendants, contains('AXEL JOSEPH L. BINAORO'));
    expect(defendants, isNot(contains('Possession')));
  });
}
