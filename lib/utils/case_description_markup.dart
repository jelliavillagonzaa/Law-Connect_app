import 'dart:convert';

/// One styled piece of a case description, as typed in the editor.
class CaseTextRun {
  const CaseTextRun({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.font = 'Times New Roman',
    this.size = 16,
    this.sizeExplicit = false,
    this.color,
    this.background,
    this.script,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final String font;
  final double size;
  final bool sizeExplicit;
  final int? color;
  final int? background;
  final String? script;
}

/// One paragraph, including alignment, lists, and line spacing.
class CaseTextParagraph {
  const CaseTextParagraph({
    required this.runs,
    this.align = 'left',
    this.list,
    this.indent = 0,
    this.header = 0,
    this.lineHeight = 1.5,
    this.quote = false,
  });

  final List<CaseTextRun> runs;
  final String align;
  final String? list;
  final int indent;
  final int header;
  final double lineHeight;
  final bool quote;

  bool get isBlank => runs.every((run) => run.text.trim().isEmpty);
}

/// RTF for the description, plus colors that must be added to the color table.
class CaseDescriptionRtf {
  const CaseDescriptionRtf({required this.body, required this.colors});

  final String body;

  /// RGB values. The first extra color is RTF color index 4.
  final List<int> colors;
}

/// Reads the saved editor delta. Falls back to plain text when there is no delta.
List<CaseTextParagraph> parseCaseDescription({
  String? deltaJson,
  String plain = '',
}) {
  final fromDelta = _parseDelta(deltaJson);
  if (fromDelta != null && _hasVisibleText(fromDelta)) return fromDelta;
  return _plainParagraphs(plain);
}

CaseDescriptionRtf buildCaseDescriptionRtf(List<CaseTextParagraph> paragraphs) {
  if (paragraphs.isEmpty || !_hasVisibleText(paragraphs)) {
    return const CaseDescriptionRtf(body: r'\pard\ql —\par ', colors: []);
  }

  final colors = <int>[];
  int colorSlot(int? rgb) {
    if (rgb == null) return 0;
    final existing = colors.indexOf(rgb);
    if (existing >= 0) return existing + 4;
    colors.add(rgb);
    return colors.length + 3;
  }

  final buffer = StringBuffer();
  var ordered = 0;
  for (final paragraph in paragraphs) {
    if (paragraph.list == 'ordered') {
      ordered += 1;
    } else {
      ordered = 0;
    }
    buffer.write(_paragraphRtf(paragraph, ordered, colorSlot));
  }
  buffer.write(r'\pard\ql\f0\fs22\b0\i0\ul0\strike0\highlight0\cf0\nosupersub ');
  return CaseDescriptionRtf(body: buffer.toString(), colors: colors);
}

bool _hasVisibleText(List<CaseTextParagraph> paragraphs) {
  for (final paragraph in paragraphs) {
    for (final run in paragraph.runs) {
      if (run.text.trim().isNotEmpty) return true;
    }
  }
  return false;
}

List<CaseTextParagraph> _plainParagraphs(String plain) {
  final text = plain.trim();
  if (text.isEmpty) return const [];
  return [
    for (final line in text.split('\n'))
      CaseTextParagraph(runs: [CaseTextRun(text: line.trimRight())]),
  ];
}

List<CaseTextParagraph>? _parseDelta(String? deltaJson) {
  final encoded = deltaJson?.trim() ?? '';
  if (encoded.isEmpty) return null;
  try {
    final raw = jsonDecode(encoded);
    if (raw is! List) return null;
    final paragraphs = <CaseTextParagraph>[];
    var runs = <CaseTextRun>[];

    void closeParagraph(Map<String, dynamic> block) {
      paragraphs.add(
        CaseTextParagraph(
          runs: runs,
          align: _stringAttr(block['align']) ?? 'left',
          list: _stringAttr(block['list']),
          indent: _intAttr(block['indent']),
          header: _intAttr(block['header']),
          lineHeight: _doubleAttr(block['line-height']) ?? 1.5,
          quote: block['blockquote'] == true,
        ),
      );
      runs = [];
    }

    for (final entry in raw) {
      if (entry is! Map) continue;
      final insert = entry['insert'];
      if (insert is! String) continue;
      final attrs = entry['attributes'] is Map
          ? Map<String, dynamic>.from(entry['attributes'] as Map)
          : <String, dynamic>{};
      var rest = insert;
      while (true) {
        final newline = rest.indexOf('\n');
        if (newline < 0) {
          if (rest.isNotEmpty) runs.add(_run(rest, attrs));
          break;
        }
        final before = rest.substring(0, newline);
        if (before.isNotEmpty) runs.add(_run(before, attrs));
        closeParagraph(attrs);
        rest = rest.substring(newline + 1);
      }
    }
    if (runs.isNotEmpty) closeParagraph(const {});
    if (paragraphs.isNotEmpty && paragraphs.last.isBlank) {
      paragraphs.removeLast();
    }
    return paragraphs;
  } catch (_) {
    return null;
  }
}

CaseTextRun _run(String text, Map<String, dynamic> attrs) {
  final sizeRaw = attrs['size']?.toString();
  final size = _fontSize(sizeRaw);
  return CaseTextRun(
    text: text,
    bold: attrs['bold'] == true,
    italic: attrs['italic'] == true,
    underline: attrs['underline'] == true,
    strike: attrs['strike'] == true,
    font: _stringAttr(attrs['font']) ?? 'Times New Roman',
    size: size ?? 16,
    sizeExplicit: size != null,
    color: _cssColor(attrs['color']),
    background: _cssColor(attrs['background']),
    script: _stringAttr(attrs['script']),
  );
}

String _paragraphRtf(
  CaseTextParagraph paragraph,
  int ordered,
  int Function(int? rgb) colorSlot,
) {
  final align = switch (paragraph.align) {
    'center' => r'\qc',
    'right' => r'\qr',
    'justify' => r'\qj',
    _ => r'\ql',
  };
  final levels = paragraph.indent +
      (paragraph.list == null ? 0 : 1) +
      (paragraph.quote ? 1 : 0);
  final left = levels * 360;
  final spacing = (240 * paragraph.lineHeight).round().clamp(240, 960);
  final buffer = StringBuffer()
    ..write(r'\pard')
    ..write(align)
    ..write('\\li$left\\sl$spacing\\slmult1 ');
  if (paragraph.quote) {
    buffer.write(r'\brdrl\brdrs\brdrw10 ');
  }

  if (paragraph.list == 'ordered' && ordered > 0) {
    buffer.write(_escape(paragraph.header > 0 ? '$ordered. ' : '$ordered. '));
  } else if (paragraph.list == 'bullet') {
    buffer.write(r'\u8226? ');
  }

  if (paragraph.runs.isEmpty) {
    buffer.write(r'\par ');
    return buffer.toString();
  }

  for (final run in paragraph.runs) {
    final bold = run.bold || paragraph.header > 0;
    final size = run.sizeExplicit
        ? run.size
        : switch (paragraph.header) {
            1 => 24.0,
            2 => 20.0,
            3 => 18.0,
            _ => run.size,
          };
    buffer
      ..write(bold ? r'\b ' : r'\b0 ')
      ..write(run.italic ? r'\i ' : r'\i0 ')
      ..write(run.underline ? r'\ul ' : r'\ul0 ')
      ..write(run.strike ? r'\strike ' : r'\strike0 ')
      ..write(switch (run.script) {
        'sub' => r'\sub ',
        'super' => r'\super ',
        _ => r'\nosupersub ',
      })
      ..write('\\f${_rtfFont(run.font)}')
      ..write('\\fs${(size * 2).round().clamp(16, 72)} ');
    final color = colorSlot(run.color);
    final background = colorSlot(run.background);
    buffer
      ..write(color == 0 ? r'\cf0 ' : '\\cf$color ')
      ..write(background == 0 ? r'\highlight0 ' : '\\highlight$background ')
      ..write(_escape(run.text));
  }
  buffer.write(r'\par ');
  return buffer.toString();
}

int _rtfFont(String name) {
  final normalized = name.toLowerCase();
  if (normalized.contains('courier')) return 2;
  if (normalized.contains('georgia')) return 3;
  if (normalized.contains('calibri')) return 4;
  if (normalized.contains('arial') || normalized.contains('helvetica')) {
    return 0;
  }
  return 1;
}

String? _stringAttr(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return null;
  return text;
}

int _intAttr(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double? _doubleAttr(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

double? _fontSize(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(raw);
  if (match == null) return null;
  return double.tryParse(match.group(1)!);
}

int? _cssColor(Object? raw) {
  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  if (text.startsWith('#')) {
    var hex = text.substring(1);
    if (hex.length == 3) {
      hex = hex.split('').map((char) => '$char$char').join();
    }
    if (hex.length == 8) hex = hex.substring(0, 6);
    if (hex.length == 6) return int.tryParse(hex, radix: 16);
  }
  final rgb = RegExp(
    r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)',
  ).firstMatch(text);
  if (rgb == null) return null;
  final red = int.parse(rgb.group(1)!).clamp(0, 255);
  final green = int.parse(rgb.group(2)!).clamp(0, 255);
  final blue = int.parse(rgb.group(3)!).clamp(0, 255);
  return (red << 16) | (green << 8) | blue;
}

String _escape(String text) {
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
