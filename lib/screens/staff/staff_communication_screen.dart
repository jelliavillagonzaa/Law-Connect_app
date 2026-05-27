import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import '../../services/staff_auth_service.dart';
import '../../services/chat_service.dart';
import '../../models/message_model.dart';
import '../../theme/app_theme.dart';
import '../../screens/client/chat_screen.dart';
import 'staff_client_chat_screen.dart';

class StaffCommunicationScreen extends StatefulWidget {
  const StaffCommunicationScreen({super.key});

  @override
  State<StaffCommunicationScreen> createState() =>
      _StaffCommunicationScreenState();
}

class _StaffCommunicationScreenState extends State<StaffCommunicationScreen> {
  final StaffAuthService _staffAuthService = StaffAuthService();
  final ChatService _chatService = ChatService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _assignedAttorneyId;
  String? _currentStaffId;

  @override
  void initState() {
    super.initState();
    _loadStaffInfo();
  }

  Future<void> _loadStaffInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentStaffId = user.uid;
    }

    final staff = await _staffAuthService.getCurrentStaff();
    if (staff != null) {
      setState(() {
        _assignedAttorneyId = staff.assignedAttorneyId;
        _currentStaffId = staff.id;
      });
    }
  }

  // Get all conversations for staff (both client and attorney)
  Stream<List<ChatModel>> _getAllStaffConversations() {
    if (_currentStaffId == null) {
      return Stream.value([]);
    }

    // Get client conversations
    final clientChatsStream = _chatService.getClientChatsForStaff(
      _assignedAttorneyId ?? '',
      _currentStaffId!,
    );

    // Get all user conversations to find attorney conversation
    final allConversationsStream = _chatService.getUserConversations(
      _currentStaffId!,
    );

    // Combine both streams
    final StreamController<List<ChatModel>> controller =
        StreamController<List<ChatModel>>.broadcast();
    final Map<String, ChatModel> allChatsMap = <String, ChatModel>{};

    StreamSubscription? clientSub;
    StreamSubscription? allConversationsSub;

    void updateStream() {
      final List<ChatModel> mergedChats = allChatsMap.values.where((chat) {
        // Include client chats (from getClientChatsForStaff)
        if (chat.clientId != null && chat.clientId!.isNotEmpty) {
          return true;
        }
        // Include attorney chat if it's with assigned attorney and no client
        if (_assignedAttorneyId != null &&
            chat.attorneyId == _assignedAttorneyId &&
            chat.staffId == _currentStaffId &&
            (chat.clientId == null || chat.clientId!.isEmpty)) {
          return true;
        }
        return false;
      }).toList();

      mergedChats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (!controller.isClosed) {
        controller.add(mergedChats);
      }
    }

    // Listen to client chats
    clientSub = clientChatsStream.listen(
      (chats) {
        for (var chat in chats) {
          allChatsMap[chat.id] = chat;
        }
        updateStream();
      },
      onError: (error) {
        if (!controller.isClosed) {
          controller.addError(error);
        }
      },
    );

    // Listen to all conversations to find attorney chat
    allConversationsSub = allConversationsStream.listen(
      (chats) {
        for (var chat in chats) {
          // Only add if it's an attorney chat with assigned attorney
          if (_assignedAttorneyId != null &&
              chat.attorneyId == _assignedAttorneyId &&
              chat.staffId == _currentStaffId &&
              (chat.clientId == null || chat.clientId!.isEmpty)) {
            allChatsMap[chat.id] = chat;
          }
        }
        updateStream();
      },
      onError: (error) {
        if (!controller.isClosed) {
          controller.addError(error);
        }
      },
    );

    // Cleanup on cancel
    controller.onCancel = () {
      clientSub?.cancel();
      allConversationsSub?.cancel();
    };

    return controller.stream;
  }

  Future<void> _openChatWithAttorney() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Get.snackbar(
        'Error',
        'You must be logged in to send messages',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    if (_assignedAttorneyId == null || _assignedAttorneyId!.isEmpty) {
      Get.snackbar(
        'No Attorney Assigned',
        'You are not assigned to an attorney yet',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
      return;
    }

    try {
      // Get attorney info
      final attorneyDoc = await _firestore
          .collection('users')
          .doc(_assignedAttorneyId!)
          .get();

      if (!attorneyDoc.exists) {
        Get.snackbar(
          'Error',
          'Attorney not found',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      final attorneyData = attorneyDoc.data()!;
      final attorneyName =
          attorneyData['fullName'] ?? attorneyData['name'] ?? 'Attorney';

      // Check if chat already exists
      String? existingChatId;
      final existingChats = await _firestore
          .collection('messages')
          .where('participants', arrayContains: user.uid)
          .get();

      for (var doc in existingChats.docs) {
        final participants = List<String>.from(
          doc.data()['participants'] ?? [],
        );
        final chatData = doc.data();

        // Check if this is a staff-attorney chat (both participants match and no client)
        if (participants.contains(user.uid) &&
            participants.contains(_assignedAttorneyId) &&
            (chatData['clientId'] == null || chatData['clientId'] == '')) {
          existingChatId = doc.id;
          break;
        }
      }

      String chatId;
      if (existingChatId != null) {
        chatId = existingChatId;
      } else {
        // Create new chat with attorney
        chatId = await _chatService.getOrCreateChat(
          user.uid,
          _assignedAttorneyId!,
        );
      }

      // Ensure the chat document has staffId and attorneyId fields
      final chatDoc = await _firestore.collection('messages').doc(chatId).get();
      if (chatDoc.exists) {
        final updateData = <String, dynamic>{};
        final chatData = chatDoc.data()!;

        // Set staffId if not present
        if (chatData['staffId'] != user.uid) {
          updateData['staffId'] = user.uid;
        }

        // Set attorneyId if not present
        if (chatData['attorneyId'] != _assignedAttorneyId) {
          updateData['attorneyId'] = _assignedAttorneyId;
        }

        // Ensure clientId is null for staff-attorney chats
        if (chatData['clientId'] != null && chatData['clientId'] != '') {
          updateData['clientId'] =
              FieldValue.delete(); // Use FieldValue.delete() to remove field
        }

        if (updateData.isNotEmpty) {
          await _firestore
              .collection('messages')
              .doc(chatId)
              .update(updateData);
        }
      }

      // Navigate to chat with the conversationId
      Get.to(
        () => ChatScreen(
          conversationId: chatId,
          otherUserId: _assignedAttorneyId!,
          otherUserName: attorneyName,
        ),
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to open chat: ${e.toString()}',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    if (_currentStaffId == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Client Messages (Staff Feedback)', style: TextStyle()),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'Staff not found',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Messages', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.royalBlue,
        foregroundColor: Colors.white,
        actions: [
          if (_assignedAttorneyId != null && _assignedAttorneyId!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.message),
              tooltip: 'Message Attorney',
              onPressed: _openChatWithAttorney,
            ),
        ],
      ),
      body: StreamBuilder<List<ChatModel>>(
        stream: _getAllStaffConversations(),
        builder: (context, snapshot) {
          // Don't show loading - show empty state immediately if no data yet
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: TextStyle(color: Colors.red),
              ),
            );
          }

          final chats = snapshot.data ?? [];

          if (chats.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No messages yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your conversations will appear here',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chat = chats[index];
              return Dismissible(
                key: Key(chat.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Colors.red,
                  child: const Icon(
                    Icons.delete,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                confirmDismiss: (direction) async {
                  return await showDialog<bool>(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            title: const Text('Delete Conversation'),
                            content: const Text(
                              'Are you sure you want to delete this conversation?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                                child: const Text('Delete'),
                              ),
                            ],
                          );
                        },
                      ) ??
                      false;
                },
                onDismissed: (direction) async {
                  final success = await _chatService.deleteConversation(
                    user.uid,
                    chat.id,
                  );
                  if (success && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Conversation deleted'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: _buildChatCard(chat, user.uid),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildChatCard(ChatModel chat, String staffId) {
    // Determine if this is a client or attorney conversation
    final isClientChat = chat.clientId != null && chat.clientId!.isNotEmpty;
    final isAttorneyChat =
        chat.attorneyId == _assignedAttorneyId &&
        chat.staffId == staffId &&
        chat.clientId == null;

    if (isClientChat) {
      // Client conversation - load client info
      return StreamBuilder<DocumentSnapshot>(
        stream: _firestore.collection('users').doc(chat.clientId!).snapshots(),
        builder: (context, snapshot) {
          String clientName = chat.clientId ?? 'Client';
          String clientEmail = '';

          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>?;
            if (data != null) {
              clientName =
                  data['fullName'] ?? data['name'] ?? chat.clientId ?? 'Client';
              clientEmail = data['email'] ?? '';
            }
          }

          return _buildChatCardUI(
            chat: chat,
            name: clientName,
            email: clientEmail,
            isClient: true,
            onTap: () {
              Get.to(
                () => StaffClientChatScreen(
                  chatId: chat.id,
                  clientId: chat.clientId ?? '',
                  clientName: clientName,
                ),
              );
            },
          );
        },
      );
    } else if (isAttorneyChat) {
      // Attorney conversation - load attorney info
      return StreamBuilder<DocumentSnapshot>(
        stream: _assignedAttorneyId != null
            ? _firestore
                  .collection('users')
                  .doc(_assignedAttorneyId!)
                  .snapshots()
            : null,
        builder: (context, snapshot) {
          String attorneyName = 'Attorney';
          String attorneyEmail = '';

          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>?;
            if (data != null) {
              attorneyName = data['fullName'] ?? data['name'] ?? 'Attorney';
              attorneyEmail = data['email'] ?? '';
            }
          }

          return _buildChatCardUI(
            chat: chat,
            name: attorneyName,
            email: attorneyEmail,
            isClient: false,
            onTap: () {
              Get.to(
                () => ChatScreen(
                  conversationId: chat.id,
                  otherUserId: _assignedAttorneyId!,
                  otherUserName: attorneyName,
                ),
              );
            },
          );
        },
      );
    } else {
      // Fallback - shouldn't happen but handle gracefully
      return _buildChatCardUI(
        chat: chat,
        name: 'Unknown',
        email: '',
        isClient: false,
        onTap: () {},
      );
    }
  }

  Widget _buildChatCardUI({
    required ChatModel chat,
    required String name,
    required String email,
    required bool isClient,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppTheme.royalBlue.withOpacity(0.1),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.royalBlue,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.darkText,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isClient
                                ? AppTheme.royalBlue.withOpacity(0.1)
                                : AppTheme.gold.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isClient
                                  ? AppTheme.royalBlue.withOpacity(0.3)
                                  : AppTheme.gold.withOpacity(0.5),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            isClient ? 'CLIENT' : 'ATTORNEY',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isClient
                                  ? AppTheme.royalBlue
                                  : AppTheme.gold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                    if (chat.lastMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        chat.lastMessage!,
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
