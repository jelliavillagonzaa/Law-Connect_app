/// Third-party Gmail / shopping / product mail that leaked in as a court notice.
/// Real hearing titles are "Court hearing / order — …", never "New court notice".

bool isOutOfSystemCourtNoticeTitle(String title) {
  final t = title.toLowerCase().trim();
  if (t.isEmpty) return false;
  return t == 'new court notice' ||
      (t.startsWith('new court notice') && !t.contains('court hearings'));
}

bool isOutOfSystemPumpedNoticeText(String raw) {
  final t = raw.toLowerCase();
  if (t.isEmpty) return false;
  const markers = [
    'ollama',
    'canva',
    'google account data',
    'shared some google account',
    'you shared some google',
    'your order has been delivered',
    'order has been delivered',
    'thanks for shopping with us',
    'thanks for shopping',
    'transparent pricing',
    'your package has been delivered',
    'track your order',
  ];
  for (final m in markers) {
    if (t.contains(m)) return true;
  }
  return false;
}

String _cappedField(dynamic value, [int max = 400]) {
  if (value == null) return '';
  final s = value is String ? value : value.toString();
  if (s.length <= max) return s;
  return s.substring(0, max);
}

bool isOutOfSystemPumpedNotice(Map<String, dynamic> data) {
  final title = '${data['title'] ?? ''}'.toLowerCase().trim();
  if (isOutOfSystemCourtNoticeTitle(title)) return true;

  // Never concatenate full court-order OCR onto the UI isolate.
  final blob = [
    _cappedField(data['title'], 200),
    _cappedField(data['summary'], 400),
    _cappedField(data['subject'], 200),
    _cappedField(data['caseTitle'], 200),
    _cappedField(data['caseNo'], 80),
    _cappedField(data['message'], 400),
  ].join('\n');
  return isOutOfSystemPumpedNoticeText(blob);
}
