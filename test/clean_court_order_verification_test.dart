import 'package:flutter_test/flutter_test.dart';
import 'package:law_connect4/utils/court_order_display.dart';
import 'package:law_connect4/utils/hearing_notification_formatter.dart';

void main() {
  test('Verifies clean court order, location, role detection, and display', () {
    const rawOrder = '''REPUBLIC OF THE PHILIPPINES
REGIONAL TRIAL COURT
NATIONAL CAPITAL JUDICIAL REGION
QUEZON CITY, BRANCH 45
PEOPLE OF THE PHILIPPINES, Criminal Case No. Q-26-45871
Plaintiff, For: QUALIFIED THEFT
-versus-
JOREN LIMPAHAN,
Defendant.
ORDER
Before this Court is the scheduled hearing of the above-entitled case for arraignment and pre-trial conference.
After considering the records of the case and the appearance of the parties, the Court hereby sets the
continuation of the proceedings on May 14 , 2026 at 8:00 AM o’clock in the morning at the Session Hall of this
Court, Regional Trial Court, Branch 45, Quezon City.
The accused is hereby directed to appear before this Court on the said date and time. Failure to appear without
valid justification shall constrain the Court to take appropriate legal action pursuant to the Rules of Court.
The prosecution and defense counsel are likewise ordered to submit their respective pre-trial briefs at least three
(3) days before the scheduled hearing.
SO ORDERED.
Quezon City, Philippines, this 12th day of May 2026.
______________________________
HON. MARIA TERESA V. RAMOS
Presiding Judge
NOTICE
TO:
ATTY. APAO
Counsel for the Defense

GREETINGS:
Please take notice that the hearing of the above-entitled case has been scheduled on May 14 , 2026 at 8:00 AM
before the Regional Trial Court, Branch 45, Quezon City.
You are hereby required to appear and assist your client accordingly.
Quezon City, Philippines.
______________________________
HALL OF JUSTICE''';

    final notifData = {
      'caseNo': 'Q-26-45871',
      'caseTitle': 'PEOPLE OF THE PHILIPPINES vs. JOREN LIMPAHAN',
      'clientName': 'Joren Limpahan',
      'location': 'Regional Trial Court, Branch 45, Quezon City',
      'courtBranch': 'Branch 45',
      'hearingDate': 'May 14, 2026',
      'hearingTime': '8:00 AM',
      'fullText': rawOrder,
      'summary': 'Scheduled hearing of the above-entitled case for arraignment and pre-trial conference.',
    };

    final fields = HearingNotificationFormatter.fieldsForHearingNotificationDetail(
      notifData,
      parseOrderText: true,
    );

    final map = {for (final e in fields) e.key: e.value};

    expect(map['Case No.'], equals('Q-26-45871'));
    expect(map['Involved Party'], equals('Joren Limpahan'));
    expect(map['Your Role / Status'], equals('Accused / Defendant'));
    expect(map['Hearing time'], equals('8:00 AM'));
    expect(map['Location'], equals('Regional Trial Court, Branch 45, Quezon City'));
    expect(map.containsKey('Order / full text'), isTrue);

    final parsedOrder = CourtOrderDisplay.parse(map['Order / full text']!);
    expect(parsedOrder.isPleading, isTrue);
    expect(map['Order / full text']!, contains('Q-26-45871'));
  });
}
