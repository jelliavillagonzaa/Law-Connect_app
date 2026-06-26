import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'payment_history_report.dart';

/// Builds a Payment History Report PDF that matches the on-screen layout.
Future<Uint8List> buildPaymentHistoryReportPdf(
  PaymentHistoryReport report,
) async {
  final doc = PdfDocument();
  doc.pageSettings.orientation = PdfPageOrientation.landscape;
  final margins = PdfMargins();
  margins.all = 24;
  doc.pageSettings.margins = margins;

  final navy = PdfColor(26, 39, 68);
  final green = PdfColor(34, 139, 34);
  final greenBg = PdfColor(232, 245, 233);
  final orange = PdfColor(181, 142, 58);
  final orangeBg = PdfColor(255, 243, 224);
  final red = PdfColor(192, 57, 43);
  final redBg = PdfColor(255, 235, 235);
  final borderGray = PdfColor(220, 220, 220);

  final fontTitle = PdfStandardFont(
    PdfFontFamily.helvetica,
    18,
    style: PdfFontStyle.bold,
  );
  final fontBold = PdfStandardFont(PdfFontFamily.helvetica, 8,
      style: PdfFontStyle.bold);
  final font = PdfStandardFont(PdfFontFamily.helvetica, 7.5);
  final fontSmall = PdfStandardFont(PdfFontFamily.helvetica, 7);

  PdfPage page = doc.pages.add();
  PdfGraphics g = page.graphics;
  var size = page.getClientSize();
  var y = 0.0;

  Future<void> ensureSpace(double needed) async {
    if (y + needed <= size.height - 24) return;
    page = doc.pages.add();
    g = page.graphics;
    size = page.getClientSize();
    y = 0;
  }

  Future<void> drawHeader() async {
    final meta = report.meta;
    final rightX = size.width * 0.38;
    final rightW = size.width - rightX;

    // Title — measure text so bounds are never too small (Syncfusion clips otherwise).
    const titleText = 'PAYMENT HISTORY REPORT';
    final titleSize = fontTitle.measureString(titleText);
    g.drawString(
      titleText,
      fontTitle,
      brush: PdfSolidBrush(navy),
      bounds: Rect.fromLTWH(
        rightX,
        y,
        rightW,
        titleSize.height + 6,
      ),
      format: PdfStringFormat(
        alignment: PdfTextAlignment.right,
        lineAlignment: PdfVerticalAlignment.top,
      ),
    );
    final metaY = y + titleSize.height + 8;
    g.drawString(
      'Report Date: ${meta.reportDate}',
      fontSmall,
      brush: PdfSolidBrush(PdfColor(80, 80, 80)),
      bounds: Rect.fromLTWH(rightX, metaY, rightW, 12),
      format: PdfStringFormat(alignment: PdfTextAlignment.right),
    );
    g.drawString(
      'Prepared By: ${meta.preparedBy}',
      fontSmall,
      brush: PdfSolidBrush(PdfColor(80, 80, 80)),
      bounds: Rect.fromLTWH(rightX, metaY + 14, rightW, 12),
      format: PdfStringFormat(alignment: PdfTextAlignment.right),
    );

    try {
      final logoData = await rootBundle.load('assets/logo.png');
      g.drawImage(
        PdfBitmap(logoData.buffer.asUint8List()),
        Rect.fromLTWH(0, y, 40, 40),
      );
    } catch (_) {
      g.drawEllipse(Rect.fromLTWH(0, y, 40, 40), brush: PdfSolidBrush(navy));
    }

    g.drawString(meta.firmName, fontBold,
        bounds: Rect.fromLTWH(48, y, rightX - 56, 14));
    g.drawString(meta.firmAddress, fontSmall,
        bounds: Rect.fromLTWH(48, y + 14, rightX - 56, 10));
    g.drawString('${meta.firmPhone}  |  ${meta.firmEmail}', fontSmall,
        bounds: Rect.fromLTWH(48, y + 26, rightX - 56, 10));

    y += 64;
  }

  await drawHeader();

  final grid = PdfGrid();
  grid.columns.add(count: 9);
  grid.columns[0].width = 28;
  grid.columns[1].width = 95;
  grid.columns[2].width = 72;
  grid.columns[3].width = 62;
  grid.columns[4].width = 62;
  grid.columns[5].width = 72;
  grid.columns[6].width = 58;
  grid.columns[7].width = 68;
  grid.columns[8].width = 80;

  grid.headers.add(1);
  const headers = [
    'No.',
    'Client Name',
    'Case No.',
    'Total Fee',
    'Total Paid',
    'Remaining Balance',
    'Payment Status',
    'Last Payment Date',
    'Recorded By',
  ];
  for (var i = 0; i < headers.length; i++) {
    final cell = grid.headers[0].cells[i];
    cell.value = headers[i];
    cell.style.backgroundBrush = PdfSolidBrush(navy);
    cell.style.textBrush = PdfBrushes.white;
    cell.style.font = fontBold;
    cell.stringFormat = PdfStringFormat(
      alignment: PdfTextAlignment.center,
      lineAlignment: PdfVerticalAlignment.middle,
    );
  }

  for (var i = 0; i < report.rows.length; i++) {
    final r = report.rows[i];
    final row = grid.rows.add();
    final zebra = i.isOdd ? PdfColor(248, 249, 252) : PdfColor(255, 255, 255);

    row.cells[0].value = '${i + 1}';
    row.cells[1].value = r.clientName;
    row.cells[2].value = r.caseNumber;
    // Use plain ASCII text for PDF amounts to avoid unsupported characters.
    row.cells[3].value = 'PHP ${r.totalFee.toStringAsFixed(2)}';
    row.cells[4].value = 'PHP ${r.totalPaid.toStringAsFixed(2)}';
    row.cells[5].value = 'PHP ${r.remainingBalance.toStringAsFixed(2)}';
    row.cells[6].value = r.statusLabel;
    row.cells[7].value = r.lastPaymentDate != null
        ? DateFormat('MMM dd, yyyy').format(r.lastPaymentDate!)
        : '-';
    row.cells[8].value = r.lastRecordedBy ?? '-';

    PdfColor statusColor = red;
    PdfColor statusBg = redBg;
    switch (r.statusLabel) {
      case 'PAID':
        statusColor = green;
        statusBg = greenBg;
        break;
      case 'PARTIAL':
        statusColor = orange;
        statusBg = orangeBg;
        break;
    }

    for (var c = 0; c < 9; c++) {
      row.cells[c].style.font = font;
      row.cells[c].style.backgroundBrush = PdfSolidBrush(zebra);
      row.cells[c].style.borders.all = PdfPen(borderGray, width: 0.25);
      row.cells[c].stringFormat = PdfStringFormat(
        alignment: c == 1 || c == 8
            ? PdfTextAlignment.left
            : PdfTextAlignment.center,
        lineAlignment: PdfVerticalAlignment.middle,
      );
    }

    row.cells[6].style.backgroundBrush = PdfSolidBrush(statusBg);
    row.cells[6].style.textBrush = PdfSolidBrush(statusColor);
    row.cells[6].style.font = fontBold;
  }

  grid.style = PdfGridStyle(
    cellPadding: PdfPaddings(left: 4, right: 4, top: 5, bottom: 5),
    font: font,
  );

  final tableResult = grid.draw(
    page: page,
    bounds: Rect.fromLTWH(0, y, size.width, size.height - y - 120),
  );

  y = (tableResult?.bounds.bottom ?? y + 80) + 14;
  await ensureSpace(110);

  g.drawString('SUMMARY', fontBold, bounds: Rect.fromLTWH(0, y, 80, 12));
  y += 14;

  final s = report.summary;
  final gap = 10.0;
  final cardW = (size.width - gap * 2) / 3;
  _summaryPdfCard(
      g,
      'TOTAL UNPAID CASES',
      s.unpaidCount,
      'PHP ${s.unpaidAmount.toStringAsFixed(2)}',
      red,
      redBg,
      0,
      y,
      cardW);
  _summaryPdfCard(
      g,
      'TOTAL PARTIALLY PAID CASES',
      s.partialCount,
      'PHP ${s.partialAmount.toStringAsFixed(2)}',
      orange,
      orangeBg,
      cardW + gap,
      y,
      cardW);
  _summaryPdfCard(
      g,
      'TOTAL FULLY PAID CASES',
      s.paidCount,
      'PHP ${s.paidAmount.toStringAsFixed(2)}',
      green,
      greenBg,
      (cardW + gap) * 2,
      y,
      cardW);

  y += 58;
  await ensureSpace(44);

  g.drawRectangle(
    brush: PdfSolidBrush(PdfColor(245, 245, 245)),
    bounds: Rect.fromLTWH(0, y, size.width * 0.72, 30),
  );
  g.drawString(
    'NOTE: This report shows all clients and their payment status as of the report date.',
    fontSmall,
    bounds: Rect.fromLTWH(8, y + 8, size.width * 0.7, 24),
  );

  g.drawString(report.meta.preparedBy, fontBold,
      bounds: Rect.fromLTWH(size.width * 0.74, y + 4, size.width * 0.25, 10),
      format: PdfStringFormat(alignment: PdfTextAlignment.right));
  g.drawString('Attorney at Law', fontSmall,
      bounds: Rect.fromLTWH(size.width * 0.74, y + 16, size.width * 0.25, 10),
      format: PdfStringFormat(alignment: PdfTextAlignment.right));

  final bytes = doc.saveSync();
  doc.dispose();
  return Uint8List.fromList(bytes);
}

void _summaryPdfCard(
  PdfGraphics g,
  String title,
  int count,
  String amount,
  PdfColor color,
  PdfColor bg,
  double x,
  double y,
  double w,
) {
  final titleFont = PdfStandardFont(PdfFontFamily.helvetica, 7);
  final countFont = PdfStandardFont(PdfFontFamily.helvetica, 22,
      style: PdfFontStyle.bold);

  g.drawRectangle(
    brush: PdfSolidBrush(bg),
    pen: PdfPen(color, width: 0.6),
    bounds: Rect.fromLTWH(x, y, w, 50),
  );
  g.drawString(title, titleFont,
      brush: PdfSolidBrush(color),
      bounds: Rect.fromLTWH(x + 8, y + 6, w - 16, 10));
  g.drawString('$count', countFont,
      brush: PdfSolidBrush(color),
      bounds: Rect.fromLTWH(x + 8, y + 18, w - 16, 18));
  g.drawString('Total Amount: $amount', titleFont,
      brush: PdfSolidBrush(color),
      bounds: Rect.fromLTWH(x + 8, y + 36, w - 16, 10));
}
