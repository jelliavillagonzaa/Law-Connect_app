import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';

Future<String?> writeTempBytesForOcr(Uint8List bytes) async {
  final dir = await getTemporaryDirectory();
  final f = File(
    '${dir.path}/lc_court_${DateTime.now().millisecondsSinceEpoch}.bin',
  );
  await f.writeAsBytes(bytes, flush: true);
  return f.path;
}
