import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/task_model.dart';

enum StaffTaskReportKind { summary, completed }

class StaffTaskReportData {
  const StaffTaskReportData({
    required this.kind,
    required this.preparedBy,
    required this.generatedAt,
    required this.totalTasks,
    required this.completedCount,
    required this.inProgressCount,
    required this.pendingCount,
    required this.tasks,
  });

  final StaffTaskReportKind kind;
  final String preparedBy;
  final DateTime generatedAt;
  final int totalTasks;
  final int completedCount;
  final int inProgressCount;
  final int pendingCount;
  final List<TaskModel> tasks;

  String get reportTitle => kind == StaffTaskReportKind.summary
      ? 'Task Summary Report'
      : 'Completed Tasks Report';

  String get exportedAtLabel =>
      DateFormat('MMMM dd, yyyy • hh:mm a').format(generatedAt);

  String safeFilenameStem() {
    final date = DateFormat('yyyyMMdd').format(generatedAt);
    return kind == StaffTaskReportKind.summary
        ? 'task_summary_$date'
        : 'completed_tasks_$date';
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'Pending';
    case 'in_progress':
      return 'In Progress';
    case 'completed':
      return 'Completed';
    default:
      return status.replaceAll('_', ' ');
  }
}

String _priorityLabel(int? priority) {
  switch (priority) {
    case 1:
    case 2:
      return 'High';
    case 4:
      return 'Low';
    case 3:
    default:
      return 'Normal';
  }
}

String _fmtDate(DateTime? value) {
  if (value == null) return '-';
  return DateFormat('MMM dd, yyyy').format(value);
}

String _clean(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return '-';
  return text.replaceAll(RegExp(r'\s+'), ' ');
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

Uint8List buildStaffTaskReportWordBytes(StaffTaskReportData data) {
  final isCompleted = data.kind == StaffTaskReportKind.completed;
  final headers = isCompleted
      ? ['No.', 'Task', 'Description', 'Priority', 'Due Date', 'Completed']
      : ['No.', 'Task', 'Status', 'Priority', 'Due Date', 'Completed'];
  const widths = [900, 3200, 2000, 1400, 1600, 1700];

  String tableRow(List<String> cells, {bool header = false}) {
    final b = StringBuffer(r'\trowd\trgaph70\trpaddl80\trpaddr80');
    var x = 0;
    for (final w in widths) {
      x += w;
      if (header) {
        b.write(r'\clcbpat1');
      }
      b.write(
        r'\clvertalc\clbrdrt\brdrs\brdrw10\clbrdrl\brdrs\brdrw10'
        r'\clbrdrb\brdrs\brdrw10\clbrdrr\brdrs\brdrw10',
      );
      b.write('\\cellx$x');
    }
    for (final cell in cells) {
      if (header) b.write(r'\b ');
      b.write(r'\intbl ');
      b.write(_escapeRtf(cell));
      if (header) b.write(r'\b0 ');
      b.write(r'\cell');
    }
    b.write(r'\row');
    return b.toString();
  }

  final rtf = StringBuffer()
    ..write(r'{\rtf1\ansi\deff0')
    ..write(r'{\fonttbl{\f0\fswiss Arial;}}')
    ..write(r'{\colortbl;\red26\green39\blue68;}')
    ..write(r'\f0\fs22')
    ..write(r'\b\fs32 ')
    ..write(_escapeRtf(data.reportTitle))
    ..write(r'\b0\fs22\par')
    ..write(r'\par')
    ..write(_escapeRtf('Law Connect  |  Staff Task Report'))
    ..write(r'\par')
    ..write(_escapeRtf('Prepared by: ${data.preparedBy}'))
    ..write(r'\par')
    ..write(_escapeRtf('Generated: ${data.exportedAtLabel}'))
    ..write(r'\par\par')
    ..write(r'\b SUMMARY\b0\par\par')
    ..write(
      _escapeRtf(
        'Total Tasks: ${data.totalTasks}    '
        'Completed: ${data.completedCount}    '
        'In Progress: ${data.inProgressCount}    '
        'Pending: ${data.pendingCount}',
      ),
    )
    ..write(r'\par\par')
    ..write(r'\b ')
    ..write(
      _escapeRtf(
        isCompleted
            ? 'Completed Tasks (${data.tasks.length})'
            : 'All Tasks (${data.tasks.length})',
      ),
    )
    ..write(r'\b0\par\par')
    ..write(tableRow(headers, header: true));

  if (data.tasks.isEmpty) {
    rtf.write(
      tableRow(
        isCompleted
            ? ['-', 'No completed tasks', '-', '-', '-', '-']
            : ['-', 'No tasks assigned', '-', '-', '-', '-'],
      ),
    );
  } else {
    for (var i = 0; i < data.tasks.length; i++) {
      final task = data.tasks[i];
      final cells = isCompleted
          ? [
              '${i + 1}',
              _clean(task.title),
              _clean(task.description),
              _priorityLabel(task.priority),
              _fmtDate(task.dueDate),
              _fmtDate(task.completedAt),
            ]
          : [
              '${i + 1}',
              _clean(task.title),
              _statusLabel(task.status),
              _priorityLabel(task.priority),
              _fmtDate(task.dueDate),
              task.status == 'completed' ? _fmtDate(task.completedAt) : '-',
            ];
      rtf.write(tableRow(cells));
    }
  }

  rtf.write('}');
  return Uint8List.fromList(utf8.encode(rtf.toString()));
}

Future<Uint8List> buildStaffTaskReportPdfBytes(StaffTaskReportData data) async {
  final doc = PdfDocument();
  doc.pageSettings.orientation = PdfPageOrientation.landscape;
  final margins = PdfMargins()..all = 28;
  doc.pageSettings.margins = margins;

  final navy = PdfColor(26, 39, 68);
  final muted = PdfColor(90, 90, 90);
  final border = PdfColor(210, 214, 220);
  final lightBg = PdfColor(248, 249, 252);
  final cardBg = PdfColor(245, 247, 250);

  final fontTitle = PdfStandardFont(
    PdfFontFamily.helvetica,
    16,
    style: PdfFontStyle.bold,
  );
  final fontSection = PdfStandardFont(
    PdfFontFamily.helvetica,
    11,
    style: PdfFontStyle.bold,
  );
  final fontBold = PdfStandardFont(
    PdfFontFamily.helvetica,
    8,
    style: PdfFontStyle.bold,
  );
  final font = PdfStandardFont(PdfFontFamily.helvetica, 8);
  final fontSmall = PdfStandardFont(PdfFontFamily.helvetica, 8);

  final page = doc.pages.add();
  final g = page.graphics;
  final size = page.getClientSize();
  var y = 0.0;

  g.drawRectangle(
    brush: PdfSolidBrush(navy),
    bounds: Rect.fromLTWH(0, y, size.width, 42),
  );
  g.drawString(
    'LAW CONNECT',
    PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.bold),
    brush: PdfBrushes.white,
    bounds: Rect.fromLTWH(16, y + 8, size.width * 0.4, 14),
  );
  g.drawString(
    'Staff Task Report',
    fontSmall,
    brush: PdfSolidBrush(PdfColor(200, 210, 230)),
    bounds: Rect.fromLTWH(16, y + 22, size.width * 0.4, 12),
  );
  g.drawString(
    data.reportTitle.toUpperCase(),
    fontTitle,
    brush: PdfBrushes.white,
    bounds: Rect.fromLTWH(size.width * 0.38, y + 6, size.width * 0.62 - 16, 20),
    format: PdfStringFormat(alignment: PdfTextAlignment.right),
  );
  g.drawString(
    'Prepared by: ${data.preparedBy}',
    fontSmall,
    brush: PdfSolidBrush(PdfColor(220, 226, 236)),
    bounds: Rect.fromLTWH(size.width * 0.38, y + 24, size.width * 0.62 - 16, 12),
    format: PdfStringFormat(alignment: PdfTextAlignment.right),
  );
  y += 54;

  g.drawString(
    'Generated: ${data.exportedAtLabel}',
    fontSmall,
    brush: PdfSolidBrush(muted),
    bounds: Rect.fromLTWH(0, y, size.width, 12),
    format: PdfStringFormat(alignment: PdfTextAlignment.right),
  );
  y += 18;

  g.drawString('SUMMARY', fontSection, bounds: Rect.fromLTWH(0, y, 200, 14));
  y += 20;

  final cards = [
    ('Total Tasks', '${data.totalTasks}', navy),
    ('Completed', '${data.completedCount}', PdfColor(34, 139, 34)),
    ('In Progress', '${data.inProgressCount}', PdfColor(37, 99, 168)),
    ('Pending', '${data.pendingCount}', PdfColor(180, 100, 30)),
  ];
  const gap = 10.0;
  final cardW = (size.width - gap * 3) / 4;
  const cardH = 48.0;
  for (var i = 0; i < cards.length; i++) {
    final x = i * (cardW + gap);
    final (label, value, color) = cards[i];
    g.drawRectangle(
      brush: PdfSolidBrush(cardBg),
      pen: PdfPen(border, width: 0.6),
      bounds: Rect.fromLTWH(x, y, cardW, cardH),
    );
    g.drawRectangle(
      brush: PdfSolidBrush(color),
      bounds: Rect.fromLTWH(x, y, 4, cardH),
    );
    g.drawString(
      value,
      PdfStandardFont(PdfFontFamily.helvetica, 16, style: PdfFontStyle.bold),
      brush: PdfSolidBrush(color),
      bounds: Rect.fromLTWH(x + 14, y + 6, cardW - 20, 22),
    );
    g.drawString(
      label.toUpperCase(),
      fontSmall,
      brush: PdfSolidBrush(muted),
      bounds: Rect.fromLTWH(x + 14, y + 28, cardW - 20, 12),
    );
  }
  y += cardH + 22;

  final isCompleted = data.kind == StaffTaskReportKind.completed;
  g.drawString(
    isCompleted
        ? 'COMPLETED TASKS (${data.tasks.length})'
        : 'ALL TASKS (${data.tasks.length})',
    fontSection,
    bounds: Rect.fromLTWH(0, y, size.width, 14),
  );
  y += 16;

  final grid = PdfGrid();
  const colCount = 6;
  grid.columns.add(count: colCount);

  if (isCompleted) {
    grid.columns[0].width = size.width * 0.06;
    grid.columns[1].width = size.width * 0.24;
    grid.columns[2].width = size.width * 0.32;
    grid.columns[3].width = size.width * 0.12;
    grid.columns[4].width = size.width * 0.13;
    grid.columns[5].width = size.width * 0.13;
  } else {
    grid.columns[0].width = size.width * 0.06;
    grid.columns[1].width = size.width * 0.34;
    grid.columns[2].width = size.width * 0.16;
    grid.columns[3].width = size.width * 0.14;
    grid.columns[4].width = size.width * 0.15;
    grid.columns[5].width = size.width * 0.15;
  }

  final headers = isCompleted
      ? ['No.', 'Task', 'Description', 'Priority', 'Due Date', 'Completed']
      : ['No.', 'Task', 'Status', 'Priority', 'Due Date', 'Completed'];

  grid.headers.add(1);
  for (var i = 0; i < headers.length; i++) {
    final cell = grid.headers[0].cells[i];
    cell.value = headers[i];
    cell.style.backgroundBrush = PdfSolidBrush(navy);
    cell.style.textBrush = PdfBrushes.white;
    cell.style.font = fontBold;
    cell.stringFormat = PdfStringFormat(
      alignment: i <= 2 ? PdfTextAlignment.left : PdfTextAlignment.center,
      lineAlignment: PdfVerticalAlignment.middle,
    );
  }

  if (data.tasks.isEmpty) {
    final row = grid.rows.add();
    row.cells[0].value = '-';
    row.cells[1].value =
        isCompleted ? 'No completed tasks.' : 'No tasks assigned.';
    for (var c = 2; c < colCount; c++) {
      row.cells[c].value = '-';
    }
    for (var c = 0; c < colCount; c++) {
      row.cells[c].style.font = font;
      row.cells[c].style.backgroundBrush = PdfSolidBrush(lightBg);
      row.cells[c].style.borders.all = PdfPen(border, width: 0.4);
    }
  } else {
    for (var i = 0; i < data.tasks.length; i++) {
      final task = data.tasks[i];
      final row = grid.rows.add();
      final zebra = i.isOdd ? lightBg : PdfColor(255, 255, 255);
      row.cells[0].value = '${i + 1}';
      row.cells[1].value = _clean(task.title);
      if (isCompleted) {
        row.cells[2].value = _clean(task.description);
        row.cells[3].value = _priorityLabel(task.priority);
        row.cells[4].value = _fmtDate(task.dueDate);
        row.cells[5].value = _fmtDate(task.completedAt);
      } else {
        row.cells[2].value = _statusLabel(task.status);
        row.cells[3].value = _priorityLabel(task.priority);
        row.cells[4].value = _fmtDate(task.dueDate);
        row.cells[5].value =
            task.status == 'completed' ? _fmtDate(task.completedAt) : '-';
      }

      for (var c = 0; c < colCount; c++) {
        row.cells[c].style.font = font;
        row.cells[c].style.backgroundBrush = PdfSolidBrush(zebra);
        row.cells[c].style.borders.all = PdfPen(border, width: 0.4);
        row.cells[c].stringFormat = PdfStringFormat(
          alignment: c <= 2 ? PdfTextAlignment.left : PdfTextAlignment.center,
          lineAlignment: PdfVerticalAlignment.middle,
        );
      }
      row.cells[0].stringFormat = PdfStringFormat(
        alignment: PdfTextAlignment.center,
        lineAlignment: PdfVerticalAlignment.middle,
      );
    }
  }

  grid.style = PdfGridStyle(
    cellPadding: PdfPaddings(left: 6, right: 6, top: 6, bottom: 6),
    font: font,
  );

  grid.draw(
    page: page,
    bounds: Rect.fromLTWH(0, y, size.width, size.height - y - 20),
  );

  final bytes = Uint8List.fromList(await doc.save());
  doc.dispose();
  return bytes;
}
