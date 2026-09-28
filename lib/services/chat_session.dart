/// Which chat thread is on screen, so an open conversation does not
/// also raise a second push banner.
class ChatSession {
  static String? openChatId;

  static void open(String? chatId) {
    final id = chatId?.trim() ?? '';
    openChatId = id.isEmpty ? null : id;
  }

  static void close(String? chatId) {
    final id = chatId?.trim() ?? '';
    if (id.isEmpty || openChatId == id) {
      openChatId = null;
    }
  }
}
