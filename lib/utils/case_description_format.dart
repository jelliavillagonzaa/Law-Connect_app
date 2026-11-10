import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

QuillController createCaseDescriptionController({
  String? deltaJson,
  String? plainFallback,
}) {
  Document document;
  final encoded = deltaJson?.trim() ?? '';
  if (encoded.isNotEmpty) {
    try {
      final raw = jsonDecode(encoded);
      if (raw is List) {
        document = Document.fromJson(raw);
        if (document.toPlainText().trim().isEmpty) {
          document = _plainDocument(plainFallback);
        }
      } else {
        document = _plainDocument(plainFallback);
      }
    } catch (_) {
      document = _plainDocument(plainFallback);
    }
  } else {
    document = _plainDocument(plainFallback);
  }

  return QuillController(
    document: document,
    selection: const TextSelection.collapsed(offset: 0),
  );
}

Document _plainDocument(String? plainFallback) {
  final text = plainFallback?.trim() ?? '';
  if (text.isEmpty) return Document();
  return Document()..insert(0, text);
}

String caseDescriptionPlainText(QuillController controller) {
  return controller.document.toPlainText().trim();
}

String caseDescriptionDeltaJson(QuillController controller) {
  return jsonEncode(controller.document.toDelta().toJson());
}

int caseDescriptionWordCount(QuillController controller) {
  final plain = caseDescriptionPlainText(controller);
  if (plain.isEmpty) return 0;
  return plain.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
}
