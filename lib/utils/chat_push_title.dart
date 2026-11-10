/// Chat push title: the sender's name plus Client, Staff, or Attorney.
class ChatPushTitle {
  ChatPushTitle._();

  static String format({required String name, String? role}) {
    final clean = name.trim();
    final label = roleLabel(role);
    final hasName = clean.isNotEmpty && clean != 'User' && clean != 'New message';
    if (!hasName) return label.isEmpty ? 'New message' : label;
    if (label.isEmpty) return clean;
    return '$clean · $label';
  }

  static String roleLabel(String? role) {
    switch ((role ?? '').trim().toLowerCase()) {
      case 'client':
        return 'Client';
      case 'staff':
      case 'paralegal':
        return 'Staff';
      case 'attorney':
        return 'Attorney';
      default:
        return '';
    }
  }
}
