import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/chat_service.dart';
import '../../models/message_model.dart';
import '../../theme/app_theme.dart';
import 'chat_page.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  String? _currentUserRole;

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists && mounted) {
        setState(() {
          _currentUserRole = userDoc.data()?['role'];
        });
      }
    } catch (e) {
      // Handle error silently
    }
  }

  String? _getOtherUserId(ChatModel chat, String currentUserId) {
    // For attorneys: show client if it's an attorney-client chat, or staff if it's attorney-staff chat
    if (_currentUserRole == 'attorney') {
      // Priority: show client if available (attorney-client chat)
      if (chat.clientId != null && chat.clientId != currentUserId) {
        return chat.clientId;
      }
      // Otherwise show staff if it's an attorney-staff chat
      else if (chat.staffId != null && chat.staffId != currentUserId) {
        return chat.staffId;
      }
      // Fallback: get from participants
      else {
        return chat.participants.firstWhere(
          (id) => id != currentUserId && !id.startsWith('staff_'),
          orElse: () => '',
        );
      }
    }
    // For clients: show attorney if available, otherwise staff
    else if (_currentUserRole == 'client') {
      if (chat.attorneyId != null && chat.attorneyId != currentUserId) {
        return chat.attorneyId;
      } else if (chat.staffId != null && chat.staffId != currentUserId) {
        return chat.staffId;
      } else {
        return chat.participants.firstWhere(
          (id) => id != currentUserId && !id.startsWith('staff_'),
          orElse: () => '',
        );
      }
    }
    // For staff: show client or attorney
    else if (_currentUserRole == 'staff') {
      if (chat.clientId != null && chat.clientId != currentUserId) {
        return chat.clientId;
      } else if (chat.attorneyId != null && chat.attorneyId != currentUserId) {
        return chat.attorneyId;
      } else {
        return chat.participants.firstWhere(
          (id) => id != currentUserId && !id.startsWith('staff_'),
          orElse: () => '',
        );
      }
    }
    // Fallback for unknown roles
    else {
      return chat.participants.firstWhere(
        (id) => id != currentUserId && !id.startsWith('staff_'),
        orElse: () => '',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatService = ChatService();
    final user = FirebaseAuth.instance.currentUser;
    final firestore = FirebaseFirestore.instance;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor: AppTheme.royalBlue,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<ChatModel>>(
        stream: chatService.getUserChats(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final chats = snapshot.data ?? [];

          if (chats.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No messages yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
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

              // Determine the other user ID based on current user's role
              final otherUserId = _getOtherUserId(chat, user.uid);

              if (otherUserId == null || otherUserId.isEmpty) {
                return const SizedBox.shrink();
              }

              return FutureBuilder<DocumentSnapshot>(
                future: firestore.collection('users').doc(otherUserId).get(),
                builder: (context, userSnapshot) {
                  String displayName = 'User';
                  String? userRole;
                  String? userEmail;

                  if (userSnapshot.hasData && userSnapshot.data!.exists) {
                    final userData =
                        userSnapshot.data!.data() as Map<String, dynamic>?;
                    if (userData != null) {
                      displayName =
                          userData['fullName'] ??
                          userData['name'] ??
                          userData['email']?.split('@')[0] ??
                          'User';
                      userRole = userData['role'];
                      userEmail = userData['email'];
                    }
                  }

                  // Determine role label
                  String roleLabel = '';
                  Color roleColor = Colors.grey;
                  if (userRole == 'client') {
                    roleLabel = 'CLIENT';
                    roleColor = AppTheme.royalBlue;
                  } else if (userRole == 'attorney') {
                    roleLabel = 'ATTORNEY';
                    roleColor = AppTheme.gold;
                  } else if (userRole == 'staff') {
                    roleLabel = 'STAFF';
                    roleColor = AppTheme.royalBlue;
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      onTap: () {
                        Get.to(
                          () => ChatPage(
                            attorneyId: otherUserId,
                            attorneyName: displayName,
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: roleColor.withValues(alpha: 0.1),
                              child: Text(
                                displayName.isNotEmpty
                                    ? displayName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: roleColor,
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
                                      Expanded(
                                        child: Text(
                                          displayName,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.darkText,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (roleLabel.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: roleColor.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: roleColor.withValues(
                                                alpha: 0.3,
                                              ),
                                              width: 1,
                                            ),
                                          ),
                                          child: Text(
                                            roleLabel,
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: roleColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (userEmail != null &&
                                      userEmail.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      userEmail,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  if (chat.lastMessage != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      chat.lastMessage!,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${chat.updatedAt.hour.toString().padLeft(2, '0')}:${chat.updatedAt.minute.toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
