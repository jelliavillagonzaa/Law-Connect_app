import 'dart:typed_data';

import 'temp_file_for_ocr_stub.dart'
    if (dart.library.io) 'temp_file_for_ocr_io.dart' as impl;

Future<String?> writeTempBytesForOcr(Uint8List bytes) =>
    impl.writeTempBytesForOcr(bytes);
