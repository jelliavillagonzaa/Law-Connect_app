import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';
import '../../services/chat_service.dart';
import '../../services/chat_session.dart';
import '../../models/message_model.dart';
import '../../models/user_model.dart';

class ChatScreen extends StatefulWidget {
  final String otherUserId;
  final String otherUserName;
  final String? otherUserRole;
  final String? conversationId; // Optional, if starting a new chat

  const ChatScreen({
    super.key,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserRole,
    this.conversationId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _conversationId;
  bool _isInitializing = true;
  bool _hasError = false;
  String? _errorMessage;
  String _displayName = '';
  String? _otherUserRole;
  String? _attorneyId;
  String? _staffId;
  StreamSubscription<List<MessageModel>>? _messagesSub;

  // Color palette
  static const Color primaryColor = AppTheme.royalBlue;
  static const Color backgroundColor = AppTheme.lightGray;

  @override
  void initState() {
    super.initState();
    _displayName = widget.otherUserName;
    _otherUserRole = widget.otherUserRole;
    if (widget.conversationId != null && widget.conversationId!.isNotEmpty) {
      _conversationId = widget.conversationId;
      ChatSession.open(_conversationId);
      _isInitializing = false;
    }
    unawaited(_initializeChat());
  }

  /// Show error dialog with proper styling
  Future<void> _showErrorDialog(BuildContext context, String message) async {
    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.white,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color.fromRGBO(
                    244,
                    67,
                    54,
                    0.1,
                  ), // AppTheme.error with 0.1 opacity
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline,
                  color: AppTheme.error,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Error',
                  style: AppTheme.heading4.copyWith(
                    color: primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'OK',
                style: AppTheme.bodyMedium.copyWith(
                  color: primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _initializeChat() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _hasError = true;
          _errorMessage = 'User not authenticated. Please log in.';
        });
      }
      return;
    }

    try {
      final activeConvId = widget.conversationId ?? _conversationId;
      if (activeConvId != null && activeConvId.isNotEmpty) {
        Map<String, dynamic>? cdata;
        try {
          final convDoc = await _firestore
              .collection('messages')
              .doc(activeConvId)
              .get();
          if (convDoc.exists) {
            cdata = convDoc.data() ?? {};
            _attorneyId = (cdata['attorneyId'] as String?)?.trim();
            _staffId = (cdata['staffId'] as String?)?.trim();
          }
        } catch (_) {}

        final counterpart = await _chatService.chatCounterpartInfo(
          chatId: activeConvId,
          currentUserId: user.uid,
          cachedChatData: cdata,
        );

        if (mounted) {
          setState(() {
            _displayName = (widget.otherUserName.isNotEmpty &&
                    widget.otherUserName.toLowerCase() != 'user')
                ? widget.otherUserName
                : counterpart.name;
            _otherUserRole = (widget.otherUserRole != null &&
                    widget.otherUserRole!.isNotEmpty)
                ? widget.otherUserRole
                : counterpart.role;
            _conversationId = activeConvId;
            _isInitializing = false;
            _hasError = false;
          });
          ChatSession.open(activeConvId);
          _chatService.markMessagesAsSeen(activeConvId, user.uid);
          _listenForSeenUpdates(activeConvId, user.uid);
        }
        return;
      }

      final info = await _chatService.getOrCreateClientOfficeChatWithCounterpart(user.uid);
      if (mounted) {
        setState(() {
          _displayName = info.counterpart.name;
          _otherUserRole = info.counterpart.role;
          _conversationId = info.chatId;
          _isInitializing = false;
          _hasError = false;
        });
        ChatSession.open(info.chatId);
        _chatService.markMessagesAsSeen(info.chatId, user.uid);
        _listenForSeenUpdates(info.chatId, user.uid);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _hasError = true;
          _errorMessage = 'Failed to initialize chat. Please try again.';
        });
        _showErrorDialog(context, _errorMessage!);
      }
    }
  }

  void _listenForSeenUpdates(String chatId, String userId) {
    _messagesSub?.cancel();
    _messagesSub = _chatService.getMessagesWithNotifications(chatId).listen(
      (_) => _chatService.markMessagesAsSeenDebounced(chatId, userId),
      onError: (_) {},
    );
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _conversationId == null) {
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showErrorDialog(context, 'User not authenticated. Please log in.');
        return;
      }

      // Do not hardcode senderRole as 'client' — attorneys/staff also use this
      // screen (e.g. attorney ↔ staff). ChatService resolves role from the
      // signed-in user profile; claiming 'client' rejects non-client logins.
      await _chatService.sendMessage(
        chatId: _conversationId!,
        senderId: user.uid,
        text: _messageController.text.trim(),
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
      if (mounted) {
        _showErrorDialog(context, _friendlySendError(e));
      }
    }
  }

  String _friendlySendError(Object e) {
    var msg = e.toString();
    while (msg.startsWith('Exception: ')) {
      msg = msg.substring('Exception: '.length);
    }
    const prefix = 'Failed to send message: ';
    if (msg.startsWith(prefix)) {
      msg = msg.substring(prefix.length);
      while (msg.startsWith('Exception: ')) {
        msg = msg.substring('Exception: '.length);
      }
    }
    if (msg.trim().isEmpty) {
      return 'Failed to send message. Please try again.';
    }
    return msg.trim();
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
    if (user == null || _conversationId == null) return;

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
                    chatId: _conversationId!,
                    messageId: message.id,
                    userId: user.uid,
                    emoji: emoji,
                  );
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) {
                    _showErrorDialog(context, 'Failed to add reaction: $e');
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
    if (user == null || _conversationId == null) return;

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
          chatId: _conversationId!,
          messageId: message.id,
          userId: user.uid,
        );
      } catch (e) {
        if (mounted) {
          _showErrorDialog(context, 'Failed to delete message: $e');
        }
      }
    }
  }

  String _cleanSenderName(MessageModel message) {
    var name = (message.senderName ?? '').trim();
    final role = (message.senderRole ?? '').toLowerCase();

    final isStf = _otherUserRole == 'staff' ||
        role == 'staff' ||
        (_staffId != null &&
            _staffId!.isNotEmpty &&
            message.senderId == _staffId);

    if (isStf) {
      if (name.isEmpty ||
          name.toLowerCase() == 'user' ||
          name.toLowerCase() == 'attorney' ||
          name.toLowerCase().startsWith('atty.')) {
        return (_displayName.isNotEmpty &&
                _displayName.toLowerCase() != 'attorney' &&
                !_displayName.toLowerCase().startsWith('atty.'))
            ? _displayName
            : 'Legal Staff';
      }
      return name;
    }

    final isAtt = _otherUserRole == 'attorney' ||
        role == 'attorney' ||
        (_attorneyId != null &&
            _attorneyId!.isNotEmpty &&
            message.senderId == _attorneyId);

    if (isAtt) {
      if (name.isEmpty ||
          name.toLowerCase() == 'user' ||
          name.toLowerCase() == 'staff' ||
          name.toLowerCase() == 'legal staff' ||
          name.toLowerCase() == 'law connect') {
        if (_displayName.isNotEmpty &&
            _displayName.toLowerCase() != 'staff' &&
            _displayName.toLowerCase() != 'legal staff') {
          return _displayName;
        }
        return 'Attorney';
      }
      if (name.toLowerCase() == 'attorney') {
        return 'Attorney';
      }
      if (!name.startsWith('Atty.')) {
        name = 'Atty. $name';
      }
      return name;
    }

    if (name.isNotEmpty && name.toLowerCase() != 'user') {
      return name;
    }
    return _displayName.isNotEmpty ? _displayName : widget.otherUserName;
  }

  Widget _buildMessageBubble(MessageModel message, String currentUserId) {
    final isMe = message.senderId == currentUserId;
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
            // Avatar for other user messages (left side)
            Builder(
              builder: (context) {
                final isAttorney = _otherUserRole == 'attorney';
                final roleColor = isAttorney
                    ? AppTheme.royalBlue
                    : const Color(0xFF00897B);
                final senderLabel = _cleanSenderName(message);
                final cleanSender = isAttorney
                    ? senderLabel.replaceAll('Atty. ', '').trim()
                    : senderLabel.trim();
                final letter = cleanSender.isNotEmpty
                    ? cleanSender[0].toUpperCase()
                    : (isAttorney ? 'A' : 'S');

                return Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: roleColor,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      letter,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
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
                          ? const Color(
                              0xFF2196F3,
                            ) // Bright blue for my messages
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
                              _cleanSenderName(message),
                              style: const TextStyle(
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
                        final hasMyReaction =
                            user != null && userIds.contains(user.uid);

                        return GestureDetector(
                          onTap: () {
                            if (user != null && _conversationId != null) {
                              _chatService.toggleReaction(
                                chatId: _conversationId!,
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
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }

  @override
  void dispose() {
    ChatSession.close(_conversationId);
    _messagesSub?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    // Loading state
    if (_isInitializing && _conversationId == null) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: primaryColor,
          title: Text(
            _displayName.isEmpty ? widget.otherUserName : _displayName,
            style: const TextStyle(color: Colors.white),
          ),
        ),
        body: const SizedBox.expand(),
      );
    }

    // Error state
    if (_hasError || user == null || _conversationId == null) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: primaryColor,
          title: Text(
            _displayName.isEmpty ? widget.otherUserName : _displayName,
            style: const TextStyle(color: Colors.white),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Color.fromRGBO(
                      244,
                      67,
                      54,
                      0.1,
                    ), // AppTheme.error with 0.1 opacity
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppTheme.error,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Unable to Load Chat',
                  style: AppTheme.heading3.copyWith(
                    color: primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _errorMessage ??
                      'Failed to initialize chat. Please try again.',
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isInitializing = true;
                      _hasError = false;
                    });
                    _initializeChat();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(
        0xFFF8FAFC,
      ), // Light gray background like in the image
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        shadowColor: Colors.black.withOpacity(0.08),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Builder(
          builder: (context) {
            final isAttorney = _otherUserRole == 'attorney';
            final roleColor =
                isAttorney ? AppTheme.royalBlue : const Color(0xFF00897B);
            final roleText = isAttorney ? 'ATTORNEY' : 'STAFF';

            var cleanName = _displayName.trim();
            if (cleanName.isEmpty) cleanName = widget.otherUserName.trim();

            if (isAttorney) {
              if (cleanName.isEmpty ||
                  cleanName.toLowerCase() == 'user' ||
                  cleanName.toLowerCase() == 'staff' ||
                  cleanName.toLowerCase() == 'legal staff') {
                cleanName = 'Attorney';
              } else if (cleanName.toLowerCase() == 'attorney') {
                cleanName = 'Attorney';
              } else if (!cleanName.startsWith('Atty.')) {
                cleanName = 'Atty. $cleanName';
              }
            } else {
              if (cleanName.isEmpty ||
                  cleanName.toLowerCase() == 'user' ||
                  cleanName.toLowerCase() == 'attorney' ||
                  cleanName.toLowerCase().startsWith('atty.')) {
                cleanName = 'Legal Staff';
              }
            }

            final letterSource = isAttorney
                ? cleanName.replaceAll('Atty. ', '').trim()
                : cleanName.trim();
            final letter = letterSource.isNotEmpty
                ? letterSource[0].toUpperCase()
                : (isAttorney ? 'A' : 'S');

            return Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: roleColor.withOpacity(0.12),
                  child: Text(
                    letter,
                    style: TextStyle(
                      color: roleColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        cleanName,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: roleColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: roleColor.withOpacity(0.3),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              roleText,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: roleColor,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      body: Column(
        children: [
          _signedInBanner(),
          Expanded(
            child: StreamBuilder<List<MessageModel>>(
              stream: _chatService.getMessagesWithNotifications(
                _conversationId!,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const SizedBox.shrink();
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 64,
                            color: AppTheme.error,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Error loading messages',
                            style: AppTheme.heading4.copyWith(
                              color: primaryColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            snapshot.error.toString(),
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
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
                          'Start the conversation!',
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
                    final widgets = <Widget>[];

                    // Add date separator if needed
                    if (_shouldShowDateSeparator(messages, index)) {
                      widgets.add(
                        _buildDateSeparator(_formatDate(message.timestamp)),
                      );
                    }

                    // Add message bubble
                    widgets.add(_buildMessageBubble(message, user.uid));

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: widgets,
                    );
                  },
                );
              },
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
                      icon: Icon(Icons.send, color: Colors.grey[600], size: 20),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _signedInBanner() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    return Material(
      color: const Color(0xFFE8F0FE),
      child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: _firestore.collection('users').doc(user.uid).get(),
        builder: (context, snap) {
          var name = (user.displayName ?? '').trim();
          if (snap.hasData && snap.data!.exists) {
            name = UserModel.resolveDisplayName(snap.data!.data() ?? {});
          }
          final email = user.email ?? '';
          final label = name.isNotEmpty && name != 'User'
              ? name
              : (email.isNotEmpty ? email : 'this client account');
          final extra =
              name.isNotEmpty && name != 'User' && email.isNotEmpty
                  ? ' · $email'
                  : '';
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              'Sending as $label$extra',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A3A6C),
              ),
            ),
          );
        },
      ),
    );
  }
}
