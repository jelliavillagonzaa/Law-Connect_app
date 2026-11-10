import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme/app_theme.dart';
import '../../services/chat_service.dart';
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

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Messages')),
        body: const Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.lightBackground,
      appBar: AppBar(title: const Text('Messages')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _signedInAsBar(user),
          Expanded(
            child: StreamBuilder<List<ChatModel>>(
        stream: _chatService.getUserConversations(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const SizedBox.shrink();
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final conversations = ChatModel.oneThreadPerClient(
            (snapshot.data ?? []).where((c) => c.hasMessages).toList(),
          );

          if (conversations.isEmpty) {
            return const MessageFormWidget();
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              // Get the other user ID (prefer attorneyId for attorney chats, staffId for staff chats)
              String otherUserId;
              if (conversation.attorneyId != null &&
                  conversation.attorneyId != user.uid) {
                otherUserId = conversation.attorneyId!;
              } else if (conversation.staffId != null &&
                  conversation.staffId != user.uid) {
                otherUserId = conversation.staffId!;
              } else if (conversation.clientId != null &&
                  conversation.clientId != user.uid) {
                otherUserId = conversation.clientId!;
              } else {
                otherUserId = conversation.participants.firstWhere(
                  (id) => id != user.uid && !id.startsWith('staff_'),
                  orElse: () => '',
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
                child: Builder(
                  builder: (context) {
                    return FutureBuilder<({String id, String name, String role})>(
                      future: _chatService.chatCounterpartInfo(
                        chatId: conversation.id,
                        currentUserId: user.uid,
                      ),
                      builder: (context, counterpartSnap) {
                        final counterpart = counterpartSnap.data;
                        final isStaff = conversation.isClientStaffChat ||
                            conversation.chatType == 'client_staff' ||
                            counterpart?.role == 'staff' ||
                            (conversation.staffId != null &&
                                conversation.staffId!.isNotEmpty) ||
                            (conversation.staffEmail != null &&
                                conversation.staffEmail!.isNotEmpty);
                        final isAttorney = !isStaff &&
                            (counterpart?.role == 'attorney' ||
                                (conversation.attorneyId != null &&
                                    conversation.attorneyId != user.uid));
                        final otherUserName = (counterpart != null &&
                                counterpart.name.trim().isNotEmpty)
                            ? counterpart.name
                            : (isAttorney ? 'Attorney' : 'Legal Staff');
                        final resolvedOtherId = (counterpart != null &&
                                counterpart.id.isNotEmpty &&
                                counterpart.id != 'staff@gmail.com')
                            ? counterpart.id
                            : (isAttorney
                                ? (conversation.attorneyId ?? otherUserId)
                                : (conversation.staffId ?? otherUserId));
                        final cleanLetterSource = isAttorney
                            ? otherUserName.replaceAll('Atty. ', '').trim()
                            : otherUserName.trim();
                        final letter = cleanLetterSource.isNotEmpty
                            ? cleanLetterSource[0].toUpperCase()
                            : (isAttorney ? 'A' : 'S');
                        final roleBadgeText = isAttorney ? 'ATTORNEY' : 'STAFF';
                        final roleBadgeColor = isAttorney
                            ? AppTheme.royalBlue
                            : const Color(0xFF00897B);

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: roleBadgeColor.withOpacity(0.1),
                          child: Text(
                            letter,
                            style: AppTheme.bodyMedium.copyWith(
                              color: roleBadgeColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: roleBadgeColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: roleBadgeColor.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                roleBadgeText,
                                style: AppTheme.caption.copyWith(
                                  color: roleBadgeColor,
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
                                  final confirmed = await showDialog<bool>(
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
                                                    Navigator.of(context)
                                                        .pop(false),
                                                child: const Text('Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(context)
                                                        .pop(true),
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
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Conversation deleted',
                                          ),
                                          backgroundColor: Colors.green,
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    } else if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
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
                              otherUserId: resolvedOtherId,
                              otherUserName: otherUserName,
                              otherUserRole: counterpart?.role ?? (isAttorney ? 'attorney' : 'staff'),
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
          ),
        ],
      ),
    );
  }

  Widget _signedInAsBar(User user) {
    return Material(
      color: const Color(0xFFE8F0FE),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          'Sending as ${user.displayName?.trim().isNotEmpty == true ? user.displayName : (user.email ?? 'this client account')}'
          '${user.email != null ? ' · ${user.email}' : ''}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A3A6C),
          ),
        ),
      ),
    );
  }
}
