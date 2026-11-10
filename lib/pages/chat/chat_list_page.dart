import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/chat_service.dart';
import '../../models/message_model.dart';
import '../../models/user_model.dart';
import '../../theme/app_theme.dart';
import '../../screens/client/chat_screen.dart';
import '../../screens/attorney/attorney_client_chat_screen.dart';
import '../../screens/staff/staff_client_chat_screen.dart';
import '../../widgets/common/nav_unread_dot.dart';

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
    // For clients: prefer attorney if it's an attorney chat, or staff if it's a staff chat
    else if (_currentUserRole == 'client') {
      if (chat.attorneyId != null && chat.attorneyId != currentUserId) {
        return chat.attorneyId;
      } else if (chat.staffId != null && chat.staffId != currentUserId) {
        return chat.staffId;
      } else {
        return chat.participants.firstWhere(
          (id) => id != currentUserId && !id.startsWith('staff_'),
          orElse: () => chat.staffId ?? '',
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

  final ChatService _chatService = ChatService();
  Stream<List<ChatModel>>? _inboxStream;
  String? _streamUserId;

  static final Map<String, Map<String, dynamic>> _userProfileCache = {};
  static final Set<String> _pendingUserFetches = {};

  void _ensureUserProfile(String uid) {
    if (uid.isEmpty || _userProfileCache.containsKey(uid) || _pendingUserFetches.contains(uid)) return;
    _pendingUserFetches.add(uid);
    FirebaseFirestore.instance.collection('users').doc(uid).get().then((doc) {
      _pendingUserFetches.remove(uid);
      if (doc.exists && doc.data() != null) {
        _userProfileCache[uid] = doc.data()!;
        if (mounted) setState(() {});
      }
    }).catchError((_) {
      _pendingUserFetches.remove(uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    if (_inboxStream == null || _streamUserId != user.uid) {
      _streamUserId = user.uid;
      _inboxStream = _chatService.watchInboxChats(user.uid);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor: AppTheme.royalBlue,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<ChatModel>>(
        stream: _inboxStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const SizedBox.shrink();
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final chats = ChatModel.oneThreadPerClient(
            (snapshot.data ?? []).where((chat) => chat.hasMessages).toList(),
          );

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

              final cachedUserData = _userProfileCache[otherUserId];
              if (cachedUserData == null) {
                _ensureUserProfile(otherUserId);
              }

              String displayName = 'User';
              String? userRole;
              String? userEmail;

              if (cachedUserData != null) {
                displayName = UserModel.resolveDisplayName(cachedUserData);
                userRole = cachedUserData['role'];
                userEmail = cachedUserData['email'];
              } else if (chat.clientName != null && chat.clientName!.trim().isNotEmpty) {
                displayName = chat.clientName!.trim();
              }

              if (chat.clientId == otherUserId) {
                if (userRole != null && userRole != 'client') {
                  return const SizedBox.shrink();
                }
                if (ChatModel.isPlaceholderClientLabel(displayName) &&
                    (userEmail == null || userEmail.trim().isEmpty)) {
                  return const SizedBox.shrink();
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
                roleColor = AppTheme.royalBlue;
                if (!displayName.startsWith('Atty.') &&
                    displayName.trim().isNotEmpty &&
                    displayName != 'User' &&
                    displayName != 'Attorney') {
                  displayName = 'Atty. $displayName';
                }
              } else if (userRole == 'staff') {
                roleLabel = 'STAFF';
                roleColor = const Color(0xFF00897B);
              } else {
                roleLabel = 'STAFF';
                roleColor = const Color(0xFF00897B);
              }

              final storedUnread = chat.unreadCountFor(user.uid);
              final hasUnread = storedUnread > 0;
              final unreadLabel = storedUnread > 0
                  ? (storedUnread > 99 ? '99+' : '$storedUnread')
                  : null;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  onTap: () {
                    if (_currentUserRole == 'attorney' &&
                        userRole == 'client') {
                      Get.to(
                        () => AttorneyClientChatScreen(
                          chatId: chat.id,
                          clientId: otherUserId,
                          clientName: displayName,
                        ),
                      );
                    } else if (_currentUserRole == 'staff' &&
                        userRole == 'client') {
                      Get.to(
                        () => StaffClientChatScreen(
                          chatId: chat.id,
                          clientId: otherUserId,
                          clientName: displayName,
                        ),
                      );
                    } else {
                      Get.to(
                        () => ChatScreen(
                          conversationId: chat.id,
                          otherUserId: otherUserId,
                          otherUserName: displayName,
                        ),
                      );
                    }
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
                                            fontWeight: hasUnread
                                                ? FontWeight.bold
                                                : FontWeight.w600,
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
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '${chat.updatedAt.hour.toString().padLeft(2, '0')}:${chat.updatedAt.minute.toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                if (unreadLabel != null)
                                  Container(
                                    constraints:
                                        const BoxConstraints(minWidth: 22),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE53935),
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: Text(
                                      unreadLabel,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  )
                                else if (hasUnread)
                                  const ListUnreadDot(),
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
      ),
    );
  }
}
