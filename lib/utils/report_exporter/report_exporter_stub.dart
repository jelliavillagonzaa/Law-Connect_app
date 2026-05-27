import 'dart:typed_data';

/// Save bytes to the user's device as a downloaded file.
///
/// - On web: triggers a browser download
/// - On mobile/desktop: prompts for a save location when possible
Future<void> saveBytes({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  throw UnsupportedError('saveBytes is not supported on this platform.');
}

