import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'dart:io';
import 'dart:async';
import '../models/message_model.dart';
import 'notification_service.dart';
import 'firestore_mirror_helper.dart';
import 'fcm_service.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final NotificationService _notificationService = NotificationService();

  // Track last message timestamp to avoid duplicate notifications
  final Map<String, DateTime> _lastNotificationTime = {};
  final Map<String, Timer> _seenMarkDebounce = {};

  // Get or create a chat with staff by email (no need to find staff user first)
  // Messages go directly to staff@gmail.com - staff will see it when they log in
  Future<String> getOrCreateChatByStaffEmail({
    required String clientId,
    required String staffEmail,
  }) async {
    try {
      // Check if chat already exists for this client and staff email
      final existingChats = await _firestore
          .collection('messages')
          .where('clientId', isEqualTo: clientId)
          .where('staffEmail', isEqualTo: staffEmail)
          .limit(1)
          .get();

      if (existingChats.docs.isNotEmpty) {
        return existingChats.docs.first.id;
      }

      // Create new chat with staffEmail identifier
      // Staff will be able to access it by their email when they log in
      final chatData = <String, dynamic>{
        'participants': [
          clientId,
          'staff_$staffEmail',
        ], // Use email as identifier
        'clientId': clientId,
        'staffEmail': staffEmail, // Store email for staff lookup
        'lastMessage': null,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final result = await HybridDatastore.addChat(data: chatData);
      if (!result.isSuccess || result.id == null) {
        throw Exception(result.failureMessage);
      }
      return result.id!;
    } catch (e) {
      throw Exception('Failed to get or create chat with staff: $e');
    }
  }

  // Get or create a chat between two users
  // Can be used for client-attorney or client-staff chats
  Future<String> getOrCreateChat(String userId1, String userId2) async {
    try {
      // Check if chat already exists
      final existingChats = await _firestore
          .collection('messages')
          .where('participants', arrayContains: userId1)
          .get();

      for (var doc in existingChats.docs) {
        final participants = List<String>.from(
          doc.data()['participants'] ?? [],
        );
        if (participants.contains(userId1) && participants.contains(userId2)) {
          // Update chat document to include clientId and attorneyId/staffId if not present
          final data = doc.data();

          // Determine which user is client and which is staff/attorney
          final user1Doc = await _firestore
              .collection('users')
              .doc(userId1)
              .get();
          final user2Doc = await _firestore
              .collection('users')
              .doc(userId2)
              .get();

          String? clientId;
          String? attorneyId;
          String? staffId;

          if (user1Doc.exists && user1Doc.data()?['role'] == 'client') {
            clientId = userId1;
            if (user2Doc.exists) {
              final role2 = user2Doc.data()?['role'];
              if (role2 == 'attorney') {
                attorneyId = userId2;
              } else if (role2 == 'staff') {
                staffId = userId2;
                // Only set attorneyId for staff-attorney chats, NOT for staff-client chats
                // For direct staff-client chats, we don't want attorneyId
              }
            }
          } else if (user2Doc.exists && user2Doc.data()?['role'] == 'client') {
            clientId = userId2;
            if (user1Doc.exists) {
              final role1 = user1Doc.data()?['role'];
              if (role1 == 'attorney') {
                attorneyId = userId1;
              } else if (role1 == 'staff') {
                staffId = userId1;
                // Only set attorneyId for staff-attorney chats, NOT for staff-client chats
                // For direct staff-client chats, we don't want attorneyId
              }
            }
          } else if (user1Doc.exists &&
              user1Doc.data()?['role'] == 'staff' &&
              user2Doc.exists &&
              user2Doc.data()?['role'] == 'attorney') {
            // Direct staff-attorney chat (no client)
            staffId = userId1;
            attorneyId = userId2;
          } else if (user1Doc.exists &&
              user1Doc.data()?['role'] == 'attorney' &&
              user2Doc.exists &&
              user2Doc.data()?['role'] == 'staff') {
            // Direct staff-attorney chat (no client)
            attorneyId = userId1;
            staffId = userId2;
          }

          // Update chat document if needed
          final updateData = <String, dynamic>{};
          if (clientId != null && data['clientId'] == null) {
            updateData['clientId'] = clientId;
          }
          // Only set attorneyId if it's a direct staff-attorney chat (no client) or client-attorney chat (no staff)
          // Don't set attorneyId for staff-client chats
          if (attorneyId != null && data['attorneyId'] == null) {
            if (clientId == null || staffId == null) {
              updateData['attorneyId'] = attorneyId;
            }
          }
          if (staffId != null && data['staffId'] == null) {
            updateData['staffId'] = staffId;
          }

          // Remove attorneyId from staff-client chats if it exists
          if (clientId != null &&
              staffId != null &&
              data['attorneyId'] != null) {
            updateData['attorneyId'] = FieldValue.delete();
          }

          if (updateData.isNotEmpty) {
            await doc.reference.update(updateData);
          }

          return doc.id;
        }
      }

      // Determine roles for new chat
      final user1Doc = await _firestore.collection('users').doc(userId1).get();
      final user2Doc = await _firestore.collection('users').doc(userId2).get();

      String? clientId;
      String? attorneyId;
      String? staffId;

      // Get roles
      String? role1;
      String? role2;
      if (user1Doc.exists) {
        final data = user1Doc.data();
        role1 = data?['role'];
      }
      if (user2Doc.exists) {
        final data = user2Doc.data();
        role2 = data?['role'];
      }

      // Priority 1: Attorney-Client direct chat (most important - no staff should be involved)
      if (role1 == 'attorney' && role2 == 'client') {
        attorneyId = userId1;
        clientId = userId2;
        // Explicitly NO staffId for direct attorney-client chats
      } else if (role1 == 'client' && role2 == 'attorney') {
        clientId = userId1;
        attorneyId = userId2;
        // Explicitly NO staffId for direct attorney-client chats
      }
      // Priority 2: Staff-Client chat (no attorney)
      else if (role1 == 'staff' && role2 == 'client') {
        staffId = userId1;
        clientId = userId2;
        // No attorneyId for direct staff-client chats
      } else if (role1 == 'client' && role2 == 'staff') {
        clientId = userId1;
        staffId = userId2;
        // No attorneyId for direct staff-client chats
      }
      // Priority 3: Staff-Attorney chat (no client)
      else if (role1 == 'staff' && role2 == 'attorney') {
        staffId = userId1;
        attorneyId = userId2;
      } else if (role1 == 'attorney' && role2 == 'staff') {
        attorneyId = userId1;
        staffId = userId2;
      }

      // Create new chat
      final chatData = <String, dynamic>{
        'participants': [userId1, userId2],
        'lastMessage': null,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (clientId != null) {
        chatData['clientId'] = clientId;
      }
      // Only set attorneyId if it's a direct attorney-client chat (no staff) OR staff-attorney chat (no client)
      if (attorneyId != null) {
        // For attorney-client chats: set attorneyId only if there's NO staff
        // For staff-attorney chats: set attorneyId only if there's NO client
        if ((clientId != null && staffId == null) ||
            (clientId == null && staffId != null)) {
          chatData['attorneyId'] = attorneyId;
        }
      }
      if (staffId != null) {
        chatData['staffId'] = staffId;
      }

      final result = await HybridDatastore.addChat(data: chatData);
      if (!result.isSuccess || result.id == null) {
        throw Exception(result.failureMessage);
      }

      return result.id!;
    } catch (e) {
      throw Exception('Failed to get or create chat: $e');
    }
  }

  // Send a text message
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String text,
    String? senderRole,
  }) async {
    try {
      // Get sender role if not provided
      String? finalSenderRole = senderRole;
      if (finalSenderRole == null) {
        try {
          final senderDoc = await _firestore
              .collection('users')
              .doc(senderId)
              .get();
          finalSenderRole = senderDoc.data()?['role'];
        } catch (e) {
          // If can't get role, continue without it
        }
      }

      // Add message to subcollection
      final msgData = <String, dynamic>{
        'chatId': chatId,
        'senderId': senderId,
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
        'isSeen': false,
        if (finalSenderRole != null) 'senderRole': finalSenderRole,
      };
      final msgResult = await HybridDatastore.addChatMessage(
        chatId: chatId,
        data: msgData,
      );
      if (!msgResult.isSuccess) throw Exception(msgResult.failureMessage);

      // Update chat last message
      final chatResult = await HybridDatastore.updateChat(
        id: chatId,
        patch: {
          'lastMessage': text,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      if (!chatResult.isSuccess) throw Exception(chatResult.failureMessage);

      unawaited(
        _pushNewMessageToRecipients(
          chatId: chatId,
          senderId: senderId,
          text: text,
        ),
      );
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  // Send message with attachment
  Future<void> sendMessageWithAttachment({
    required String chatId,
    required String senderId,
    required String text,
    required File file,
  }) async {
    try {
      // Upload file to Firebase Storage
      final fileName = file.path.split('/').last;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = _storage.ref().child(
        'chat_attachments/$chatId/${timestamp}_$fileName',
      );

      final uploadTask = ref.putFile(file);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Add message with attachment
      final msgData = <String, dynamic>{
        'chatId': chatId,
        'senderId': senderId,
        'text': text,
        'attachmentUrl': downloadUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'isSeen': false,
      };
      final msgResult = await HybridDatastore.addChatMessage(
        chatId: chatId,
        data: msgData,
      );
      if (!msgResult.isSuccess) throw Exception(msgResult.failureMessage);

      final lastMessage = text.isEmpty ? 'Attachment' : text;

      // Update chat last message
      final chatResult = await HybridDatastore.updateChat(
        id: chatId,
        patch: {
          'lastMessage': lastMessage,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      if (!chatResult.isSuccess) throw Exception(chatResult.failureMessage);

      unawaited(
        _pushNewMessageToRecipients(
          chatId: chatId,
          senderId: senderId,
          text: lastMessage,
        ),
      );
    } catch (e) {
      throw Exception('Failed to send message with attachment: $e');
    }
  }

  /// Push only to the other people in the thread (client, staff, or attorney).
  Future<void> _pushNewMessageToRecipients({
    required String chatId,
    required String senderId,
    required String text,
  }) async {
    try {
      final chatDoc = await _firestore.collection('messages').doc(chatId).get();
      if (!chatDoc.exists) return;
      final data = chatDoc.data() ?? {};
      final recipients = await _messageRecipientIds(data, senderId);
      if (recipients.isEmpty) return;

      var senderName = 'New message';
      try {
        final senderDoc = await _firestore.collection('users').doc(senderId).get();
        final senderData = senderDoc.data();
        final name = (senderData?['fullName'] ??
                senderData?['name'] ??
                senderData?['displayName'] ??
                '')
            .toString()
            .trim();
        if (name.isNotEmpty) senderName = name;
      } catch (_) {}

      final trimmed = text.trim();
      final preview = trimmed.isEmpty
          ? 'Sent an attachment'
          : (trimmed.length > 140 ? '${trimmed.substring(0, 140)}...' : trimmed);

      final fcm = FCMService();
      for (final userId in recipients) {
        await fcm.sendChatPush(
          userId: userId,
          title: senderName,
          body: preview,
          chatId: chatId,
          senderId: senderId,
          senderName: senderName,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Chat push skipped: $e');
      }
    }
  }

  Future<Set<String>> _messageRecipientIds(
    Map<String, dynamic> data,
    String senderId,
  ) async {
    final ids = <String>{};
    void addId(dynamic raw) {
      final id = raw?.toString().trim() ?? '';
      if (id.isEmpty || id == senderId || id.startsWith('staff_')) return;
      ids.add(id);
    }

    final participants = data['participants'];
    if (participants is List) {
      for (final participant in participants) {
        addId(participant);
      }
    }
    addId(data['clientId']);
    addId(data['staffId']);
    addId(data['attorneyId']);

    final emails = <String>{};
    final staffEmail = data['staffEmail']?.toString().trim() ?? '';
    if (staffEmail.isNotEmpty) emails.add(staffEmail);
    if (participants is List) {
      for (final participant in participants) {
        final value = participant?.toString() ?? '';
        if (value.startsWith('staff_') && value.length > 6) {
          emails.add(value.substring(6));
        }
      }
    }
    for (final email in emails) {
      try {
        final matches = await _firestore
            .collection('users')
            .where('email', isEqualTo: email)
            .limit(3)
            .get();
        for (final doc in matches.docs) {
          if (doc.id != senderId) ids.add(doc.id);
        }
      } catch (_) {}
    }

    ids.remove(senderId);
    return ids;
  }

  // Get messages for a chat (real-time stream)
  Stream<List<MessageModel>> getMessages(String chatId) {
    try {
      return _firestore
          .collection('messages')
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(80)
          .snapshots()
          .map((snapshot) {
            return snapshot.docs
                .map((doc) => MessageModel.fromFirestore(doc))
                .toList()
                .reversed
                .toList();
          });
    } catch (e) {
      throw Exception('Failed to get messages: $e');
    }
  }

  // Get messages with notification sound for new messages
  Stream<List<MessageModel>> getMessagesWithNotifications(String chatId) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return _firestore
        .collection('messages')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(80)
        .snapshots()
        .map((snapshot) {
          final messages = snapshot.docs
              .map((doc) => MessageModel.fromFirestore(doc))
              .toList()
              .reversed
              .toList();

          if (messages.isNotEmpty && currentUserId != null) {
            final lastMessage = messages.last;
            if (lastMessage.senderId != currentUserId) {
              final messageTime = lastMessage.timestamp;
              final lastNotified = _lastNotificationTime[chatId];
              final timeSinceMessage =
                  DateTime.now().difference(messageTime).inSeconds;
              if (timeSinceMessage < 5 &&
                  (lastNotified == null || messageTime.isAfter(lastNotified))) {
                _lastNotificationTime[chatId] = messageTime;
                unawaited(
                  _notificationService.showNotificationWithSound(
                    id: DateTime.now().millisecondsSinceEpoch % 100000,
                    title: 'New message',
                    body: lastMessage.text.isNotEmpty
                        ? lastMessage.text
                        : 'Sent an attachment',
                    payload: chatId,
                  ),
                );
              }
            }
          }

          return messages;
        });
  }

  // Get all chats for a user
  Stream<List<ChatModel>> getUserChats(String userId) {
    try {
      return _firestore
          .collection('messages')
          .where('participants', arrayContains: userId)
          .limit(30)
          .snapshots()
          .map((snapshot) {
            final chats = snapshot.docs
                .map((doc) {
                  final data = doc.data();
                  // Filter out conversations deleted by this user
                  final deletedFor = List<String>.from(
                    data['deletedFor'] ?? [],
                  );
                  if (deletedFor.contains(userId)) {
                    return null; // Skip this conversation
                  }
                  return ChatModel.fromFirestore(doc);
                })
                .where((chat) => chat != null)
                .cast<ChatModel>()
                .toList();
            // Sort by updatedAt in memory to avoid index requirement
            chats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
            return chats;
          });
    } catch (e) {
      throw Exception('Failed to get user chats: $e');
    }
  }

  /// Debounced mark-as-read while a chat is open (avoids spamming writes).
  void markMessagesAsSeenDebounced(String chatId, String userId) {
    _seenMarkDebounce[chatId]?.cancel();
    _seenMarkDebounce[chatId] = Timer(const Duration(milliseconds: 350), () {
      unawaited(markMessagesAsSeen(chatId, userId));
    });
  }

  // Mark messages as seen
  Future<void> markMessagesAsSeen(String chatId, String userId) async {
    try {
      QuerySnapshot<Map<String, dynamic>> messagesSnapshot;
      try {
        messagesSnapshot = await _firestore
            .collection('messages')
            .doc(chatId)
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .limit(200)
            .get();
      } catch (_) {
        messagesSnapshot = await _firestore
            .collection('messages')
            .doc(chatId)
            .collection('messages')
            .limit(200)
            .get();
      }

      final toMark = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in messagesSnapshot.docs) {
        final data = doc.data();
        final senderId = data['senderId'] as String?;
        if (senderId == null || senderId == userId) continue;
        if (data['isSeen'] == true) continue;
        toMark.add(doc);
      }

      if (toMark.isEmpty) return;

      final batch = _firestore.batch();
      for (final doc in toMark) {
        batch.update(doc.reference, {'isSeen': true});
      }
      await batch.commit();

      for (final doc in toMark) {
        unawaited(
          HybridDatastore.updateChatMessage(
            chatId: chatId,
            id: doc.id,
            patch: {'isSeen': true},
          ),
        );
      }

      try {
        await _firestore.collection('messages').doc(chatId).update({
          'updatedAt': FieldValue.serverTimestamp(),
        });
        unawaited(
          HybridDatastore.updateChat(
            id: chatId,
            patch: {'updatedAt': FieldValue.serverTimestamp()},
          ),
        );
      } catch (_) {}
    } catch (e) {
      throw Exception('Failed to mark messages as seen: $e');
    }
  }

  // Unread badge: cache-first, never N+1 message scans (those ANR the client).
  Future<int> getUnreadCount(String userId, {int maxChats = 6}) async {
    try {
      final query = _firestore
          .collection('messages')
          .where('participants', arrayContains: userId)
          .limit(maxChats);
      QuerySnapshot<Map<String, dynamic>> chats;
      try {
        chats = await query
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 1));
        if (chats.docs.isEmpty) {
          chats = await query.get().timeout(const Duration(seconds: 1));
        }
      } catch (_) {
        return 0;
      }

      var totalUnread = 0;
      var peeked = 0;
      for (final chatDoc in chats.docs) {
        final data = chatDoc.data();
        final deletedFor = List<String>.from(data['deletedFor'] ?? []);
        if (deletedFor.contains(userId)) continue;
        if (peeked >= 3) break;
        peeked++;
        try {
          final snap = await _firestore
              .collection('messages')
              .doc(chatDoc.id)
              .collection('messages')
              .limit(8)
              .get(const GetOptions(source: Source.cache))
              .timeout(const Duration(milliseconds: 400));
          for (final msgDoc in snap.docs) {
            final msg = msgDoc.data();
            if (msg['senderId'] != userId && msg['isSeen'] != true) {
              totalUnread++;
            }
          }
        } catch (_) {}
      }
      return totalUnread;
    } catch (_) {
      return 0;
    }
  }

  /// Whether this conversation has unread messages for [userId].
  Future<bool> chatHasUnread(String chatId, String userId) async {
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _firestore
            .collection('messages')
            .doc(chatId)
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .limit(50)
            .get();
      } catch (_) {
        snap = await _firestore
            .collection('messages')
            .doc(chatId)
            .collection('messages')
            .limit(50)
            .get();
      }
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['senderId'] != userId && data['isSeen'] != true) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Live per-conversation unread flag for list cards.
  Stream<bool> watchChatHasUnread(String chatId, String userId) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('messages')
        .doc(chatId)
        .collection('messages');
    try {
      query = query.orderBy('timestamp', descending: true).limit(50);
    } catch (_) {
      query = query.limit(50);
    }
    return query.snapshots().map((snap) {
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['senderId'] != userId && data['isSeen'] != true) {
          return true;
        }
      }
      return false;
    });
  }

  /// Live unread badge stream — refreshes when conversations update.
  Stream<int> watchUnreadCount(String userId, {int maxChats = 25}) {
    final controller = StreamController<int>.broadcast();
    Timer? debounce;
    StreamSubscription<List<ChatModel>>? chatsSub;

    Future<void> refresh() async {
      try {
        final count = await getUnreadCount(userId, maxChats: maxChats);
        if (!controller.isClosed) controller.add(count);
      } catch (_) {
        if (!controller.isClosed) controller.add(0);
      }
    }

    void scheduleRefresh() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 400), refresh);
    }

    chatsSub = getUserChats(userId).listen(
      (_) => scheduleRefresh(),
      onError: (_) {},
    );
    unawaited(refresh());

    final poll = Timer.periodic(
      const Duration(seconds: 10),
      (_) => scheduleRefresh(),
    );

    controller.onCancel = () {
      debounce?.cancel();
      poll.cancel();
      chatsSub?.cancel();
    };

    return controller.stream;
  }

  // Get user conversations (alias for getUserChats for compatibility)
  Stream<List<ChatModel>> getUserConversations(String userId) {
    return getUserChats(userId);
  }

  // Delete a conversation (soft delete - marks as deleted for user)
  Future<bool> deleteConversation(String userId, String conversationId) async {
    try {
      // Verify user is a participant
      final chatDoc = await _firestore
          .collection('messages')
          .doc(conversationId)
          .get();
      if (!chatDoc.exists) {
        return false;
      }

      final participants = List<String>.from(
        chatDoc.data()?['participants'] ?? [],
      );
      if (!participants.contains(userId)) {
        return false;
      }

      // Use soft delete - mark conversation as deleted for this user
      // This way the conversation still exists for the other participant
      final deletedFor = List<String>.from(chatDoc.data()?['deletedFor'] ?? []);

      if (!deletedFor.contains(userId)) {
        deletedFor.add(userId);
        final result = await HybridDatastore.updateChat(
          id: conversationId,
          patch: {'deletedFor': deletedFor},
        );
        if (!result.isSuccess) throw Exception(result.failureMessage);
      }

      return true;
    } catch (e) {
      print('Error deleting conversation: $e');
      return false;
    }
  }

  // Get client-attorney chats for staff (staff feedback)
  // Staff can see all chats between clients and their assigned attorney
  Stream<List<ChatModel>> getClientChatsForStaff(
    String attorneyId,
    String staffId,
  ) {
    // Use async generator to handle staff email lookup
    return _getClientChatsForStaffStream(attorneyId, staffId);
  }

  Stream<List<ChatModel>> _getClientChatsForStaffStream(
    String attorneyId,
    String staffId,
  ) async* {
    try {
      // Get staff email for querying chats with email identifier
      String? staffEmail;
      try {
        final staffDoc = await _firestore
            .collection('users')
            .doc(staffId)
            .get();
        staffEmail = staffDoc.data()?['email'];
      } catch (e) {
        // If can't get email, continue without it
      }

      // Query for chats linked to the attorney (client-attorney chats)
      // Only query if attorneyId is not empty
      Stream<QuerySnapshot>? attorneyChatsStream;
      if (attorneyId.isNotEmpty) {
        attorneyChatsStream = _firestore
            .collection('messages')
            .where('attorneyId', isEqualTo: attorneyId)
            .snapshots();
      }

      // Query for direct client-staff chats (by staffId)
      final staffChatsStream = _firestore
          .collection('messages')
          .where('staffId', isEqualTo: staffId)
          .snapshots();

      // Query for chats with staffEmail (chats created without finding staff first)
      Stream<QuerySnapshot>? staffEmailChatsStream;
      if (staffEmail != null) {
        staffEmailChatsStream = _firestore
            .collection('messages')
            .where('staffEmail', isEqualTo: staffEmail)
            .snapshots();
      }

      // Combine all streams
      final StreamController<List<ChatModel>> controller =
          StreamController<List<ChatModel>>.broadcast();
      final Map<String, ChatModel> allChatsMap = <String, ChatModel>{};
      StreamSubscription? attorneySub;
      StreamSubscription? staffSub;
      StreamSubscription? staffEmailSub;

      void updateStream() {
        // Filter out attorney-client conversations (where attorneyId is set but staffId is not)
        // Staff should only see direct staff-client chats
        final List<ChatModel> filteredChats = allChatsMap.values.where((chat) {
          // Exclude pure attorney-client conversations (no staffId and no staffEmail)
          if (chat.attorneyId != null &&
              chat.staffId == null &&
              chat.staffEmail == null) {
            return false; // This is an attorney-client chat, exclude it
          }
          // Include all other chats (staff-client chats)
          return true;
        }).toList();

        filteredChats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        if (!controller.isClosed) {
          controller.add(filteredChats);
        }
      }

      // Emit initial empty list immediately to prevent stuck loading state
      updateStream();

      // Listen to attorney chats (only if stream exists)
      if (attorneyChatsStream != null) {
        attorneySub = attorneyChatsStream.listen(
          (snapshot) {
            for (var doc in snapshot.docs) {
              allChatsMap[doc.id] = ChatModel.fromFirestore(doc);
            }
            updateStream();
          },
          onError: (error) {
            if (!controller.isClosed) {
              controller.addError(error);
            }
          },
        );
      }

      // Listen to staff chats (by staffId)
      staffSub = staffChatsStream.listen(
        (snapshot) {
          for (var doc in snapshot.docs) {
            allChatsMap[doc.id] = ChatModel.fromFirestore(doc);
          }
          updateStream();
        },
        onError: (error) {
          if (!controller.isClosed) {
            controller.addError(error);
          }
        },
      );

      // Listen to staff chats (by staffEmail - chats created without finding staff first)
      if (staffEmailChatsStream != null) {
        staffEmailSub = staffEmailChatsStream.listen(
          (snapshot) {
            for (var doc in snapshot.docs) {
              // Update chat to include staffId if not present
              final chatData = doc.data() as Map<String, dynamic>;
              if (chatData['staffId'] == null) {
                doc.reference.update({'staffId': staffId});
              }
              allChatsMap[doc.id] = ChatModel.fromFirestore(doc);
            }
            updateStream();
          },
          onError: (error) {
            if (!controller.isClosed) {
              controller.addError(error);
            }
          },
        );
      }

      // Cleanup on cancel
      controller.onCancel = () {
        attorneySub?.cancel();
        staffSub?.cancel();
        staffEmailSub?.cancel();
      };

      // Yield the stream
      yield* controller.stream;
    } catch (e) {
      throw Exception('Failed to get client chats for staff: $e');
    }
  }

  // Get or access a chat by chatId (for staff to reply to client messages)
  Future<String?> getChatById(String chatId) async {
    try {
      final chatDoc = await _firestore.collection('messages').doc(chatId).get();
      if (chatDoc.exists) {
        return chatDoc.id;
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get chat: $e');
    }
  }

  // Check if staff can access a chat (staff must be in the chat or assigned to the attorney in the chat)
  // Staff can access chats for feedback purposes even if not directly assigned
  Future<bool> canStaffAccessChat(String staffId, String chatId) async {
    try {
      // Get staff email
      final staffDoc = await _firestore.collection('users').doc(staffId).get();
      if (!staffDoc.exists) {
        return false;
      }
      final staffEmail = staffDoc.data()?['email'];

      // Get chat document
      final chatDoc = await _firestore.collection('messages').doc(chatId).get();
      if (!chatDoc.exists) {
        return false;
      }

      final chatData = chatDoc.data()!;

      // Check if staff is directly in the chat (staffId matches)
      final chatStaffId = chatData['staffId'];
      if (chatStaffId == staffId) {
        return true;
      }

      // Check if chat was created with staff email (chats created without finding staff first)
      if (staffEmail != null) {
        final chatStaffEmail = chatData['staffEmail'];
        if (chatStaffEmail == staffEmail) {
          // Update chat to include staffId for future queries
          await chatDoc.reference.update({'staffId': staffId});
          return true;
        }
      }

      // Also check if staff's assigned attorney matches chat's attorney
      final assignedAttorneyId = staffDoc.data()?['assignedAttorneyId'];
      if (assignedAttorneyId != null) {
        final chatAttorneyId = chatData['attorneyId'];
        if (chatAttorneyId == assignedAttorneyId) {
          return true;
        }
      }

      // Allow access if staff has any assigned attorney and chat has an attorney
      // This allows staff to provide feedback on client messages even if not directly linked
      if (assignedAttorneyId != null && chatData['attorneyId'] != null) {
        // Staff can access if they have an assigned attorney (for feedback purposes)
        return true;
      }

      return false;
    } catch (e) {
      // On error, allow access to prevent blocking staff from providing feedback
      return true;
    }
  }

  // Add or remove reaction to a message
  Future<void> toggleReaction({
    required String chatId,
    required String messageId,
    required String userId,
    required String emoji,
  }) async {
    try {
      final messageRef = _firestore
          .collection('messages')
          .doc(chatId)
          .collection('messages')
          .doc(messageId);

      final messageDoc = await messageRef.get();
      if (!messageDoc.exists) {
        throw Exception('Message not found');
      }

      final data = messageDoc.data()!;

      // Properly convert reactions from Firestore format (Map<String, List<dynamic>>)
      // to Map<String, List<String>>
      Map<String, List<String>> reactions = {};
      if (data['reactions'] != null) {
        final reactionsData = data['reactions'] as Map;
        reactions = Map<String, List<String>>.from(
          reactionsData.map(
            (key, value) => MapEntry(
              key.toString(),
              List<String>.from((value as List).map((e) => e.toString())),
            ),
          ),
        );
      }

      // Messenger-style: User can only have ONE reaction at a time
      // Step 1: Check if user already has this emoji (before removing)
      final clickedEmojiList = reactions[emoji] ?? [];
      final hadThisEmoji = clickedEmojiList.any(
        (uid) => uid.toString() == userId.toString(),
      );

      // Step 2: Remove user from ALL emojis
      final keysToRemove = <String>[];
      for (var entry in reactions.entries) {
        final key = entry.key;
        final userList = List<String>.from(entry.value);
        userList.removeWhere((uid) => uid.toString() == userId.toString());

        if (userList.isEmpty) {
          keysToRemove.add(key);
        } else {
          reactions[key] = userList;
        }
      }

      // Remove empty emoji entries
      for (var key in keysToRemove) {
        reactions.remove(key);
      }

      // Step 3: If they didn't have this emoji, add it (if they had it, we already removed it above - so toggle off)
      if (!hadThisEmoji) {
        final newUserList = List<String>.from(reactions[emoji] ?? []);
        newUserList.add(userId);
        reactions[emoji] = newUserList;
      }
      // If they had it, we already removed it above - so reaction is now removed (toggle off)

      final result = await HybridDatastore.updateChatMessage(
        chatId: chatId,
        id: messageId,
        patch: {'reactions': reactions},
      );
      if (!result.isSuccess) throw Exception(result.failureMessage);
    } catch (e) {
      throw Exception('Failed to toggle reaction: $e');
    }
  }

  // Delete a message
  Future<bool> deleteMessage({
    required String chatId,
    required String messageId,
    required String userId,
  }) async {
    try {
      final messageRef = _firestore
          .collection('messages')
          .doc(chatId)
          .collection('messages')
          .doc(messageId);

      final messageDoc = await messageRef.get();
      if (!messageDoc.exists) {
        return false;
      }

      final data = messageDoc.data()!;
      // Only allow sender to delete their own message
      if (data['senderId'] != userId) {
        return false;
      }

      final deleteResult = await HybridDatastore.deleteChatMessage(
        chatId: chatId,
        id: messageId,
      );
      if (!deleteResult.isSuccess) return false;
      final messagesSnapshot = await _firestore
          .collection('messages')
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      String? newLastMessage;
      if (messagesSnapshot.docs.isNotEmpty) {
        final lastMsg = messagesSnapshot.docs.first.data();
        newLastMessage = lastMsg['text'] ?? 'Attachment';
      }

      final chatResult = await HybridDatastore.updateChat(
        id: chatId,
        patch: {
          'lastMessage': newLastMessage,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      if (!chatResult.isSuccess) return false;

      return true;
    } catch (e) {
      return false;
    }
  }
}
