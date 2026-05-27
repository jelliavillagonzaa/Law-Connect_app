import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<void> saveBytes({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save report',
    fileName: filename,
    bytes: bytes,
  );

  // Some platforms will save directly when `bytes` is provided; some return a path.
  if (path == null) return;
  final file = File(path);
  await file.writeAsBytes(bytes, flush: true);
}

