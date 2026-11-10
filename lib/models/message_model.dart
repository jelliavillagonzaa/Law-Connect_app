import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  final String id;
  final String chatId;
  final String senderId;
  final String text;
  final String? attachmentUrl;
  final DateTime timestamp;
  final bool? isSeen;
  final String? senderRole; // 'client', 'staff', 'attorney', 'admin'
  final String? senderName;
  final Map<String, List<String>>?
  reactions; // emoji -> list of user IDs who reacted

  MessageModel({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    this.attachmentUrl,
    required this.timestamp,
    this.isSeen,
    this.senderRole,
    this.senderName,
    this.reactions,
  });

  factory MessageModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    Map<String, List<String>>? reactionsMap;
    if (data['reactions'] != null) {
      reactionsMap = Map<String, List<String>>.from(
        (data['reactions'] as Map).map(
          (key, value) =>
              MapEntry(key.toString(), List<String>.from(value as List)),
        ),
      );
    }
    return MessageModel(
      id: doc.id,
      chatId: data['chatId'] ?? '',
      senderId: data['senderId'] ?? '',
      text: data['text'] ?? '',
      attachmentUrl: data['attachmentUrl'],
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isSeen: data['isSeen'] ?? false,
      senderRole: data['senderRole'],
      senderName: data['senderName'],
      reactions: reactionsMap,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'chatId': chatId,
      'senderId': senderId,
      'text': text,
      if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
      'timestamp': Timestamp.fromDate(timestamp),
      'isSeen': isSeen ?? false,
      if (senderRole != null) 'senderRole': senderRole,
      if (senderName != null && senderName!.trim().isNotEmpty)
        'senderName': senderName,
      if (reactions != null) 'reactions': reactions,
    };
  }

  String labelForSender({required String fallback}) {
    final named = senderName?.trim() ?? '';
    if (named.isNotEmpty) return named;
    return fallback;
  }
}

class ChatModel {
  final String id;
  final List<String> participants;
  final String? lastMessage;
  final DateTime updatedAt;
  final String? clientId;
  final String? attorneyId;
  final String? staffId; // Added for client-staff chats
  final String? staffEmail; // Added for chats created with staff email
  final String? clientName;
  final String? chatType; // 'client_staff', 'client_attorney', 'staff_attorney'
  final Map<String, int> unreadFor;

  ChatModel({
    required this.id,
    required this.participants,
    this.lastMessage,
    required this.updatedAt,
    this.clientId,
    this.attorneyId,
    this.staffId,
    this.staffEmail,
    this.clientName,
    this.chatType,
    this.unreadFor = const {},
  });

  factory ChatModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatModel(
      id: doc.id,
      participants: List<String>.from(data['participants'] ?? []),
      lastMessage: data['lastMessage'],
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      clientId: data['clientId'],
      attorneyId: data['attorneyId'],
      staffId: data['staffId'],
      staffEmail: data['staffEmail'],
      clientName: data['clientName'],
      chatType: data['chatType'],
      unreadFor: unreadForMap(data['unreadFor']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'participants': participants,
      if (lastMessage != null) 'lastMessage': lastMessage,
      'updatedAt': Timestamp.fromDate(updatedAt),
      if (clientId != null) 'clientId': clientId,
      if (attorneyId != null) 'attorneyId': attorneyId,
      if (staffId != null) 'staffId': staffId,
      if (staffEmail != null) 'staffEmail': staffEmail,
      if (clientName != null && clientName!.trim().isNotEmpty)
        'clientName': clientName,
      if (chatType != null) 'chatType': chatType,
    };
  }

  bool get isClientStaffChat =>
      chatType == 'client_staff' ||
      ((staffId != null && staffId!.isNotEmpty) &&
          (clientId != null && clientId!.isNotEmpty)) ||
      (staffEmail != null && staffEmail!.isNotEmpty);

  bool get hasMessages {
    final text = lastMessage?.trim() ?? '';
    return text.isNotEmpty;
  }

  /// Unread messages waiting for [userId]. Staff also sees shared office inbox.
  int unreadCountFor(String userId, {bool includeOfficeStaff = false}) {
    final mine = unreadFor[userId] ?? 0;
    if (!includeOfficeStaff) return mine < 0 ? 0 : mine;
    final office = unreadFor[officeUnreadKey] ?? 0;
    final n = mine > office ? mine : office;
    return n < 0 ? 0 : n;
  }

  static const officeUnreadKey = 'officeStaff';

  static Map<String, int> unreadForMap(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, int>{};
    raw.forEach((key, value) {
      final k = key.toString();
      if (k.isEmpty) return;
      if (value is int) {
        out[k] = value;
      } else if (value is num) {
        out[k] = value.round();
      }
    });
    return out;
  }

  static bool isPlaceholderClientLabel(String name) {
    final n = name.trim().toLowerCase();
    return n.isEmpty || n == 'client' || n == 'user' || n == 'unknown';
  }

  /// One row per client account: keep the newest thread.
  static List<ChatModel> oneThreadPerClient(List<ChatModel> chats) {
    final byClient = <String, ChatModel>{};
    final rest = <ChatModel>[];
    for (final chat in chats) {
      final clientId = chat.clientId?.trim() ?? '';
      if (clientId.isEmpty) {
        rest.add(chat);
        continue;
      }
      final current = byClient[clientId];
      if (current == null || chat.updatedAt.isAfter(current.updatedAt)) {
        byClient[clientId] = chat;
      }
    }
    final merged = [...byClient.values, ...rest];
    merged.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return merged;
  }
}
