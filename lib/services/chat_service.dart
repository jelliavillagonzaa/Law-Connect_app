import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'dart:async';
import '../models/message_model.dart';
import 'notification_service.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final NotificationService _notificationService = NotificationService();

  // Track last message timestamp to avoid duplicate notifications
  final Map<String, DateTime> _lastNotificationTime = {};

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

      final chatRef = await _firestore.collection('messages').add(chatData);
      return chatRef.id;
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
        if ((clientId != null && staffId == null) || (clientId == null && staffId != null)) {
          chatData['attorneyId'] = attorneyId;
        }
      }
      if (staffId != null) {
        chatData['staffId'] = staffId;
      }

      final chatRef = await _firestore.collection('messages').add(chatData);

      return chatRef.id;
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
      await _firestore
          .collection('messages')
          .doc(chatId)
          .collection('messages')
          .add({
            'chatId': chatId,
            'senderId': senderId,
            'text': text,
            'timestamp': FieldValue.serverTimestamp(),
            'isSeen': false,
            if (finalSenderRole != null) 'senderRole': finalSenderRole,
          });

      // Update chat last message
      await _firestore.collection('messages').doc(chatId).update({
        'lastMessage': text,
        'updatedAt': FieldValue.serverTimestamp(),
      });
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
      final ref = _storage
          .ref()
          .child('chat_attachments/$chatId/${timestamp}_$fileName');

      final uploadTask = ref.putFile(file);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Add message with attachment
      await _firestore
          .collection('messages')
          .doc(chatId)
          .collection('messages')
          .add({
            'chatId': chatId,
            'senderId': senderId,
            'text': text,
            'attachmentUrl': downloadUrl,
            'timestamp': FieldValue.serverTimestamp(),
            'isSeen': false,
          });

      // Update chat last message
      await _firestore.collection('messages').doc(chatId).update({
        'lastMessage': text.isEmpty ? 'Attachment' : text,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to send message with attachment: $e');
    }
  }

  // Get messages for a chat (real-time stream)
  Stream<List<MessageModel>> getMessages(String chatId) {
    try {
      return _firestore
          .collection('messages')
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp', descending: false)
          .snapshots()
          .map((snapshot) {
            return snapshot.docs
                .map((doc) => MessageModel.fromFirestore(doc))
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
        .orderBy('timestamp', descending: false)
        .snapshots()
        .asyncMap((snapshot) async {
          final messages = snapshot.docs
              .map((doc) => MessageModel.fromFirestore(doc))
              .toList();

          // Check for new messages from other users
          if (messages.isNotEmpty && currentUserId != null) {
            final lastMessage = messages.last;

            // Only notify if message is from someone else and is recent
            if (lastMessage.senderId != currentUserId) {
              final messageTime = lastMessage.timestamp;
              final lastNotified = _lastNotificationTime[chatId];

              // Avoid duplicate notifications (only notify if message is within last 5 seconds)
              final now = DateTime.now();
              final timeSinceMessage = now.difference(messageTime).inSeconds;

              if (timeSinceMessage < 5 &&
                  (lastNotified == null || messageTime.isAfter(lastNotified))) {
                _lastNotificationTime[chatId] = messageTime;

                // Get sender info for notification
                try {
                  final senderDoc = await _firestore
                      .collection('users')
                      .doc(lastMessage.senderId)
                      .get();

                  final senderName = senderDoc.data()?['fullName'] ?? 'Someone';

                  // Show notification with sound
                  await _notificationService.showNotificationWithSound(
                    id: DateTime.now().millisecondsSinceEpoch % 100000,
                    title: 'New message from $senderName',
                    body: lastMessage.text.isNotEmpty
                        ? lastMessage.text
                        : 'Sent an attachment',
                    payload: chatId,
                  );
                } catch (e) {
                  // Fallback notification without sender name
                  await _notificationService.showNotificationWithSound(
                    id: DateTime.now().millisecondsSinceEpoch % 100000,
                    title: 'New message',
                    body: lastMessage.text.isNotEmpty
                        ? lastMessage.text
                        : 'Sent an attachment',
                    payload: chatId,
                  );
                }
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

  // Mark messages as seen
  Future<void> markMessagesAsSeen(String chatId, String userId) async {
    try {
      // Get all unread messages (filter in memory to avoid index requirement)
      final messagesSnapshot = await _firestore
          .collection('messages')
          .doc(chatId)
          .collection('messages')
          .where('isSeen', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      int updateCount = 0;

      for (var doc in messagesSnapshot.docs) {
        final data = doc.data();
        // Only update messages from other users
        if (data['senderId'] != null && data['senderId'] != userId) {
          batch.update(doc.reference, {'isSeen': true});
          updateCount++;
        }
      }

      if (updateCount > 0) {
        await batch.commit();
        // Update parent conversation to trigger listeners
        try {
          await _firestore.collection('messages').doc(chatId).update({
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          // Ignore errors updating parent - messages are already marked as seen
          print('Warning: Failed to update parent conversation: $e');
        }
      }
    } catch (e) {
      throw Exception('Failed to mark messages as seen: $e');
    }
  }

  // Get unread message count for a user
  Future<int> getUnreadCount(String userId) async {
    try {
      final chats = await _firestore
          .collection('messages')
          .where('participants', arrayContains: userId)
          .get();

      int totalUnread = 0;
      for (var chatDoc in chats.docs) {
        // Get all unread messages (filter in memory to avoid index requirement)
        final unreadMessages = await _firestore
            .collection('messages')
            .doc(chatDoc.id)
            .collection('messages')
            .where('isSeen', isEqualTo: false)
            .get();

        // Count only messages from other users
        for (var msgDoc in unreadMessages.docs) {
          final data = msgDoc.data();
          if (data['senderId'] != userId) {
            totalUnread++;
          }
        }
      }

      return totalUnread;
    } catch (e) {
      throw Exception('Failed to get unread count: $e');
    }
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
        await _firestore.collection('messages').doc(conversationId).update({
          'deletedFor': deletedFor,
        });
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

      await messageRef.update({'reactions': reactions});
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

      await messageRef.delete();

      // Update chat last message if this was the last message
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

      await _firestore.collection('messages').doc(chatId).update({
        'lastMessage': newLastMessage,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      return false;
    }
  }
}
