import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'payment_history_report.dart';

/// Builds a professional, mobile-friendly Payment History Report PDF.
///
/// Designed to render with pixel-perfect alignment, zero horizontal overflow,
/// and clear hierarchy so it looks organized and easy to read when viewed on
/// cellphones (CP) or printed in landscape.
Future<Uint8List> buildPaymentHistoryReportPdf(
  PaymentHistoryReport report,
) async {
  final doc = PdfDocument();
  doc.pageSettings.orientation = PdfPageOrientation.landscape;
  final margins = PdfMargins();
  margins.all = 20;
  doc.pageSettings.margins = margins;

  // Modern corporate legal palette
  final navy = PdfColor(15, 23, 42); // #0F172A
  final headerNavy = PdfColor(26, 39, 68); // #1A2744
  final slate = PdfColor(100, 116, 139); // #64748B
  final borderGray = PdfColor(226, 232, 240); // #E2E8F0
  final zebraGray = PdfColor(248, 250, 252); // #F8FAFC

  // Status colors & backgrounds
  final paidGreen = PdfColor(22, 101, 52); // #166534
  final paidGreenBg = PdfColor(220, 252, 231); // #DCFCE7
  final paidGreenBorder = PdfColor(187, 247, 208);

  final partialOrange = PdfColor(180, 83, 9); // #B45309
  final partialOrangeBg = PdfColor(254, 243, 199); // #FEF3C7
  final partialOrangeBorder = PdfColor(253, 230, 138);

  final unpaidRed = PdfColor(185, 28, 28); // #B91C1C
  final unpaidRedBg = PdfColor(254, 226, 226); // #FEE2E2
  final unpaidRedBorder = PdfColor(254, 202, 202);

  // Typography
  final fontTitle = PdfStandardFont(
    PdfFontFamily.helvetica,
    16,
    style: PdfFontStyle.bold,
  );
  final fontFirmName = PdfStandardFont(
    PdfFontFamily.helvetica,
    11.5,
    style: PdfFontStyle.bold,
  );
  final fontSectionTitle = PdfStandardFont(
    PdfFontFamily.helvetica,
    9,
    style: PdfFontStyle.bold,
  );
  final fontHeader = PdfStandardFont(
    PdfFontFamily.helvetica,
    8,
    style: PdfFontStyle.bold,
  );
  final fontBody = PdfStandardFont(PdfFontFamily.helvetica, 7.5);
  final fontBodyBold = PdfStandardFont(
    PdfFontFamily.helvetica,
    7.5,
    style: PdfFontStyle.bold,
  );
  final fontSmall = PdfStandardFont(PdfFontFamily.helvetica, 7);

  final currencyFormat = NumberFormat('#,##0.00');

  PdfPage page = doc.pages.add();
  PdfGraphics g = page.graphics;
  var size = page.getClientSize();
  var y = 0.0;

  // ---------------------------------------------------------------------------
  // 1. Report Header: Perfectly aligned across the full client width
  // ---------------------------------------------------------------------------
  Future<void> drawHeader() async {
    final meta = report.meta;
    final rightW = size.width * 0.45;
    final rightX = size.width - rightW;

    // Right-hand header: Report Title & Metadata
    const titleText = 'PAYMENT HISTORY REPORT';
    final titleMeasure = fontTitle.measureString(titleText);
    g.drawString(
      titleText,
      fontTitle,
      brush: PdfSolidBrush(navy),
      bounds: Rect.fromLTWH(rightX, y, rightW, titleMeasure.height + 4),
      format: PdfStringFormat(
        alignment: PdfTextAlignment.right,
        lineAlignment: PdfVerticalAlignment.top,
      ),
    );

    final metaY = y + titleMeasure.height + 6;
    g.drawString(
      'Report Date: ${meta.reportDate}',
      fontSmall,
      brush: PdfSolidBrush(slate),
      bounds: Rect.fromLTWH(rightX, metaY, rightW, 11),
      format: PdfStringFormat(alignment: PdfTextAlignment.right),
    );
    g.drawString(
      'Prepared By: ${meta.preparedBy}',
      fontSmall,
      brush: PdfSolidBrush(slate),
      bounds: Rect.fromLTWH(rightX, metaY + 13, rightW, 11),
      format: PdfStringFormat(alignment: PdfTextAlignment.right),
    );

    // Left-hand header: Firm Logo & Details
    const logoSize = 46.0;
    try {
      final logoData = await rootBundle.load('assets/logo.png');
      g.drawImage(
        PdfBitmap(logoData.buffer.asUint8List()),
        Rect.fromLTWH(0, y, logoSize, logoSize),
      );
    } catch (_) {
      // Fallback seal emblem
      g.drawEllipse(
        Rect.fromLTWH(0, y, logoSize, logoSize),
        brush: PdfSolidBrush(navy),
      );
      g.drawString(
        'LC',
        fontHeader,
        brush: PdfBrushes.white,
        bounds: Rect.fromLTWH(0, y + 16, logoSize, 14),
        format: PdfStringFormat(alignment: PdfTextAlignment.center),
      );
    }

    final leftTextX = logoSize + 12.0;
    final leftTextW = rightX - leftTextX - 12.0;

    g.drawString(
      meta.firmName,
      fontFirmName,
      brush: PdfSolidBrush(navy),
      bounds: Rect.fromLTWH(leftTextX, y + 2, leftTextW, 14),
    );
    if (meta.firmAddress.isNotEmpty) {
      g.drawString(
        meta.firmAddress,
        fontSmall,
        brush: PdfSolidBrush(slate),
        bounds: Rect.fromLTWH(leftTextX, y + 18, leftTextW, 11),
      );
    }
    final contact = [meta.firmPhone, meta.firmEmail]
        .where((s) => s.isNotEmpty)
        .join('  |  ');
    if (contact.isNotEmpty) {
      g.drawString(
        contact,
        fontSmall,
        brush: PdfSolidBrush(slate),
        bounds: Rect.fromLTWH(leftTextX, y + 30, leftTextW, 11),
      );
    }

    y += 54;

    // Subtle divider line
    g.drawLine(
      PdfPen(borderGray, width: 0.75),
      Offset(0, y),
      Offset(size.width, y),
    );

    y += 12;
  }

  await drawHeader();

  // ---------------------------------------------------------------------------
  // 2. Table: Dynamic proportional columns spanning 100% of client width
  // ---------------------------------------------------------------------------
  final grid = PdfGrid();
  grid.columns.add(count: 9);

  // Proportional weight distribution for landscape (sum = 754)
  final colWeights = <double>[
    28.0, // 0: No.
    132.0, // 1: Client Name
    86.0, // 2: Case No.
    80.0, // 3: Total Fee
    80.0, // 4: Total Paid
    86.0, // 5: Remaining Balance
    68.0, // 6: Payment Status
    82.0, // 7: Last Payment Date
    112.0, // 8: Recorded By
  ];
  final totalWeight = colWeights.reduce((a, b) => a + b);
  for (var i = 0; i < 9; i++) {
    grid.columns[i].width = size.width * (colWeights[i] / totalWeight);
  }

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
    cell.style.backgroundBrush = PdfSolidBrush(headerNavy);
    cell.style.textBrush = PdfBrushes.white;
    cell.style.font = fontHeader;
    cell.style.borders.all = PdfPen(headerNavy, width: 0.5);

    final align = (i == 1 || i == 8)
        ? PdfTextAlignment.left
        : (i == 3 || i == 4 || i == 5)
            ? PdfTextAlignment.right
            : PdfTextAlignment.center;

    cell.stringFormat = PdfStringFormat(
      alignment: align,
      lineAlignment: PdfVerticalAlignment.middle,
    );
  }

  // Populate data rows
  for (var i = 0; i < report.rows.length; i++) {
    final r = report.rows[i];
    final row = grid.rows.add();
    final zebra = i.isOdd ? zebraGray : PdfColor(255, 255, 255);

    row.cells[0].value = '${i + 1}';
    row.cells[1].value = r.clientName;
    row.cells[2].value = r.caseNumber;
    row.cells[3].value = 'PHP ${currencyFormat.format(r.totalFee)}';
    row.cells[4].value = 'PHP ${currencyFormat.format(r.totalPaid)}';
    row.cells[5].value = 'PHP ${currencyFormat.format(r.remainingBalance)}';
    row.cells[6].value = r.statusLabel;
    row.cells[7].value = r.lastPaymentDate != null
        ? DateFormat('MMM dd, yyyy').format(r.lastPaymentDate!)
        : '—';
    row.cells[8].value = r.lastRecordedBy ?? '—';

    PdfColor statusColor = unpaidRed;
    PdfColor statusBg = unpaidRedBg;
    switch (r.statusLabel) {
      case 'PAID':
        statusColor = paidGreen;
        statusBg = paidGreenBg;
        break;
      case 'PARTIAL':
        statusColor = partialOrange;
        statusBg = partialOrangeBg;
        break;
    }

    for (var c = 0; c < 9; c++) {
      row.cells[c].style.font = fontBody;
      row.cells[c].style.backgroundBrush = PdfSolidBrush(zebra);
      row.cells[c].style.borders.all = PdfPen(borderGray, width: 0.4);

      final align = (c == 1 || c == 8)
          ? PdfTextAlignment.left
          : (c == 3 || c == 4 || c == 5)
              ? PdfTextAlignment.right
              : PdfTextAlignment.center;

      row.cells[c].stringFormat = PdfStringFormat(
        alignment: align,
        lineAlignment: PdfVerticalAlignment.middle,
      );
    }

    // Status pill style
    row.cells[6].style.backgroundBrush = PdfSolidBrush(statusBg);
    row.cells[6].style.textBrush = PdfSolidBrush(statusColor);
    row.cells[6].style.font = fontBodyBold;
  }

  grid.style = PdfGridStyle(
    cellPadding: PdfPaddings(left: 6, right: 6, top: 4.5, bottom: 4.5),
    font: fontBody,
  );

  final tableResult = grid.draw(
    page: page,
    bounds: Rect.fromLTWH(0, y, size.width, size.height - y - 90),
  );

  // Safely track the active page graphics after multi-page grid draw
  if (tableResult != null) {
    page = tableResult.page;
    g = page.graphics;
    size = page.getClientSize();
    y = tableResult.bounds.bottom + 16;
  } else {
    y += 80;
  }

  // ---------------------------------------------------------------------------
  // 3. Summary Cards Section
  // ---------------------------------------------------------------------------
  const neededForSummary = 125.0;
  if (y + neededForSummary > size.height - 20) {
    page = doc.pages.add();
    g = page.graphics;
    size = page.getClientSize();
    y = 16;
  }

  g.drawString(
    'SUMMARY',
    fontSectionTitle,
    brush: PdfSolidBrush(navy),
    bounds: Rect.fromLTWH(0, y, 120, 14),
  );
  y += 16;

  final s = report.summary;
  final gap = 10.0;
  final cardW = (size.width - gap * 2) / 3;

  _summaryPdfCard(
    g,
    title: 'TOTAL UNPAID CASES',
    count: s.unpaidCount,
    amount: 'PHP ${currencyFormat.format(s.unpaidAmount)}',
    textColor: unpaidRed,
    bg: unpaidRedBg,
    borderColor: unpaidRedBorder,
    x: 0,
    y: y,
    w: cardW,
  );
  _summaryPdfCard(
    g,
    title: 'TOTAL PARTIALLY PAID CASES',
    count: s.partialCount,
    amount: 'PHP ${currencyFormat.format(s.partialAmount)}',
    textColor: partialOrange,
    bg: partialOrangeBg,
    borderColor: partialOrangeBorder,
    x: cardW + gap,
    y: y,
    w: cardW,
  );
  _summaryPdfCard(
    g,
    title: 'TOTAL FULLY PAID CASES',
    count: s.paidCount,
    amount: 'PHP ${currencyFormat.format(s.paidAmount)}',
    textColor: paidGreen,
    bg: paidGreenBg,
    borderColor: paidGreenBorder,
    x: (cardW + gap) * 2,
    y: y,
    w: cardW,
  );

  y += 58;

  // ---------------------------------------------------------------------------
  // 4. Period Note & Authorized Sign-off
  // ---------------------------------------------------------------------------
  if (y + 36 > size.height - 18) {
    page = doc.pages.add();
    g = page.graphics;
    size = page.getClientSize();
    y = 16;
  }

  final noteW = size.width * 0.70;
  g.drawRectangle(
    brush: PdfSolidBrush(PdfColor(248, 250, 252)),
    pen: PdfPen(borderGray, width: 0.5),
    bounds: Rect.fromLTWH(0, y, noteW, 28),
  );
  g.drawString(
    report.meta.periodNote,
    fontSmall,
    brush: PdfSolidBrush(slate),
    bounds: Rect.fromLTWH(8, y + 6, noteW - 16, 18),
  );

  final sigX = size.width * 0.72;
  final sigW = size.width - sigX;
  g.drawString(
    report.meta.preparedBy,
    fontHeader,
    brush: PdfSolidBrush(navy),
    bounds: Rect.fromLTWH(sigX, y + 2, sigW, 11),
    format: PdfStringFormat(alignment: PdfTextAlignment.right),
  );
  g.drawString(
    report.meta.preparedByTitle,
    fontSmall,
    brush: PdfSolidBrush(slate),
    bounds: Rect.fromLTWH(sigX, y + 14, sigW, 10),
    format: PdfStringFormat(alignment: PdfTextAlignment.right),
  );

  // ---------------------------------------------------------------------------
  // 5. Page Numbering across all pages
  // ---------------------------------------------------------------------------
  final totalPages = doc.pages.count;
  for (var p = 0; p < totalPages; p++) {
    final pPage = doc.pages[p];
    final pSize = pPage.getClientSize();
    pPage.graphics.drawString(
      'Page ${p + 1} of $totalPages',
      fontSmall,
      brush: PdfSolidBrush(PdfColor(148, 163, 184)), // #94A3B8
      bounds: Rect.fromLTWH(0, pSize.height - 10, pSize.width, 10),
      format: PdfStringFormat(
        alignment: PdfTextAlignment.center,
        lineAlignment: PdfVerticalAlignment.bottom,
      ),
    );
  }

  final bytes = doc.saveSync();
  doc.dispose();
  return Uint8List.fromList(bytes);
}

void _summaryPdfCard(
  PdfGraphics g, {
  required String title,
  required int count,
  required String amount,
  required PdfColor textColor,
  required PdfColor bg,
  required PdfColor borderColor,
  required double x,
  required double y,
  required double w,
}) {
  final titleFont = PdfStandardFont(
    PdfFontFamily.helvetica,
    7,
    style: PdfFontStyle.bold,
  );
  final countFont = PdfStandardFont(
    PdfFontFamily.helvetica,
    16,
    style: PdfFontStyle.bold,
  );
  final amountFont = PdfStandardFont(PdfFontFamily.helvetica, 7.5);

  const cardHeight = 50.0;

  g.drawRectangle(
    brush: PdfSolidBrush(bg),
    pen: PdfPen(borderColor, width: 0.6),
    bounds: Rect.fromLTWH(x, y, w, cardHeight),
  );
  g.drawString(
    title,
    titleFont,
    brush: PdfSolidBrush(textColor),
    bounds: Rect.fromLTWH(x + 10, y + 6, w - 20, 10),
  );
  g.drawString(
    '$count',
    countFont,
    brush: PdfSolidBrush(textColor),
    bounds: Rect.fromLTWH(x + 10, y + 17, w - 20, 18),
  );
  g.drawString(
    'Total Amount: $amount',
    amountFont,
    brush: PdfSolidBrush(textColor),
    bounds: Rect.fromLTWH(x + 10, y + 34, w - 20, 11),
  );
}
