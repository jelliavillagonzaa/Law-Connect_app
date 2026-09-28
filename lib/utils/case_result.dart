/// How a completed case ended. Status stays `completed`.
class CaseResult {
  CaseResult._();

  static const won = 'won';
  static const lost = 'lost';
  static const settled = 'settled';
  static const dismissed = 'dismissed';

  static const List<String> values = [
    won,
    lost,
    settled,
    dismissed,
  ];

  static String label(String? result) {
    switch ((result ?? '').toLowerCase().trim()) {
      case won:
        return 'Won';
      case lost:
        return 'Lost';
      case settled:
        return 'Settled';
      case dismissed:
        return 'Dismissed / withdrawn';
      default:
        return '';
    }
  }

  static String shortLabel(String? result) {
    switch ((result ?? '').toLowerCase().trim()) {
      case won:
        return 'Won';
      case lost:
        return 'Lost';
      case settled:
        return 'Settled';
      case dismissed:
        return 'Dismissed';
      default:
        return '';
    }
  }

  static bool isValid(String? result) {
    final s = (result ?? '').toLowerCase().trim();
    return values.contains(s);
  }

  static String? normalize(String? result) {
    final s = (result ?? '').toLowerCase().trim();
    return isValid(s) ? s : null;
  }
}
