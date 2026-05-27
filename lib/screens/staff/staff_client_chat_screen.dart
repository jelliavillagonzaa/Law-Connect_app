import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import '../../services/chat_service.dart';
import '../../services/staff_auth_service.dart';
import '../../models/message_model.dart';
import '../../theme/app_theme.dart';

class StaffClientChatScreen extends StatefulWidget {
  final String chatId;
  final String clientId;
  final String clientName;

  const StaffClientChatScreen({
    super.key,
    required this.chatId,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<StaffClientChatScreen> createState() => _StaffClientChatScreenState();
}

class _StaffClientChatScreenState extends State<StaffClientChatScreen> {
  final ChatService _chatService = ChatService();
  final StaffAuthService _staffAuthService = StaffAuthService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = true;
  bool _hasScrolledToBottom =
      false; // Track if we've scrolled to bottom initially
  bool _canSend = false; // Track if message can be sent

  @override
  void initState() {
    super.initState();
    _initializeChat();
    // Listen to text changes to update send button state
    _messageController.addListener(() {
      final canSend = _messageController.text.trim().isNotEmpty;
      if (_canSend != canSend) {
        setState(() {
          _canSend = canSend;
        });
      }
    });
  }

  Future<void> _initializeChat() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Set loading to false immediately to show messages
      setState(() => _isLoading = false);

      // Get staff info asynchronously (don't block UI)
      _staffAuthService
          .getCurrentStaff()
          .then((staff) {
            if (staff != null && mounted) {
              // Mark messages as seen
              _chatService.markMessagesAsSeen(widget.chatId, user.uid);
            }
          })
          .catchError((e) {
            print('Error loading staff info: $e');
            // Don't block message display even if staff info fails
          });
    } catch (e) {
      setState(() => _isLoading = false);
      print('Error initializing chat: $e');
      // Don't show error snackbar - allow messages to display
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Get.snackbar('Error', 'You must be logged in to send messages');
        return;
      }

      await _chatService.sendMessage(
        chatId: widget.chatId,
        senderId: user.uid,
        text: _messageController.text.trim(),
        senderRole: 'staff',
      );

      _messageController.clear();

      // Scroll to bottom
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      print('Error sending message: $e');
      Get.snackbar(
        'Error',
        'Failed to send message: ${e.toString()}',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
    }
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
      return Scaffold(
        appBar: AppBar(
          title: Text(
            widget.clientName,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppTheme.royalBlue,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    // Only block if user is null - allow messages to display even if staffId is not set yet
    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            widget.clientName,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppTheme.royalBlue,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // Light gray background
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Message', // Changed from widget.clientName
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.black87,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<MessageModel>>(
              stream: _chatService.getMessages(widget.chatId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red[300],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Error loading messages',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${snapshot.error}',
                            style: TextStyle(fontSize: 14, color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final messages = snapshot.data ?? [];

                // Auto-scroll to bottom when messages first load
                if (messages.isNotEmpty && !_hasScrolledToBottom) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollController.hasClients && mounted) {
                      _scrollController.jumpTo(
                        _scrollController.position.maxScrollExtent,
                      );
                      _hasScrolledToBottom = true;
                    }
                  });
                }

                if (messages.isEmpty) {
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
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Messages from ${widget.clientName} will appear here',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                          textAlign: TextAlign.center,
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
                    final isStaff = message.senderId == user.uid;
                    final widgets = <Widget>[];
                    
                    // Add date separator if needed
                    if (_shouldShowDateSeparator(messages, index)) {
                      widgets.add(_buildDateSeparator(_formatDate(message.timestamp)));
                    }
                    
                    // Add message bubble
                    widgets.add(_buildMessageBubble(message, isStaff, user.uid));
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: widgets,
                    );
                  },
                );
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }

  String _formatDate(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (messageDate == today) {
      return 'Today';
    } else if (messageDate == yesterday) {
      return 'Yesterday';
    } else {
      // Format: "Dec 03, 2025"
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[dateTime.month - 1]} ${dateTime.day.toString().padLeft(2, '0')}, ${dateTime.year}';
    }
  }

  bool _shouldShowDateSeparator(List<MessageModel> messages, int index) {
    if (index == 0) return true;
    final currentDate = DateTime(
      messages[index].timestamp.year,
      messages[index].timestamp.month,
      messages[index].timestamp.day,
    );
    final previousDate = DateTime(
      messages[index - 1].timestamp.year,
      messages[index - 1].timestamp.month,
      messages[index - 1].timestamp.day,
    );
    return currentDate != previousDate;
  }

  Widget _buildDateSeparator(String dateText) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey[300])),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              dateText,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey[300])),
        ],
      ),
    );
  }

  Future<void> _showReactionPicker(
    BuildContext context,
    MessageModel message,
  ) async {
    final emojis = ['😊', '❤️', '👍', '😢', '👌', '😮', '😂', '😍'];
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

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
            final hasReaction =
                message.reactions?[emoji]?.contains(user.uid) ?? false;
            return GestureDetector(
              onTap: () async {
                try {
                  await _chatService.toggleReaction(
                    chatId: widget.chatId,
                    messageId: message.id,
                    userId: user.uid,
                    emoji: emoji,
                  );
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context); // Close picker even on error
                    Get.snackbar(
                      'Error',
                      'Failed to toggle reaction: ${e.toString()}',
                      backgroundColor: Colors.red,
                      colorText: Colors.white,
                      duration: const Duration(seconds: 3),
                    );
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
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
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
    if (user == null) return;

    // Only allow staff to delete their own messages
    if (message.senderId != user.uid) {
      Get.snackbar(
        'Info',
        'You can only delete your own messages',
        backgroundColor: Colors.blue,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text(
          'Are you sure you want to delete this message? This action cannot be undone.',
        ),
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
          chatId: widget.chatId,
          messageId: message.id,
          userId: user.uid,
        );
        if (mounted) {
          Get.snackbar(
            'Success',
            'Message deleted',
            backgroundColor: Colors.green,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),
          );
        }
      } catch (e) {
        if (mounted) {
          Get.snackbar(
            'Error',
            'Failed to delete message: ${e.toString()}',
            backgroundColor: Colors.red,
            colorText: Colors.white,
            duration: const Duration(seconds: 3),
          );
        }
      }
    }
  }

  Widget _buildMessageBubble(
    MessageModel message,
    bool isStaff,
    String currentUserId,
  ) {
    final timeStr = _formatTime(message.timestamp);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isStaff
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isStaff) ...[
            // Avatar for client messages (left side)
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF17A2B8),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Center(
                child: Text(
                  widget.clientName.isNotEmpty
                      ? widget.clientName[0].toUpperCase()
                      : 'C',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isStaff
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _showReactionPicker(context, message),
                  onDoubleTap: () {
                    // Double-tap to delete (only for own messages)
                    if (isStaff) {
                      _deleteMessage(message);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isStaff
                          ? const Color(
                              0xFF2196F3,
                            ) // Bright blue for staff messages
                          : Colors.white, // White for client messages
                      borderRadius: BorderRadius.circular(18).copyWith(
                        bottomRight: isStaff
                            ? const Radius.circular(4)
                            : const Radius.circular(18),
                        bottomLeft: isStaff
                            ? const Radius.circular(18)
                            : const Radius.circular(4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sender name
                        if (isStaff)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              'Staff',
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
                              widget.clientName,
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
                            color: isStaff ? Colors.white : Colors.black87,
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
                                color: isStaff
                                    ? Colors.white70
                                    : Colors.grey[600],
                              ),
                            ),
                            if (isStaff && message.isSeen == true) ...[
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
                        final hasMyReaction =
                            user != null && userIds.contains(user.uid);

                        return GestureDetector(
                          onTap: () async {
                            if (user != null) {
                              try {
                                await _chatService.toggleReaction(
                                  chatId: widget.chatId,
                                  messageId: message.id,
                                  userId: user.uid,
                                  emoji: emoji,
                                );
                              } catch (e) {
                                if (mounted) {
                                  Get.snackbar(
                                    'Error',
                                    'Failed to toggle reaction: ${e.toString()}',
                                    backgroundColor: Colors.red,
                                    colorText: Colors.white,
                                    duration: const Duration(seconds: 2),
                                  );
                                }
                              }
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
                                Text(
                                  emoji,
                                  style: const TextStyle(fontSize: 14),
                                ),
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
          if (isStaff) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
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
                  decoration: InputDecoration(
                    hintText: 'Type your message...',
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) {
                    if (_canSend) {
                      _sendMessage();
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _canSend ? AppTheme.royalBlue : Colors.grey[300],
                shape: BoxShape.circle,
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.send,
                  color: _canSend ? Colors.white : Colors.grey[600],
                  size: 20,
                ),
                onPressed: _canSend ? _sendMessage : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
