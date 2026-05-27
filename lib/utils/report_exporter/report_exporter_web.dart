import 'dart:typed_data';
import 'dart:html' as html;

/// Triggers a browser download with real binary content (not comma-separated text).
Future<void> saveBytes({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  // Pass Uint8List only — List<int> becomes "82,101,..." string on Flutter web.
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  try {
    final anchor = html.AnchorElement(href: url)
      ..download = filename
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
  } finally {
    html.Url.revokeObjectUrl(url);
  }
}
