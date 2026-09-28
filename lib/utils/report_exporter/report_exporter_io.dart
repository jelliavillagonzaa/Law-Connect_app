import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Save bytes to the device and open the file. Returns the path that was opened.
Future<String?> saveBytes({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  final docs = await getApplicationDocumentsDirectory();
  final openable = File('${docs.path}/$filename');
  await openable.writeAsBytes(bytes, flush: true);

  try {
    final pickedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save file',
      fileName: filename,
      bytes: bytes,
    );
    if (pickedPath != null && pickedPath.isNotEmpty) {
      try {
        final picked = File(pickedPath);
        if (!await picked.exists() || await picked.length() == 0) {
          await picked.writeAsBytes(bytes, flush: true);
        }
      } catch (e) {
        debugPrint('saveBytes extra copy failed: $e');
      }
    }
  } catch (e) {
    debugPrint('saveBytes picker failed: $e');
  }

  final path = openable.path;
  try {
    final result = await OpenFilex.open(path, type: mimeType);
    if (result.type != ResultType.done) {
      debugPrint('OpenFilex ${result.type}: ${result.message}');
    }
  } catch (e) {
    debugPrint('OpenFilex failed: $e');
  }
  return path;
}
