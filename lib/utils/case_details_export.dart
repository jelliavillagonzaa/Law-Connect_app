import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/case_model.dart';
import 'case_description_markup.dart';
import 'case_status_filter.dart';

/// Data shown on Case Details screen — used for PDF / Word export.
class CaseDetailsExportData {
  const CaseDetailsExportData({
    required this.caseModel,
    this.clientName,
    this.clientEmail,
    this.clientPhone,
    this.clientAddress,
    this.attorneyName,
    this.attorneyEmail,
  });

  final CaseModel caseModel;
  final String? clientName;
  final String? clientEmail;
  final String? clientPhone;
  final String? clientAddress;
  final String? attorneyName;
  final String? attorneyEmail;

  String? get resolvedClientName =>
      (clientName?.trim().isNotEmpty == true)
          ? clientName!.trim()
          : (caseModel.clientName?.trim().isNotEmpty == true
              ? caseModel.clientName!.trim()
              : null);

  String? get resolvedClientEmail =>
      (clientEmail?.trim().isNotEmpty == true)
          ? clientEmail!.trim()
          : (caseModel.clientEmail?.trim().isNotEmpty == true
              ? caseModel.clientEmail!.trim()
              : null);

  String? get resolvedClientPhone =>
      (clientPhone?.trim().isNotEmpty == true)
          ? clientPhone!.trim()
          : (caseModel.clientPhone?.trim().isNotEmpty == true
              ? caseModel.clientPhone!.trim()
              : null);

  String? get resolvedClientAddress =>
      (clientAddress?.trim().isNotEmpty == true)
          ? clientAddress!.trim()
          : (caseModel.clientAddress?.trim().isNotEmpty == true
              ? caseModel.clientAddress!.trim()
              : null);

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
      buffer.write(r'\line ');
    } else if (codeUnit < 0x80) {
      buffer.writeCharCode(codeUnit);
    } else {
      final signed = codeUnit > 0x7fff ? codeUnit - 0x10000 : codeUnit;
      buffer.write('\\u$signed?');
    }
  }
  return buffer.toString();
}

String _footerStamp() =>
    DateFormat('MMMM dd, yyyy hh:mm a').format(DateTime.now());

/// Builds the RTF color table from a list of RGB integer values.
/// Colors start at index 4 (indices 1-3 are reserved in the header).
String _rtfColorTable(List<int> colors) {
  final buf = StringBuffer()
    ..write(r'{\colortbl ;')
    ..write(r'\red26\green39\blue68;')   // 1 – navy
    ..write(r'\red236\green238\blue242;') // 2 – bar
    ..write(r'\red90\green98\blue110;');  // 3 – muted
  for (final rgb in colors) {
    final r = (rgb >> 16) & 0xff;
    final g = (rgb >> 8) & 0xff;
    final b = rgb & 0xff;
    buf.write('\\red$r\\green$g\\blue$b;');
  }
  buf.write('}');
  return buf.toString();
}

/// Word file in the same case-sheet layout as the PDF.
Future<Uint8List> buildCaseDetailsWordBytes(CaseDetailsExportData data) async {
  final paragraphs = parseCaseDescription(
    deltaJson: data.caseModel.caseDescriptionDelta,
    plain: data.description,
  );
  final formatted = buildCaseDescriptionRtf(paragraphs);

  final courtText = (data.caseModel.court?.trim().isNotEmpty == true)
      ? data.caseModel.court!.trim()
      : 'REGIONAL TRIAL COURT';
  final regionText = (data.caseModel.courtRegion?.trim().isNotEmpty == true)
      ? data.caseModel.courtRegion!.trim()
      : '10th Judicial Region';
  final branchText = (data.caseModel.courtBranch?.trim().isNotEmpty == true)
      ? data.caseModel.courtBranch!.trim()
      : 'BRANCH 12 - OROQUIETA CITY';
  final courtEmailText = (data.caseModel.courtEmail?.trim().isNotEmpty == true)
      ? data.caseModel.courtEmail!.trim()
      : 'rtc1orq012@judiciary.gov.ph';
  final courtPhoneText = (data.caseModel.courtContact?.trim().isNotEmpty == true)
      ? data.caseModel.courtContact!.trim()
      : '09708694723';

  final clientDisplay = (data.resolvedClientName?.trim().isNotEmpty == true)
      ? data.resolvedClientName!.trim().toUpperCase()
      : (data.caseTitle.trim().isNotEmpty ? data.caseTitle.trim().toUpperCase() : 'PLAINTIFF');
  final oppParty = (data.caseModel.opposingParty?.trim().isNotEmpty == true)
      ? data.caseModel.opposingParty!.trim().toUpperCase()
      : 'DEFENDANTS';
  final caseNo = (data.caseModel.caseNumber?.trim().isNotEmpty == true)
      ? data.caseModel.caseNumber!.trim()
      : (data.caseId.isNotEmpty && data.caseId.length >= 4
          ? 'Civil Case No. ${data.caseId.substring(0, math.min(8, data.caseId.length)).toUpperCase()}'
          : 'Civil Case No. 5297');
  final nature = (data.caseModel.natureOfAction?.trim().isNotEmpty == true)
      ? data.caseModel.natureOfAction!.trim()
      : (data.caseType.trim().isNotEmpty
          ? data.caseType.trim()
          : 'Recovery of Ownership with Possession');

  final attyName = (data.attorneyName?.trim().isNotEmpty == true)
      ? data.attorneyName!.trim().toUpperCase()
      : 'ATTY. APAO';
  final prefixedAtty = attyName.startsWith('ATTY.') ? attyName : 'ATTY. $attyName';

  final rtf = StringBuffer()
    ..write(r'{\rtf1\ansi\deff0')
    ..write(
      r'{\fonttbl{\f0\froman\fcharset0 Times New Roman;}{\f1\fswiss\fcharset0 Arial;}}',
    )
    ..write(_rtfColorTable(formatted.colors))
    ..write(r'\paperw12240\paperh15840\margl1440\margr1440\margt1440\margb1440')
    ..write(r'\f0\fs24');

  // 1. Centered Court Header
  rtf.write(r'\pard\qc\fs22 Republic of the Philippines\par\sa40 ');
  rtf.write(r'\b\fs26 ' + _escapeRtf(courtText.toUpperCase()) + r'\b0\fs22\par\sa40 ');
  rtf.write(_escapeRtf(regionText) + r'\par\sa40 ');
  rtf.write(r'\b ' + _escapeRtf(branchText.toUpperCase()) + r'\b0\par\sa40 ');
  rtf.write(r'\fs20 Email Address: ' + _escapeRtf(courtEmailText) + r'\par\sa40 ');
  rtf.write(r'Contact Number: ' + _escapeRtf(courtPhoneText) + r'\par\sa200\fs24\par ');

  // 2. Caption Table (Two Columns)
  rtf.write(r'\pard\ql\trowd\trgaph100\trleft0\cellx5500\cellx9360');
  rtf.write(r'\intbl\b ' + _escapeRtf(clientDisplay) + r'\b0\par\sa100 ');
  rtf.write(r'\pard\qr Plaintiff,\par\ql\sa120 ');
  rtf.write(r'\pard\qc\i -versus -\i0\par\ql\sa120 ');
  rtf.write(r'\b ' + _escapeRtf(oppParty) + r'\b0\par\sa100 ');
  rtf.write(r'\pard\qr Defendants.\par\ql\cell');

  rtf.write(r'\intbl\pard\ql\sa80 ');
  rtf.write(_escapeRtf(caseNo) + r'\par\sa80 ');
  rtf.write(r'For: ' + _escapeRtf(nature) + r'\par\cell\row');
  rtf.write(r'\pard\ql\par\sa120 ');

  // Separator rule
  rtf.write(r'\pard\qc\fs18 x- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -x\par\fs24\sa240 ');

  // 3. Pleading Title
  rtf.write(r'\pard\qc\b\fs28 ' + _escapeRtf(data.caseTitle.trim().toUpperCase()) + r'\b0\fs24\par\sa240 ');

  // 4. Description
  rtf.write(r'\pard\ql\fi720\sa160 ');
  rtf.write(formatted.body);
  rtf.write(r'\par\sa360 ');

  // 5. Signature Block (Manual pen signature line)
  rtf.write(r'\pard\qr\trowd\trgaph100\trleft4500\cellx9360\intbl\ql ');
  rtf.write(r'Respectfully submitted,\par\sa600 ');
  rtf.write(r'___________________________________________\par\sa60 ');
  rtf.write(r'\b ' + _escapeRtf(prefixedAtty) + r'\b0\par\sa40 ');
  rtf.write(r'Counsel for Plaintiff\par\sa40 ');
  rtf.write(r'Apao Law Office\par\sa40 ');
  rtf.write(r'Oroquieta City, Misamis Occidental\par\sa40 ');
  if (data.attorneyEmail != null && data.attorneyEmail!.trim().isNotEmpty) {
    rtf.write(r'Email: ' + _escapeRtf(data.attorneyEmail!.trim()) + r'\par\sa40 ');
  }
  rtf.write(r'\fs20 Roll of Attorneys No. ___________\par\sa40 ');
  rtf.write(r'IBP Lifetime No. ___________\par\sa40 ');
  rtf.write(r'PTR No. ___________\par\sa40 ');
  rtf.write(r'MCLE Compliance No. ___________\par\cell\row\fs24 ');

  rtf.write(r'\pard\ql\par\sa40\fs18\cf3 ');
  rtf.write(_escapeRtf('Exported: ${_footerStamp()}'));
  rtf.write(r'}');

  return Uint8List.fromList(utf8.encode(rtf.toString()));
}

/// PDF case sheet: Law Connect logo, title bar, two columns, signature.
Future<Uint8List> buildCaseDetailsPdfBytes(CaseDetailsExportData data) async {
  final doc = PdfDocument();
  doc.pageSettings.margins = PdfMargins()..all = 42;

  final ink = PdfColor(28, 32, 38);
  final muted = PdfColor(90, 98, 110);
  final line = PdfColor(55, 65, 82);

  final fontCourtName = PdfStandardFont(
    PdfFontFamily.timesRoman,
    11.5,
    style: PdfFontStyle.bold,
  );
  final fontCourtSub = PdfStandardFont(
    PdfFontFamily.timesRoman,
    10,
  );
  final fontCourtContact = PdfStandardFont(
    PdfFontFamily.timesRoman,
    9.5,
  );
  final fontCaptionTitle = PdfStandardFont(
    PdfFontFamily.timesRoman,
    10.5,
    style: PdfFontStyle.bold,
  );
  final fontCaptionBody = PdfStandardFont(
    PdfFontFamily.timesRoman,
    10,
  );
  final fontCaptionVersus = PdfStandardFont(
    PdfFontFamily.timesRoman,
    10,
    style: PdfFontStyle.italic,
  );
  final fontPleadingTitle = PdfStandardFont(
    PdfFontFamily.timesRoman,
    13,
    style: PdfFontStyle.bold,
  );
  final fontBody = PdfStandardFont(PdfFontFamily.timesRoman, 11);
  final fontSmall = PdfStandardFont(PdfFontFamily.timesRoman, 9);

  PdfPage page = doc.pages.add();
  PdfGraphics g = page.graphics;
  var pageSize = page.getClientSize();
  var y = 0.0;
  final width = pageSize.width;

  void newPageIfNeeded(double needed) {
    if (y + needed <= pageSize.height - 24) return;
    page = doc.pages.add();
    g = page.graphics;
    pageSize = page.getClientSize();
    y = 0;
  }

  List<String> wrapLines(String text, PdfFont font, double maxWidth) {
    final lines = <String>[];
    for (final raw in text.split('\n')) {
      final para = raw.trimRight();
      if (para.trim().isEmpty) {
        lines.add('');
        continue;
      }
      var current = '';
      for (final word in para.split(RegExp(r'\s+'))) {
        final candidate = current.isEmpty ? word : '$current $word';
        if (font.measureString(candidate).width <= maxWidth) {
          current = candidate;
        } else {
          if (current.isNotEmpty) {
            lines.add(current);
            current = '';
          }
          if (font.measureString(word).width > maxWidth) {
            var chunk = '';
            for (var i = 0; i < word.length; i++) {
              final test = '$chunk${word[i]}';
              if (font.measureString(test).width <= maxWidth) {
                chunk = test;
              } else {
                if (chunk.isNotEmpty) lines.add(chunk);
                chunk = word[i];
              }
            }
            current = chunk;
          } else {
            current = word;
          }
        }
      }
      if (current.isNotEmpty) lines.add(current);
    }
    return lines;
  }

  void drawCentered(String text, PdfFont font, PdfColor color, {double spacing = 13.5}) {
    final lines = wrapLines(text, font, width);
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) continue;
      newPageIfNeeded(font.height + 3);
      final textW = font.measureString(line).width;
      final x = math.max(0.0, (width - textW) / 2);
      g.drawString(
        line,
        font,
        brush: PdfSolidBrush(color),
        bounds: ui.Rect.fromLTWH(x, y, math.min(textW + 4, width), font.height + 2),
      );
      if (i < lines.length - 1) {
        y += font.height + 2;
      }
    }
    y += spacing;
  }

  // ── 1. Official Philippine Court Pleading Header (Centered) ─────────────
  drawCentered('Republic of the Philippines', fontCourtSub, ink, spacing: 13);
  final courtText = (data.caseModel.court?.trim().isNotEmpty == true)
      ? data.caseModel.court!.trim()
      : 'REGIONAL TRIAL COURT';
  drawCentered(courtText.toUpperCase(), fontCourtName, ink, spacing: 13);

  final regionText = (data.caseModel.courtRegion?.trim().isNotEmpty == true)
      ? data.caseModel.courtRegion!.trim()
      : '10th Judicial Region';
  drawCentered(regionText, fontCourtSub, ink, spacing: 13);

  final branchText = (data.caseModel.courtBranch?.trim().isNotEmpty == true)
      ? data.caseModel.courtBranch!.trim()
      : 'BRANCH 12 - OROQUIETA CITY';
  drawCentered(branchText.toUpperCase(), fontCourtName, ink, spacing: 13);

  final courtEmailText = (data.caseModel.courtEmail?.trim().isNotEmpty == true)
      ? data.caseModel.courtEmail!.trim()
      : 'rtc1orq012@judiciary.gov.ph';
  drawCentered('Email Address: $courtEmailText', fontCourtContact, ink, spacing: 12);

  final courtPhoneText = (data.caseModel.courtContact?.trim().isNotEmpty == true)
      ? data.caseModel.courtContact!.trim()
      : '09708694723';
  drawCentered('Contact Number: $courtPhoneText', fontCourtContact, ink, spacing: 18);

  // ── 2. Pleading Caption (Two-Column Layout) ──────────────────────────────
  final captionStartY = y;
  final leftColW = width * 0.54;
  final rightColX = width * 0.58;
  final rightColW = width - rightColX;

  // Left Column: Plaintiff
  final clientDisplay = (data.resolvedClientName?.trim().isNotEmpty == true)
      ? data.resolvedClientName!.trim()
      : (data.caseTitle.trim().isNotEmpty ? data.caseTitle.trim() : 'PLAINTIFF');
  final clientLines = wrapLines(clientDisplay.toUpperCase(), fontCaptionTitle, leftColW);
  for (final lineText in clientLines) {
    g.drawString(
      lineText,
      fontCaptionTitle,
      brush: PdfSolidBrush(ink),
      bounds: ui.Rect.fromLTWH(0, y, leftColW, fontCaptionTitle.height + 2),
    );
    y += fontCaptionTitle.height + 2;
  }
  y += 2;
  g.drawString(
    'Plaintiff,',
    fontCaptionBody,
    brush: PdfSolidBrush(ink),
    bounds: ui.Rect.fromLTWH(leftColW - 75, y, 75, 14),
  );
  y += 18;

  // -versus -
  final versusW = fontCaptionVersus.measureString('-versus -').width;
  g.drawString(
    '-versus -',
    fontCaptionVersus,
    brush: PdfSolidBrush(ink),
    bounds: ui.Rect.fromLTWH((leftColW - versusW) / 2, y, versusW + 4, 14),
  );
  y += 18;

  // Left Column: Defendants
  final oppParty = (data.caseModel.opposingParty?.trim().isNotEmpty == true)
      ? data.caseModel.opposingParty!.trim().toUpperCase()
      : 'DEFENDANTS';
  final oppLines = wrapLines(oppParty, fontCaptionTitle, leftColW);
  for (final lineText in oppLines) {
    g.drawString(
      lineText,
      fontCaptionTitle,
      brush: PdfSolidBrush(ink),
      bounds: ui.Rect.fromLTWH(0, y, leftColW, fontCaptionTitle.height + 2),
    );
    y += fontCaptionTitle.height + 2;
  }
  y += 2;
  g.drawString(
    'Defendants.',
    fontCaptionBody,
    brush: PdfSolidBrush(ink),
    bounds: ui.Rect.fromLTWH(leftColW - 80, y, 80, 14),
  );
  y += 18;

  final leftEndY = y;

  // Right Column: Civil Case No. & For: Nature of Action
  var rightY = captionStartY + 4;
  final caseNo = (data.caseModel.caseNumber?.trim().isNotEmpty == true)
      ? data.caseModel.caseNumber!.trim()
      : (data.caseId.isNotEmpty && data.caseId.length >= 4
          ? 'Civil Case No. ${data.caseId.substring(0, math.min(8, data.caseId.length)).toUpperCase()}'
          : 'Civil Case No. 5297');
  final caseNoLines = wrapLines(caseNo, fontCaptionBody, rightColW);
  for (final lineText in caseNoLines) {
    g.drawString(
      lineText,
      fontCaptionBody,
      brush: PdfSolidBrush(ink),
      bounds: ui.Rect.fromLTWH(rightColX, rightY, rightColW, fontCaptionBody.height + 2),
    );
    rightY += fontCaptionBody.height + 2;
  }
  rightY += 2;

  final nature = (data.caseModel.natureOfAction?.trim().isNotEmpty == true)
      ? data.caseModel.natureOfAction!.trim()
      : (data.caseType.trim().isNotEmpty
          ? data.caseType.trim()
          : 'Recovery of Ownership with Possession');
  final natureLines = wrapLines('For: $nature', fontCaptionBody, rightColW);
  for (final lineText in natureLines) {
    g.drawString(
      lineText,
      fontCaptionBody,
      brush: PdfSolidBrush(ink),
      bounds: ui.Rect.fromLTWH(rightColX, rightY, rightColW, fontCaptionBody.height + 2),
    );
    rightY += fontCaptionBody.height + 2;
  }

  y = math.max(leftEndY, rightY) + 6;

  // x-------------------------------------------------------------------------x
  final dashW = fontSmall.measureString('- ').width;
  final xW = fontSmall.measureString('x').width;
  final dashCount = math.max(10, ((width - (xW * 2)) / dashW).floor());
  final separatorText = 'x${'- ' * dashCount}x';
  g.drawString(
    separatorText,
    fontSmall,
    brush: PdfSolidBrush(ink),
    bounds: ui.Rect.fromLTWH(0, y, width, 12),
  );
  y += 20;

  // ── 3. Pleading Title (Centered, wrapped) ─────────────────────────────────
  final pleadingTitle = data.caseTitle.trim().toUpperCase();
  final titleLines = wrapLines(pleadingTitle, fontPleadingTitle, width);
  for (final line in titleLines) {
    if (line.isEmpty) continue;
    newPageIfNeeded(fontPleadingTitle.height + 4);
    final lineW = fontPleadingTitle.measureString(line).width;
    final lineX = math.max(0.0, (width - lineW) / 2);
    g.drawString(
      line,
      fontPleadingTitle,
      brush: PdfSolidBrush(ink),
      bounds: ui.Rect.fromLTWH(
        lineX,
        y,
        math.min(lineW + 4, width),
        fontPleadingTitle.height + 2,
      ),
    );
    y += fontPleadingTitle.height + 3;
  }
  y += 14;

  // ── 4. Case Description ───────────────────────────────────────────────────
  _paintFormattedDescription(
    paragraphs: parseCaseDescription(
      deltaJson: data.caseModel.caseDescriptionDelta,
      plain: data.description,
    ),
    width: width,
    ink: ink,
    fontBody: fontBody,
    newPageIfNeeded: newPageIfNeeded,
    graphics: () => g,
    readY: () => y,
    writeY: (value) => y = value,
  );
  y += 24;

  // ── 5. Attorney Signature Block (Manual Wet Signing) ─────────────────────
  newPageIfNeeded(150);
  const sigBlockW = 260.0;
  final sigBlockX = width - sigBlockW;

  g.drawString(
    'Respectfully submitted,',
    fontCaptionBody,
    brush: PdfSolidBrush(ink),
    bounds: ui.Rect.fromLTWH(sigBlockX, y, sigBlockW, 14),
  );
  y += 44; // Ample space for attorney's manual pen signature!

  // Signature line (no digital e-signature image)
  g.drawLine(
    PdfPen(ink, width: 1.0),
    ui.Offset(sigBlockX, y),
    ui.Offset(sigBlockX + sigBlockW, y),
  );
  y += 6;

  final attyName = (data.attorneyName?.trim().isNotEmpty == true)
      ? data.attorneyName!.trim().toUpperCase()
      : 'ATTY. APAO';
  final prefixedAtty = attyName.startsWith('ATTY.') ? attyName : 'ATTY. $attyName';
  g.drawString(
    prefixedAtty,
    fontCaptionTitle,
    brush: PdfSolidBrush(ink),
    bounds: ui.Rect.fromLTWH(sigBlockX, y, sigBlockW, 14),
  );
  y += 14;
  g.drawString(
    'Counsel for Plaintiff',
    fontCaptionBody,
    brush: PdfSolidBrush(ink),
    bounds: ui.Rect.fromLTWH(sigBlockX, y, sigBlockW, 13),
  );
  y += 13;
  g.drawString(
    'Apao Law Office',
    fontCaptionBody,
    brush: PdfSolidBrush(ink),
    bounds: ui.Rect.fromLTWH(sigBlockX, y, sigBlockW, 13),
  );
  y += 13;
  g.drawString(
    'Oroquieta City, Misamis Occidental',
    fontCaptionBody,
    brush: PdfSolidBrush(ink),
    bounds: ui.Rect.fromLTWH(sigBlockX, y, sigBlockW, 13),
  );
  y += 13;
  if (data.attorneyEmail != null && data.attorneyEmail!.trim().isNotEmpty) {
    g.drawString(
      'Email: ${data.attorneyEmail!.trim()}',
      fontSmall,
      brush: PdfSolidBrush(ink),
      bounds: ui.Rect.fromLTWH(sigBlockX, y, sigBlockW, 12),
    );
    y += 12;
  }
  g.drawString(
    'Roll of Attorneys No. ___________',
    fontSmall,
    brush: PdfSolidBrush(ink),
    bounds: ui.Rect.fromLTWH(sigBlockX, y, sigBlockW, 12),
  );
  y += 12;
  g.drawString(
    'IBP Lifetime No. ___________',
    fontSmall,
    brush: PdfSolidBrush(ink),
    bounds: ui.Rect.fromLTWH(sigBlockX, y, sigBlockW, 12),
  );
  y += 12;
  g.drawString(
    'PTR No. ___________',
    fontSmall,
    brush: PdfSolidBrush(ink),
    bounds: ui.Rect.fromLTWH(sigBlockX, y, sigBlockW, 12),
  );
  y += 12;
  g.drawString(
    'MCLE Compliance No. ___________',
    fontSmall,
    brush: PdfSolidBrush(ink),
    bounds: ui.Rect.fromLTWH(sigBlockX, y, sigBlockW, 12),
  );
  y += 16;

  newPageIfNeeded(32);
  y += 6;
  g.drawLine(PdfPen(line, width: 0.8), ui.Offset(0, y), ui.Offset(width, y));
  y += 8;
  g.drawString(
    'Exported: ${_footerStamp()}',
    fontSmall,
    brush: PdfSolidBrush(muted),
    bounds: ui.Rect.fromLTWH(0, y, width, 12),
  );
  y += 13;
  g.drawString(
    'Law Connect  Case Details Report',
    fontSmall,
    brush: PdfSolidBrush(muted),
    bounds: ui.Rect.fromLTWH(0, y, width, 12),
  );

  final bytes = Uint8List.fromList(await doc.save());
  doc.dispose();
  return bytes;
}

/// Renders [paragraphs] onto the current PDF page, handling word-wrap,
/// font styles, indentation, list markers, and automatic page breaks.
///
/// [graphics] and [readY]/[writeY] are callbacks so this function can keep
/// writing after [newPageIfNeeded] switches to a new page.
void _paintFormattedDescription({
  required List<CaseTextParagraph> paragraphs,
  required double width,
  required PdfColor ink,
  required PdfStandardFont fontBody,
  required void Function(double needed) newPageIfNeeded,
  required PdfGraphics Function() graphics,
  required double Function() readY,
  required void Function(double value) writeY,
}) {
  if (paragraphs.isEmpty || paragraphs.every((p) => p.isBlank)) {
    // Draw an em-dash placeholder when there is no content.
    newPageIfNeeded(fontBody.height + 6);
    graphics().drawString(
      '—',
      fontBody,
      brush: PdfSolidBrush(ink),
      bounds: ui.Rect.fromLTWH(0, readY(), width, fontBody.height + 2),
    );
    writeY(readY() + fontBody.height + 6);
    return;
  }

  // Helper: pick a PdfStandardFont matching the bold/italic combination.
  // Note: Syncfusion PDF doesn't have a combined boldItalic enum value,
  // so bold takes priority when both flags are set.
  PdfStandardFont styleFont(bool bold, bool italic) {
    if (bold) {
      return PdfStandardFont(
        PdfFontFamily.helvetica,
        fontBody.size,
        style: PdfFontStyle.bold,
      );
    } else if (italic) {
      return PdfStandardFont(
        PdfFontFamily.helvetica,
        fontBody.size,
        style: PdfFontStyle.italic,
      );
    }
    return fontBody;
  }

  // Helper: word-wrap a single string to fit [maxWidth].
  List<String> wrapText(String text, PdfFont font, double maxWidth) {
    final lines = <String>[];
    for (final raw in text.split('\n')) {
      final para = raw.trimRight();
      if (para.trim().isEmpty) {
        lines.add('');
        continue;
      }
      var current = '';
      for (final word in para.split(RegExp(r'\s+'))) {
        final candidate = current.isEmpty ? word : '$current $word';
        if (font.measureString(candidate).width <= maxWidth) {
          current = candidate;
        } else {
          if (current.isNotEmpty) {
            lines.add(current);
            current = '';
          }
          if (font.measureString(word).width > maxWidth) {
            var chunk = '';
            for (var i = 0; i < word.length; i++) {
              final test = '$chunk${word[i]}';
              if (font.measureString(test).width <= maxWidth) {
                chunk = test;
              } else {
                if (chunk.isNotEmpty) lines.add(chunk);
                chunk = word[i];
              }
            }
            current = chunk;
          } else {
            current = word;
          }
        }
      }
      if (current.isNotEmpty) lines.add(current);
    }
    return lines;
  }

  const lineSpacing = 3.0;
  const indentStep = 18.0;
  var orderedCounter = 0;

  for (final paragraph in paragraphs) {
    if (paragraph.list == 'ordered') {
      orderedCounter++;
    } else {
      orderedCounter = 0;
    }

    // Build the full plain text of the paragraph for wrapping purposes.
    final plainText = paragraph.runs.map((r) => r.text).join();
    if (plainText.trim().isEmpty) {
      // Blank paragraph = small vertical gap.
      writeY(readY() + fontBody.height * 0.5);
      continue;
    }

    // Compute indent and optional list prefix.
    final levels =
        paragraph.indent + (paragraph.list != null ? 1 : 0) + (paragraph.quote ? 1 : 0);
    final xOffset = levels * indentStep;
    final usableWidth = width - xOffset;

    // Determine list marker string.
    String marker = '';
    if (paragraph.list == 'bullet') {
      marker = '• ';
    } else if (paragraph.list == 'ordered' && orderedCounter > 0) {
      marker = '$orderedCounter. ';
    }

    // Use the first run's style as the representative style for the paragraph.
    final firstRun = paragraph.runs.isNotEmpty ? paragraph.runs.first : null;
    final isBold = firstRun?.bold == true || paragraph.header > 0;
    final isItalic = firstRun?.italic == true;
    final font = styleFont(isBold, isItalic);

    // Compute font size (headers are larger).
    final fontSize = switch (paragraph.header) {
      1 => 16.0,
      2 => 14.0,
      3 => 12.5,
      _ => fontBody.size,
    };
    final usedFont = fontSize != fontBody.size
        ? PdfStandardFont(
            isBold ? PdfFontFamily.helvetica : PdfFontFamily.helvetica,
            fontSize,
            style: isBold ? PdfFontStyle.bold : PdfFontStyle.regular,
          )
        : font;

    // Wrap the text.
    final markerWidth =
        marker.isNotEmpty ? usedFont.measureString(marker).width : 0.0;
    final textWidth = usableWidth - markerWidth;
    final wrappedLines = wrapText(plainText, usedFont, textWidth.clamp(60, usableWidth));
    final lineH = usedFont.height + lineSpacing;
    final blockH = wrappedLines.length * lineH + 4;

    newPageIfNeeded(blockH);

    var y = readY();
    final g = graphics();

    for (var i = 0; i < wrappedLines.length; i++) {
      final lineText = wrappedLines[i];
      var drawX = xOffset;

      // Draw list marker on the first line only.
      if (i == 0 && marker.isNotEmpty) {
        g.drawString(
          marker,
          usedFont,
          brush: PdfSolidBrush(ink),
          bounds: ui.Rect.fromLTWH(drawX, y, markerWidth + 2, lineH),
        );
        drawX += markerWidth;
      } else if (marker.isNotEmpty) {
        drawX += markerWidth;
      }

      if (lineText.isNotEmpty) {
        g.drawString(
          lineText,
          usedFont,
          brush: PdfSolidBrush(ink),
          bounds: ui.Rect.fromLTWH(drawX, y, textWidth + 2, lineH),
        );
      }

      // Underline — drawn manually since PdfStandardFont doesn't expose underline style.
      if (firstRun?.underline == true) {
        final lineW = usedFont.measureString(lineText).width;
        g.drawLine(
          PdfPen(ink, width: 0.7),
          ui.Offset(drawX, y + usedFont.height + 1),
          ui.Offset(drawX + lineW, y + usedFont.height + 1),
        );
      }

      y += lineH;
    }

    writeY(y + 2);
  }
}
