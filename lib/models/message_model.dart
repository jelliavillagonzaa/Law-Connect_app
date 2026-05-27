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
      if (reactions != null) 'reactions': reactions,
    };
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

  ChatModel({
    required this.id,
    required this.participants,
    this.lastMessage,
    required this.updatedAt,
    this.clientId,
    this.attorneyId,
    this.staffId,
    this.staffEmail,
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
    };
  }
}
