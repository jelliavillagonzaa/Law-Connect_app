import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme/app_theme.dart';
import '../../services/chat_service.dart';
import '../../services/profile_service.dart';
import '../../models/message_model.dart';
import '../../widgets/client/message_form_widget.dart';
import 'chat_screen.dart';

class ConversationsListScreen extends StatefulWidget {
  const ConversationsListScreen({super.key});

  @override
  State<ConversationsListScreen> createState() =>
      _ConversationsListScreenState();
}

class _ConversationsListScreenState extends State<ConversationsListScreen> {
  final ChatService _chatService = ChatService();
  final ProfileService _profileService = ProfileService();

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return '';
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays == 0) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[timestamp.weekday - 1];
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final FirebaseFirestore _firestore = FirebaseFirestore.instance;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Messages')),
        body: const Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.lightBackground,
      appBar: AppBar(title: const Text('Messages')),
      body: StreamBuilder<List<ChatModel>>(
        stream: _chatService.getUserConversations(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final conversations = snapshot.data ?? [];

          if (conversations.isEmpty) {
            return const MessageFormWidget();
          }

          return ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              // Get the other user ID (the one that's not the current user)
              // For client-staff chats, prefer staffId if available
              // For client-attorney chats, prefer attorneyId if available
              String otherUserId;
              if (conversation.staffId != null &&
                  conversation.staffId != user.uid) {
                otherUserId = conversation.staffId!;
              } else if (conversation.attorneyId != null &&
                  conversation.attorneyId != user.uid) {
                otherUserId = conversation.attorneyId!;
              } else if (conversation.clientId != null &&
                  conversation.clientId != user.uid) {
                otherUserId = conversation.clientId!;
              } else {
                otherUserId = conversation.participants.firstWhere(
                  (id) => id != user.uid,
                  orElse: () => conversation.participants.isNotEmpty
                      ? conversation.participants[0]
                      : '',
                );
              }

              return Dismissible(
                key: Key(conversation.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: AppTheme.error,
                  child: Icon(Icons.delete, color: AppTheme.white, size: 28),
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
                                  foregroundColor: AppTheme.error,
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
                    conversation.id,
                  );

                  if (success && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Conversation deleted'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: FutureBuilder<DocumentSnapshot>(
                  future: _firestore.collection('users').doc(otherUserId).get(),
                  builder: (context, userSnapshot) {
                    // Check if this is a staff or attorney conversation from chat model
                    final isStaffConversation =
                        conversation.staffId == otherUserId ||
                        conversation.staffId != null ||
                        conversation.staffEmail != null;
                    final isAttorneyConversation =
                        conversation.attorneyId == otherUserId ||
                        conversation.attorneyId != null;

                    // Default name based on conversation type
                    String otherUserName = 'Staff';
                    String? otherUserPhotoUrl;
                    String? userRole =
                        'staff'; // Default to staff for client conversations

                    if (userSnapshot.hasData && userSnapshot.data!.exists) {
                      final userData =
                          userSnapshot.data!.data() as Map<String, dynamic>?;
                      userRole = userData?['role'];

                      // Check for attorney first
                      if (userRole == 'attorney' || isAttorneyConversation) {
                        otherUserName =
                            userData?['fullName'] ??
                            userData?['name'] ??
                            'Attorney';
                      } else if (userRole == 'staff' || isStaffConversation) {
                        otherUserName = 'Staff';
                      } else {
                        // Show actual name for other roles
                        otherUserName =
                            userData?['fullName'] ??
                            userData?['name'] ??
                            'User';
                      }
                      otherUserPhotoUrl = userData?['photoUrl'];
                    }
                    // If user data not loaded, keep default based on conversation type
                    if (isAttorneyConversation && otherUserName == 'Staff') {
                      otherUserName = 'Attorney';
                    }

                    return FutureBuilder<String?>(
                      future: otherUserPhotoUrl == 'local_storage'
                          ? _profileService.getLocalProfilePicture(otherUserId)
                          : Future.value(null),
                      builder: (context, localImageSnapshot) {
                        ImageProvider? backgroundImage;
                        bool showFallback = true;

                        // Check for local storage image first
                        if (otherUserPhotoUrl == 'local_storage' &&
                            localImageSnapshot.hasData &&
                            localImageSnapshot.data != null &&
                            localImageSnapshot.data!.isNotEmpty) {
                          try {
                            final base64String = localImageSnapshot.data!;
                            final imageBytes = base64Decode(base64String);
                            backgroundImage = MemoryImage(
                              Uint8List.fromList(imageBytes),
                            );
                            showFallback = false;
                          } catch (e) {
                            print('Error decoding local image: $e');
                          }
                        }
                        // Check for network URL
                        else if (otherUserPhotoUrl != null &&
                            otherUserPhotoUrl.isNotEmpty &&
                            otherUserPhotoUrl != 'local_storage') {
                          backgroundImage = NetworkImage(otherUserPhotoUrl);
                          showFallback = false;
                        }

                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundImage: backgroundImage,
                              backgroundColor: AppTheme.navy.withOpacity(0.1),
                              child: showFallback
                                  ? Text(
                                      otherUserName.isNotEmpty
                                          ? otherUserName[0].toUpperCase()
                                          : (userRole == 'attorney'
                                                ? 'A'
                                                : (userRole == 'staff'
                                                      ? 'S'
                                                      : 'U')),
                                      style: AppTheme.bodyMedium.copyWith(
                                        color: AppTheme.navy,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    otherUserName,
                                    style: AppTheme.bodyLarge.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (userRole == 'attorney' ||
                                    conversation.attorneyId == otherUserId)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.royalBlue.withOpacity(
                                        0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppTheme.royalBlue.withOpacity(
                                          0.3,
                                        ),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      'ATTORNEY',
                                      style: AppTheme.caption.copyWith(
                                        color: AppTheme.royalBlue,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  )
                                else if (userRole == 'staff' ||
                                    conversation.staffId == otherUserId)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.royalBlue.withOpacity(
                                        0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppTheme.royalBlue.withOpacity(
                                          0.3,
                                        ),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      'STAFF',
                                      style: AppTheme.caption.copyWith(
                                        color: AppTheme.royalBlue,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              conversation.lastMessage ?? 'No messages',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.bodySmall,
                            ),
                            trailing: SizedBox(
                              width: 80,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: () async {
                                      // Stop event propagation to prevent ListTile onTap
                                      final confirmed =
                                          await showDialog<bool>(
                                            context: context,
                                            builder: (BuildContext context) {
                                              return AlertDialog(
                                                title: const Text(
                                                  'Delete Conversation',
                                                ),
                                                content: const Text(
                                                  'Are you sure you want to delete this conversation?',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.of(
                                                          context,
                                                        ).pop(false),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.of(
                                                          context,
                                                        ).pop(true),
                                                    style: TextButton.styleFrom(
                                                      foregroundColor:
                                                          AppTheme.error,
                                                    ),
                                                    child: const Text('Delete'),
                                                  ),
                                                ],
                                              );
                                            },
                                          ) ??
                                          false;

                                      if (confirmed == true) {
                                        final success = await _chatService
                                            .deleteConversation(
                                              user.uid,
                                              conversation.id,
                                            );

                                        if (success && context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Conversation deleted',
                                              ),
                                              backgroundColor: Colors.green,
                                              duration: Duration(seconds: 2),
                                            ),
                                          );
                                        } else if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Failed to delete conversation',
                                              ),
                                              backgroundColor: Colors.red,
                                              duration: Duration(seconds: 2),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      child: const Icon(
                                        Icons.delete_outline,
                                        color: AppTheme.error,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Flexible(
                                    child: Text(
                                      _formatTimestamp(conversation.updatedAt),
                                      style: AppTheme.caption.copyWith(
                                        fontSize: 10,
                                      ),
                                      textAlign: TextAlign.end,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            onTap: () {
                              Get.to(
                                () => ChatScreen(
                                  conversationId: conversation.id,
                                  otherUserId: otherUserId,
                                  otherUserName: otherUserName,
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
