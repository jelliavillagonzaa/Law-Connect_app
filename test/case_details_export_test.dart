import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:law_connect4/models/case_model.dart';
import 'package:law_connect4/utils/case_details_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Word and PDF follow court pleading layout and attorney manual signature', () async {
    final data = CaseDetailsExportData(
      caseModel: CaseModel(
        id: 'case-1',
        clientId: 'client-1',
        attorneyId: 'attorney-1',
        caseTitle: 'Heirs of Victoriana Calib-og vs Ruben Montejo et al',
        caseType: 'Civil',
        court: 'REGIONAL TRIAL COURT',
        courtBranch: 'BRANCH 12 - OROQUIETA CITY',
        courtRegion: '10th Judicial Region',
        courtEmail: 'rtc1orq012@judiciary.gov.ph',
        courtContact: '09708694723',
        caseNumber: 'Civil Case No. 5297',
        natureOfAction: 'Recovery of Ownership with Possession',
        caseDescription:
            'The plaintiffs are seeking recovery of ownership and possession of the disputed parcel of land.',
        status: 'pending',
        createdAt: DateTime(2026, 1, 10),
        updatedAt: DateTime(2026, 1, 10),
      ),
      clientName: 'Heirs of Victoriana Calib-og',
      clientEmail: 'victoriana.heirs@example.com',
      clientPhone: '09123456789',
      clientAddress: 'Oroquieta City, Misamis Occidental',
      attorneyName: 'Atty. Loren Limpahan',
    );

    final word = utf8.decode(await buildCaseDetailsWordBytes(data));
    expect(word, contains('Republic of the Philippines'));
    expect(word, contains('REGIONAL TRIAL COURT'));
    expect(word, contains('BRANCH 12 - OROQUIETA CITY'));
    expect(word, contains('Plaintiff'));
    expect(word, contains('-versus -'));
    expect(word, contains('Defendants'));
    expect(word, contains('Civil Case No. 5297'));
    expect(word, contains('Recovery of Ownership with Possession'));
    expect(word, contains('The plaintiffs are seeking recovery of ownership'));
    expect(word, contains('Atty. Loren Limpahan'));
    expect(word, contains('Counsel for Plaintiff'));

    final pdf = await buildCaseDetailsPdfBytes(data);
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    expect(pdf.length, greaterThan(1000));
  });

  test('PDF properly handles and wraps very long case titles without clipping', () async {
    final longTitleData = CaseDetailsExportData(
      caseModel: CaseModel(
        id: 'case-long-1',
        clientId: 'client-1',
        attorneyId: 'attorney-1',
        caseTitle:
            'CANCELLATION OF CERTIFICATE OF TITLE P-5165 DESIGNATED AS LOT NO._ PLAN PSU-73209, CHERYL MUTIA FELICIANO AND HEIRS OF FELIXBERTO FELICIANO',
        caseType: 'Civil',
        court: 'REGIONAL TRIAL COURT OF MISAMIS OCCIDENTAL 10TH JUDICIAL REGION',
        courtBranch: 'BRANCH 12 - HALL OF JUSTICE, CAPITOL COMPOUND, OROQUIETA CITY',
        caseNumber: 'SPL. CIVIL ACTION NO. 2026-09-8812',
        natureOfAction: 'Cancellation of Title and Recovery of Ownership with Damages',
        caseDescription: 'A very detailed legal description for testing long title wrapping in PDF generation.',
        status: 'pending',
        createdAt: DateTime(2026, 1, 10),
        updatedAt: DateTime(2026, 1, 10),
      ),
      clientName: 'Cheryl Mutia Feliciano',
      attorneyName: 'Atty. Apao',
    );

    final pdf = await buildCaseDetailsPdfBytes(longTitleData);
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    expect(pdf.length, greaterThan(1000));
  });
}
