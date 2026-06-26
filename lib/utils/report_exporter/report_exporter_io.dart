import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

Future<void> saveBytes({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  final pickedPath = await FilePicker.platform.saveFile(
    dialogTitle: 'Save file',
    fileName: filename,
    bytes: bytes,
  );

  // Some platforms write the file when `bytes` is provided and return null.
  if (pickedPath != null && pickedPath.isNotEmpty) {
    final file = File(pickedPath);
    if (!await file.exists() || await file.length() == 0) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return;
  }

  // Fallback: save to the device Downloads folder (or app documents).
  final downloads = await getDownloadsDirectory();
  final dir = downloads ?? await getApplicationDocumentsDirectory();
  final out = File('${dir.path}/$filename');
  await out.writeAsBytes(bytes, flush: true);
}

