import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import '../../theme/app_theme.dart';
import '../../services/chat_service.dart';
import '../../models/message_model.dart';

class MessageFormWidget extends StatefulWidget {
  const MessageFormWidget({super.key});

  @override
  State<MessageFormWidget> createState() => _MessageFormWidgetState();
}

class _MessageFormWidgetState extends State<MessageFormWidget> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _chatId;
  String? _staffId;
  String? _staffName;
  String? _staffPhotoUrl;
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Create or get chat with staff using email (no need to find staff first)
      _chatId = await _chatService.getOrCreateChatByStaffEmail(
        clientId: user.uid,
        staffEmail: 'staff@gmail.com',
      );

      // Try to get staff info for display (optional)
      try {
        final staffQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: 'staff@gmail.com')
            .limit(1)
            .get();

        if (staffQuery.docs.isNotEmpty) {
          final staffDoc = staffQuery.docs.first;
          final staffData = staffDoc.data();
          if (staffData['role'] == 'staff') {
            _staffId = staffDoc.id;
            _staffName = staffData['fullName'] ?? 
                        staffData['name'] ?? 
                        'Staff Member';
            _staffPhotoUrl = staffData['photoUrl'];
          } else {
            _staffId = 'staff_staff@gmail.com'; // Use email as identifier
            _staffName = 'Staff Member';
          }
        } else {
          _staffId = 'staff_staff@gmail.com'; // Use email as identifier
          _staffName = 'Staff Member';
        }
      } catch (e) {
        // If can't get staff info, use defaults
        _staffId = 'staff_staff@gmail.com';
        _staffName = 'Staff Member';
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _chatId == null) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSending = true);

    try {
      await _chatService.sendMessage(
        chatId: _chatId!,
        senderId: user.uid,
        text: _messageController.text.trim(),
      );

      _messageController.clear();

      // Scroll to bottom
      if (_scrollController.hasClients) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to send message: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      setState(() => _isSending = false);
    }
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }

  Future<void> _showReactionPicker(BuildContext context, MessageModel message) async {
    final emojis = ['😊', '❤️', '👍', '😢', '👌', '😮', '😂', '😍'];
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _chatId == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          alignment: WrapAlignment.center,
          children: emojis.map((emoji) {
            final hasReaction = message.reactions?[emoji]?.contains(user.uid) ?? false;
            return GestureDetector(
              onTap: () async {
                try {
                  await _chatService.toggleReaction(
                    chatId: _chatId!,
                    messageId: message.id,
                    userId: user.uid,
                    emoji: emoji,
                  );
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) {
                    Get.snackbar('Error', 'Failed to add reaction: $e');
                  }
                }
              },
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: hasReaction ? Colors.blue[100] : Colors.grey[100],
                  shape: BoxShape.circle,
                  border: hasReaction
                      ? Border.all(color: Colors.blue, width: 2)
                      : null,
                ),
                child: Center(
                  child: Text(
                    emoji,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _deleteMessage(MessageModel message) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _chatId == null) return;

    if (message.senderId != user.uid) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _chatService.deleteMessage(
          chatId: _chatId!,
          messageId: message.id,
          userId: user.uid,
        );
      } catch (e) {
        Get.snackbar('Error', 'Failed to delete message: $e');
      }
    }
  }

  Widget _buildMessageBubble(MessageModel message, bool isMe, String currentUserId) {
    final timeStr = _formatTime(message.timestamp);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            _buildProfilePicture(
              _staffPhotoUrl,
              _staffName ?? 'Staff',
              size: 36,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onLongPress: () => _deleteMessage(message),
                  onTap: () => _showReactionPicker(context, message),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isMe
                          ? const Color(0xFF2196F3) // Bright blue for my messages
                          : Colors.white, // White for other messages
                      borderRadius: BorderRadius.circular(18).copyWith(
                        bottomRight: isMe
                            ? const Radius.circular(4)
                            : const Radius.circular(18),
                        bottomLeft: isMe
                            ? const Radius.circular(18)
                            : const Radius.circular(4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sender name
                        if (isMe)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              'You',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              message.senderRole == 'staff' ? 'Staff' : (_staffName ?? 'Staff'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        Text(
                          message.text,
                          style: TextStyle(
                            fontSize: 15,
                            color: isMe ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: isMe ? Colors.white70 : Colors.grey[600],
                              ),
                            ),
                            if (isMe && message.isSeen == true) ...[
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.done_all,
                                size: 14,
                                color: Colors.blue,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Reactions display
                if (message.reactions != null && message.reactions!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 4,
                      children: message.reactions!.entries.map((entry) {
                        final emoji = entry.key;
                        final userIds = entry.value;
                        final user = FirebaseAuth.instance.currentUser;
                        final hasMyReaction = user != null && userIds.contains(user.uid);

                        return GestureDetector(
                          onTap: () {
                            if (user != null && _chatId != null) {
                              _chatService.toggleReaction(
                                chatId: _chatId!,
                                messageId: message.id,
                                userId: user.uid,
                                emoji: emoji,
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: hasMyReaction
                                  ? Colors.blue[100]
                                  : Colors.grey[200],
                              borderRadius: BorderRadius.circular(12),
                              border: hasMyReaction
                                  ? Border.all(color: Colors.blue, width: 1)
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(emoji, style: const TextStyle(fontSize: 14)),
                                const SizedBox(width: 4),
                                Text(
                                  '${userIds.length}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildProfilePicture(
    String? photoUrl,
    String name, {
    double size = 40,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey[300],
      ),
      child: photoUrl != null && photoUrl.isNotEmpty
          ? ClipOval(
              child: Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildDefaultAvatar(name, size),
              ),
            )
          : _buildDefaultAvatar(name, size),
    );
  }

  Widget _buildDefaultAvatar(String name, double size) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.fromRGBO(26, 77, 143, 0.1), // royalBlue with 0.1 opacity
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'S',
          style: TextStyle(
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
            color: AppTheme.royalBlue,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Always show chat interface, even if no staff
    return Column(
      children: [
        // Messages List - Light gray background like in the image
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF5F5F5), // Light gray background
            ),
            child: _staffId == null || _chatId == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey[300],
                            border: Border.all(
                              color: Colors.grey[400]!,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.info_outline,
                            size: 32,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No Staff Available',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No staff member is currently assigned yet.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : StreamBuilder<List<MessageModel>>(
                    stream: _chatService.getMessages(_chatId!),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }

                      final messages = snapshot.data ?? [];

                      if (messages.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.message_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No messages yet',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Start a conversation with ${_staffName ?? 'staff'}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 16,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          final user = FirebaseAuth.instance.currentUser;
                          final isMe = message.senderId == user?.uid;
                          return _buildMessageBubble(message, isMe, user?.uid ?? '');
                        },
                      );
                    },
                  ),
          ),
        ),
        // Message Input - White background with rounded input field
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(color: Colors.white),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _messageController,
                      enabled:
                          _staffId != null && _chatId != null && !_isSending,
                      decoration: InputDecoration(
                        hintText: 'Type your message...',
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                      maxLines: null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.grey,
                              ),
                            ),
                          )
                        : Icon(Icons.send, color: Colors.grey[600], size: 20),
                    onPressed:
                        (_staffId != null && _chatId != null && !_isSending)
                        ? _sendMessage
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
