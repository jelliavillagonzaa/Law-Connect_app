import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/case_model.dart';
import 'case_history.dart';
import 'case_result.dart';
import 'case_status_filter.dart';

/// Data shown on Case Details screen — used for PDF / Word export.
class CaseDetailsExportData {
  const CaseDetailsExportData({
    required this.caseModel,
    this.clientName,
    this.clientEmail,
    this.attorneyName,
    this.attorneyEmail,
  });

  final CaseModel caseModel;
  final String? clientName;
  final String? clientEmail;
  final String? attorneyName;
  final String? attorneyEmail;

  String get caseTitle => caseModel.caseTitle;
  String get status => CaseStatusFilter.statusLabel(caseModel.status);
  String get caseType => caseModel.caseType;
  String get description => caseModel.caseDescription;
  String get caseId => caseModel.id;

  String get createdLabel =>
      DateFormat('d/M/yyyy').format(caseModel.createdAt);

  String get updatedLabel =>
      DateFormat('d/M/yyyy').format(caseModel.updatedAt);

  String get exportedAtLabel =>
      DateFormat('MMMM dd, yyyy • hh:mm a').format(DateTime.now());

  String safeFilenameStem() {
    final slug = caseTitle
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    return 'case_details_${slug.isEmpty ? caseId : slug}_$date';
  }
}

String _escapeRtf(String text) {
  final buffer = StringBuffer();
  for (final codeUnit in text.runes) {
    if (codeUnit == 0x5c) {
      buffer.write(r'\\');
    } else if (codeUnit == 0x7b) {
      buffer.write(r'\{');
    } else if (codeUnit == 0x7d) {
      buffer.write(r'\}');
    } else if (codeUnit == 0x0a) {
      buffer.write(r'\par ');
    } else if (codeUnit < 0x80) {
      buffer.writeCharCode(codeUnit);
    } else {
      final signed = codeUnit > 0x7fff ? codeUnit - 0x10000 : codeUnit;
      buffer.write('\\u$signed?');
    }
  }
  return buffer.toString();
}

List<String> _exportLines(CaseDetailsExportData data) {
  final lines = <String>[
    'CASE DETAILS',
    '',
    data.caseTitle,
    'Status: ${data.status}',
    if (CaseStatusFilter.isCompleted(data.caseModel.status) &&
        CaseResult.label(data.caseModel.caseResult).isNotEmpty)
      'Result: ${CaseResult.label(data.caseModel.caseResult)}',
    '',
    'Case Type: ${data.caseType}',
    if (data.caseModel.opposingParty != null &&
        data.caseModel.opposingParty!.trim().isNotEmpty)
      'Opposing Party: ${data.caseModel.opposingParty!.trim()}',
    'Created: ${data.createdLabel}',
    'Last Updated: ${data.updatedLabel}',
    'Case ID: ${data.caseId}',
  ];

  if (data.clientName != null && data.clientName!.trim().isNotEmpty) {
    lines.add('Client: ${data.clientName!.trim()}');
    if (data.clientEmail != null && data.clientEmail!.trim().isNotEmpty) {
      lines.add('Client Email: ${data.clientEmail!.trim()}');
    }
  }

  if (data.attorneyName != null && data.attorneyName!.trim().isNotEmpty) {
    lines.add('Attorney: ${data.attorneyName!.trim()}');
    if (data.attorneyEmail != null && data.attorneyEmail!.trim().isNotEmpty) {
      lines.add('Attorney Email: ${data.attorneyEmail!.trim()}');
    }
  }

  lines.addAll([
    '',
    'Case History',
    ...CaseHistory.fromCase(data.caseModel).map((event) {
      final date = event.dateLabel;
      return date.isEmpty ? event.label : '${event.label} — $date';
    }),
    '',
    'Description',
    data.description.trim().isEmpty ? '—' : data.description.trim(),
    '',
    'Exported: ${data.exportedAtLabel}',
    '',
    'Law Connect — Case Details Report',
  ]);

  return lines;
}

/// Word-compatible RTF document.
Uint8List buildCaseDetailsWordBytes(CaseDetailsExportData data) {
  final lines = _exportLines(data);
  final rtf = StringBuffer()
    ..write(r'{\rtf1\ansi\deff0{\fonttbl{\f0\fswiss Arial;}}')
    ..write(r'\f0\fs24');

  for (final line in lines) {
    if (line.isEmpty) {
      rtf.write(r'\par');
      continue;
    }
    if (line == 'CASE DETAILS' ||
        line == 'Description' ||
        line == 'Case History' ||
        line == data.caseTitle) {
      rtf.write(r'\b ');
      rtf.write(_escapeRtf(line));
      rtf.write(r'\b0\par');
      if (line == 'Description') {
        rtf.write(r'\par');
      }
    } else {
      rtf.write(_escapeRtf(line));
      rtf.write(r'\par');
    }
  }

  rtf.write('}');
  return Uint8List.fromList(utf8.encode(rtf.toString()));
}

/// PDF document matching on-screen case details.
Future<Uint8List> buildCaseDetailsPdfBytes(CaseDetailsExportData data) async {
  final doc = PdfDocument();
  doc.pageSettings.margins = PdfMargins()..all = 40;

  final navy = PdfColor(26, 39, 68);
  final muted = PdfColor(100, 100, 100);
  final border = PdfColor(220, 220, 220);
  final lightBg = PdfColor(248, 249, 252);

  final fontHeading = PdfStandardFont(
    PdfFontFamily.helvetica,
    14,
    style: PdfFontStyle.bold,
  );
  final fontLabel = PdfStandardFont(
    PdfFontFamily.helvetica,
    10,
    style: PdfFontStyle.bold,
  );
  final fontBody = PdfStandardFont(PdfFontFamily.helvetica, 11);
  final fontSmall = PdfStandardFont(PdfFontFamily.helvetica, 9);

  PdfPage page = doc.pages.add();
  PdfGraphics g = page.graphics;
  var pageSize = page.getClientSize();
  var y = 0.0;
  const hPad = 0.0;
  final contentWidth = pageSize.width;

  void newPageIfNeeded(double needed) {
    if (y + needed <= pageSize.height - 36) return;
    page = doc.pages.add();
    g = page.graphics;
    pageSize = page.getClientSize();
    y = 0;
  }

  /// Draws [text] and returns the vertical space consumed (including [afterGap]).
  double drawBlock(
    String text,
    PdfFont font, {
    double afterGap = 12,
    PdfBrush? brush,
    double? maxWidth,
    bool wrap = true,
  }) {
    final w = maxWidth ?? contentWidth;
    final format = PdfStringFormat(
      wordWrap: wrap ? PdfWordWrapType.word : PdfWordWrapType.none,
      lineAlignment: PdfVerticalAlignment.top,
    );
    final measured = font.measureString(
      text,
      format: format,
      layoutArea: Size(w, pageSize.height),
    );
    final blockH = measured.height + 4;
    newPageIfNeeded(blockH + afterGap);
    g.drawString(
      text,
      font,
      brush: brush ?? PdfSolidBrush(PdfColor(30, 30, 30)),
      bounds: Rect.fromLTWH(hPad, y, w, blockH),
      format: format,
    );
    y += blockH + afterGap;
    return blockH + afterGap;
  }

  void drawDivider({double gap = 14}) {
    newPageIfNeeded(gap + 2);
    g.drawLine(
      PdfPen(border, width: 0.8),
      Offset(hPad, y),
      Offset(hPad + contentWidth, y),
    );
    y += gap;
  }

  // ── Header band ──
  g.drawRectangle(
    brush: PdfSolidBrush(navy),
    bounds: Rect.fromLTWH(0, y, pageSize.width, 36),
  );
  g.drawString(
    'CASE DETAILS',
    PdfStandardFont(PdfFontFamily.helvetica, 14, style: PdfFontStyle.bold),
    brush: PdfSolidBrush(PdfColor(255, 255, 255)),
    bounds: Rect.fromLTWH(hPad, y + 10, contentWidth, 18),
  );
  y += 48;

  // ── Case title + status ──
  drawBlock(data.caseTitle, fontHeading, afterGap: 8, wrap: true);
  drawBlock('Status: ${data.status}', fontBody, afterGap: 16);

  drawDivider();

  // ── Metadata ──
  final metaRows = <(String, String)>[
    ('Case Type', data.caseType),
    if (CaseStatusFilter.isCompleted(data.caseModel.status) &&
        CaseResult.label(data.caseModel.caseResult).isNotEmpty)
      ('Result', CaseResult.label(data.caseModel.caseResult)),
    ('Created', data.createdLabel),
    ('Last Updated', data.updatedLabel),
    ('Case ID', data.caseId),
  ];
  if (data.clientName != null && data.clientName!.trim().isNotEmpty) {
    metaRows.add(('Client', data.clientName!.trim()));
    if (data.clientEmail != null && data.clientEmail!.trim().isNotEmpty) {
      metaRows.add(('Client Email', data.clientEmail!.trim()));
    }
  }
  if (data.attorneyName != null && data.attorneyName!.trim().isNotEmpty) {
    metaRows.add(('Attorney', data.attorneyName!.trim()));
    if (data.attorneyEmail != null && data.attorneyEmail!.trim().isNotEmpty) {
      metaRows.add(('Attorney Email', data.attorneyEmail!.trim()));
    }
  }

  for (final (label, value) in metaRows) {
    newPageIfNeeded(22);
    g.drawString(
      '$label:',
      fontLabel,
      brush: PdfSolidBrush(muted),
      bounds: Rect.fromLTWH(hPad, y, 100, 14),
    );
    final format = PdfStringFormat(wordWrap: PdfWordWrapType.word);
    final valueSize = fontBody.measureString(
      value,
      format: format,
      layoutArea: Size(contentWidth - 108, pageSize.height),
    );
    g.drawString(
      value,
      fontBody,
      bounds: Rect.fromLTWH(hPad + 108, y, contentWidth - 108, valueSize.height + 2),
      format: format,
    );
    y += valueSize.height + 10;
  }

  y += 4;
  drawDivider();

  // ── Description section ──
  newPageIfNeeded(40);
  drawBlock('Description', fontHeading, afterGap: 10, wrap: false);

  final desc = data.description.trim().isEmpty ? '—' : data.description.trim();
  final descFormat = PdfStringFormat(wordWrap: PdfWordWrapType.word);
  final descSize = fontBody.measureString(
    desc,
    format: descFormat,
    layoutArea: Size(contentWidth - 24, pageSize.height),
  );
  final boxH = descSize.height + 20;
  newPageIfNeeded(boxH + 24);

  g.drawRectangle(
    brush: PdfSolidBrush(lightBg),
    pen: PdfPen(border, width: 0.6),
    bounds: Rect.fromLTWH(hPad, y, contentWidth, boxH),
  );
  g.drawString(
    desc,
    fontBody,
    brush: PdfSolidBrush(PdfColor(40, 40, 40)),
    bounds: Rect.fromLTWH(hPad + 12, y + 10, contentWidth - 24, descSize.height + 4),
    format: descFormat,
  );
  y += boxH + 20;

  // ── Footer ──
  drawDivider(gap: 10);
  drawBlock(
    'Exported: ${data.exportedAtLabel}',
    fontSmall,
    brush: PdfSolidBrush(muted),
    afterGap: 6,
    wrap: false,
  );
  drawBlock(
    'Law Connect — Case Details Report',
    fontSmall,
    brush: PdfSolidBrush(muted),
    afterGap: 0,
    wrap: false,
  );

  final bytes = Uint8List.fromList(await doc.save());
  doc.dispose();
  return bytes;
}
