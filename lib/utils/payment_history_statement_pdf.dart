import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/invoice_model.dart';
import '../models/payment_model.dart';
import '../utils/currency.dart';

/// Data needed to render one case payment statement (screen + PDF).
class PaymentStatementData {
  final String firmName;
  final String firmAddress;
  final String firmPhone;
  final String firmEmail;
  final String clientName;
  final String clientId;
  final String clientPhone;
  final String clientEmail;
  final String caseNumber;
  final String caseTitle;
  final String practiceArea;
  final String attorneyName;
  final InvoiceModel invoice;
  final List<PaymentModel> payments;

  const PaymentStatementData({
    required this.firmName,
    required this.firmAddress,
    required this.firmPhone,
    required this.firmEmail,
    required this.clientName,
    required this.clientId,
    required this.clientPhone,
    required this.clientEmail,
    required this.caseNumber,
    required this.caseTitle,
    required this.practiceArea,
    required this.attorneyName,
    required this.invoice,
    required this.payments,
  });

  String get referenceNo =>
      'PH-${DateFormat('yyyy').format(DateTime.now())}-${invoice.id.substring(0, invoice.id.length < 5 ? invoice.id.length : 5).toUpperCase()}';

  String get statementDate =>
      DateFormat('MMMM dd, yyyy').format(DateTime.now());

  double get totalLegalFee => invoice.totalLegalFee;
  double get totalPaid => invoice.amountPaid;
  double get remainingBalance => invoice.remainingBalance;
  String get statusLabel => invoice.statusLabel.toUpperCase();
}

/// Builds a professional Statement of Account PDF matching the firm template.
Uint8List buildPaymentStatementPdf(List<PaymentStatementData> statements) {
  final doc = PdfDocument();
  final navy = PdfColor(26, 39, 68);
  final red = PdfColor(192, 57, 43);

  final fontTitle = PdfStandardFont(PdfFontFamily.helvetica, 20,
      style: PdfFontStyle.bold);
  final fontBold = PdfStandardFont(PdfFontFamily.helvetica, 10,
      style: PdfFontStyle.bold);
  final font = PdfStandardFont(PdfFontFamily.helvetica, 9);
  final fontSmall = PdfStandardFont(PdfFontFamily.helvetica, 8);

  for (final s in statements) {
    final page = doc.pages.add();
    final size = page.getClientSize();
    double y = 20;

    // Firm header (left)
    page.graphics.drawRectangle(
      brush: PdfSolidBrush(PdfColor(240, 243, 248)),
      bounds: Rect.fromLTWH(0, y, 50, 50),
    );
    page.graphics.drawString('⚖', PdfStandardFont(PdfFontFamily.helvetica, 24),
        bounds: Rect.fromLTWH(14, y + 10, 40, 40));
    page.graphics.drawString(s.firmName, fontBold,
        bounds: Rect.fromLTWH(58, y, size.width * 0.45, 14));
    y += 16;
    page.graphics.drawString(s.firmAddress, fontSmall,
        bounds: Rect.fromLTWH(58, y, size.width * 0.45, 12));
    y += 12;
    page.graphics.drawString('${s.firmPhone}  |  ${s.firmEmail}', fontSmall,
        bounds: Rect.fromLTWH(58, y, size.width * 0.45, 12));

    // Title (right)
    page.graphics.drawString('PAYMENT HISTORY', fontTitle,
        bounds: Rect.fromLTWH(size.width * 0.55, 20, size.width * 0.42, 24),
        format: PdfStringFormat(alignment: PdfTextAlignment.right));
    page.graphics.drawString('Statement of Account', font,
        bounds: Rect.fromLTWH(size.width * 0.55, 44, size.width * 0.42, 14),
        format: PdfStringFormat(alignment: PdfTextAlignment.right));
    page.graphics.drawString('Statement Date: ${s.statementDate}', fontSmall,
        bounds: Rect.fromLTWH(size.width * 0.55, 62, size.width * 0.42, 12),
        format: PdfStringFormat(alignment: PdfTextAlignment.right));
    page.graphics.drawString('Reference No.: ${s.referenceNo}', fontSmall,
        bounds: Rect.fromLTWH(size.width * 0.55, 74, size.width * 0.42, 12),
        format: PdfStringFormat(alignment: PdfTextAlignment.right));

    y = 95;
    final colW = (size.width - 20) / 3;

    void sectionTitle(String title, double x) {
      page.graphics.drawString(title, fontBold,
          bounds: Rect.fromLTWH(x, y, colW - 8, 14));
    }

    void field(String label, String value, double x, double fy) {
      page.graphics.drawString(label, fontSmall,
          bounds: Rect.fromLTWH(x, fy, colW - 8, 10));
      page.graphics.drawString(value, font,
          bounds: Rect.fromLTWH(x, fy + 11, colW - 8, 12));
    }

    sectionTitle('Client Information', 0);
    sectionTitle('Case Information', colW);
    sectionTitle('Account Summary', colW * 2);

    final fy = y + 18;
    final nameParts = s.clientName.split(' ');
    final first = nameParts.isNotEmpty ? nameParts.first : s.clientName;
    final last =
        nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '—';

    field('First Name', first, 0, fy);
    field('Case Number', s.caseNumber, colW, fy);
    field('Total Legal Fee', Currency.peso(s.totalLegalFee), colW * 2, fy);

    field('Last Name', last, 0, fy + 28);
    field('Case Title', s.caseTitle, colW, fy + 28);
    field('Total Amount Paid', Currency.peso(s.totalPaid), colW * 2, fy + 28);

    field('Client ID', s.clientId, 0, fy + 56);
    field('Practice Area', s.practiceArea, colW, fy + 56);
    field('Remaining Balance', Currency.peso(s.remainingBalance),
        colW * 2, fy + 56);

    field('Contact No.', s.clientPhone.isEmpty ? '—' : s.clientPhone, 0,
        fy + 84);
    field('Attorney', s.attorneyName, colW, fy + 84);
    field('Payment Status', s.statusLabel, colW * 2, fy + 84);

    field('Email', s.clientEmail.isEmpty ? '—' : s.clientEmail, 0, fy + 112);
    field('Total Legal Fee', Currency.peso(s.totalLegalFee), colW, fy + 112);

    // Summary box border
    page.graphics.drawRectangle(
      pen: PdfPen(navy, width: 1),
      bounds: Rect.fromLTWH(colW * 2, y, colW, 150),
    );
    page.graphics.drawRectangle(
      brush: PdfSolidBrush(navy),
      bounds: Rect.fromLTWH(colW * 2, y, colW, 18),
    );
    page.graphics.drawString('Account Summary', fontBold,
        brush: PdfBrushes.white,
        bounds: Rect.fromLTWH(colW * 2 + 6, y + 3, colW - 12, 14));

    y = fy + 150;

    // Payment table
    page.graphics.drawString('Payment History', fontBold,
        bounds: Rect.fromLTWH(0, y, size.width, 16));
    y += 20;

    final grid = PdfGrid();
    grid.columns.add(count: 7);
    grid.headers.add(1);
    final headers = [
      'Payment ID',
      'Date & Time',
      'Amount Paid',
      'Payment Type',
      'Payment Status',
      'Recorded By',
      'Remarks / OR No.',
    ];
    for (var i = 0; i < headers.length; i++) {
      grid.headers[0].cells[i].value = headers[i];
      grid.headers[0].cells[i].style.backgroundBrush =
          PdfSolidBrush(navy);
      grid.headers[0].cells[i].style.textBrush = PdfBrushes.white;
      grid.headers[0].cells[i].style.font = fontBold;
    }

    for (final p in s.payments) {
      final row = grid.rows.add();
      row.cells[0].value = p.displayPaymentId;
      row.cells[1].value =
          DateFormat('MMM dd, yyyy hh:mm a').format(p.paidAt);
      row.cells[2].value = Currency.peso(p.amount);
      row.cells[3].value = p.methodLabel;
      row.cells[4].value = 'PAID';
      row.cells[5].value = p.recordedByLabel;
      row.cells[6].value = p.referenceNo ?? p.note ?? '—';
      for (var i = 0; i < 7; i++) {
        row.cells[i].style.font = fontSmall;
      }
    }

    if (s.remainingBalance > 0.001) {
      final row = grid.rows.add();
      row.cells[0].value = '—';
      row.cells[1].value = '—';
      row.cells[2].value = Currency.peso(s.remainingBalance);
      row.cells[3].value = '—';
      row.cells[4].value = 'UNPAID';
      row.cells[5].value = '—';
      row.cells[6].value = 'Remaining Balance';
      for (var i = 0; i < 7; i++) {
        row.cells[i].style.font = fontSmall;
        row.cells[i].style.textBrush = PdfSolidBrush(red);
      }
    }

    grid.style = PdfGridStyle(
      cellPadding: PdfPaddings(left: 4, right: 4, top: 4, bottom: 4),
      font: fontSmall,
    );
  grid.draw(
      page: page,
      bounds: Rect.fromLTWH(0, y, size.width, 200),
    );

    // Footer note
    final footerY = size.height - 80;
    page.graphics.drawRectangle(
      brush: PdfSolidBrush(PdfColor(245, 245, 245)),
      bounds: Rect.fromLTWH(0, footerY, size.width * 0.65, 50),
    );
    page.graphics.drawString(
      'Note: This statement reflects all payments recorded at the law office. '
      'Please keep this document for your records. For questions, contact the firm.',
      fontSmall,
      bounds: Rect.fromLTWH(8, footerY + 8, size.width * 0.62, 40),
    );
    page.graphics.drawString('Prepared By:', fontSmall,
        bounds: Rect.fromLTWH(size.width * 0.7, footerY + 20, 100, 12));
    page.graphics.drawString(s.firmName, fontBold,
        bounds: Rect.fromLTWH(size.width * 0.7, footerY + 34, size.width * 0.28, 14));
  }

  final bytes = doc.saveSync();
  doc.dispose();
  return Uint8List.fromList(bytes);
}
