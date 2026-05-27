import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/staff_service.dart';
import '../../services/chat_service.dart';
import '../../services/task_service.dart';
import '../../services/staff_auth_service.dart';
import '../../services/hearing_notification_fanout_service.dart';
import '../attorney/attorney_reminders_screen.dart';
import '../../utils/hearing_notification_formatter.dart';
import '../../widgets/common/hearing_notification_detail_panel.dart';

class StaffNotificationsScreen extends StatefulWidget {
  const StaffNotificationsScreen({super.key});

  @override
  State<StaffNotificationsScreen> createState() => _StaffNotificationsScreenState();
}

class _StaffNotificationsScreenState extends State<StaffNotificationsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final StaffService _staffService = StaffService();
  final ChatService _chatService = ChatService();
  final TaskService _taskService = TaskService();
  final StaffAuthService _staffAuthService = StaffAuthService();
  bool _isMarkingAllRead = false;
  String? _assignedAttorneyId;
  /// Expanded Firestore notification cards (key: `type_id`).
  final Set<String> _expandedNotificationKeys = <String>{};

  static String _stringFrom(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    if (value is String) return value;
    return value.toString();
  }

  String _notificationCardKey(Map<String, dynamic> notification) {
    final id = _stringFrom(notification['id']);
    final fsType = _stringFrom(notification['firestoreType']);
    if (fsType.isNotEmpty) {
      return '${fsType}_$id';
    }
    final type = _stringFrom(notification['type']);
    return '${type}_$id';
  }

  static bool _isCourtEmailSpam(String fsType) {
    final t = fsType.toLowerCase();
    return t == 'court_email_ingest' || t.startsWith('court_');
  }

  /// First paragraph / first line / short excerpt for the collapsed row (full body expands on tap).
  String? _messagePreviewSubtitle(
    String message, {
    Map<String, dynamic>? data,
  }) {
    if (data != null) {
      final type = (data['type'] as String? ?? '').toLowerCase();
      if (type.contains('hearing') ||
          (data['hearingDocId'] as String?)?.trim().isNotEmpty == true) {
        final line = HearingNotificationFormatter.buildSummary(data);
        if (line.isNotEmpty) return line;
      }
    }

    final summary = (data?['summary'] as String?)?.trim();
    if (summary != null && summary.isNotEmpty) return summary;
    final t = message.trim();
    if (t.isEmpty) return null;
    final paragraphs = t.split('\n\n');
    if (paragraphs.length >= 2) {
      return paragraphs.first.trim();
    }
    final lines = t.split('\n');
    if (lines.length >= 2) {
      return lines.first.trim();
    }
    if (t.length > 100) {
      return '${t.substring(0, 97)}...';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadStaffData();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final fanout = HearingNotificationFanoutService.instance;
      fanout.attach();
      fanout.warmInbox(uid);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(fanout.syncStaffHearingNotifications(force: true));
        unawaited(fanout.syncRecentHearingsForInbox());
      });
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _notificationsQuery(String staffId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: staffId)
        .limit(200)
        .snapshots();
  }

  Future<void> _loadStaffData() async {
    final staff = await _staffAuthService.getCurrentStaff();
    if (mounted && staff != null) {
      setState(() {
        _assignedAttorneyId = staff.assignedAttorneyId;
      });
    }
  }

  Stream<List<Map<String, dynamic>>> _getOtherNotifications(String staffId) {
    return _notificationsQuery(staffId).asyncMap(
        (QuerySnapshot<Map<String, dynamic>> notificationsSnapshot) async {
      final List<Map<String, dynamic>> allNotifications = [];

      // 1. Firestore notifications (exclude hearings — shown above)
      try {
        final notifRows = notificationsSnapshot.docs.map((doc) {
          final data = doc.data();
          final ts = (data['createdAt'] as Timestamp?)?.toDate();
          final fsType = _stringFrom(data['type']).toLowerCase();
          if (_isCourtEmailSpam(fsType) ||
              hearingOrAppointmentBellType(fsType)) {
            return null;
          }
          return {
            'id': doc.id,
            'type': 'notification',
            'firestoreType': fsType,
            'title': data['title'] ?? 'Notification',
            'message': data['message'] ?? '',
            'summary': data['summary'],
            'caseNo': data['caseNo'],
            'clientName': data['clientName'],
            'courtBranch': data['courtBranch'],
            'isRead': data['isRead'] == true,
            'timestamp': ts,
            'sortKey': ts ?? DateTime.fromMillisecondsSinceEpoch(0),
            'icon': Icons.notifications,
            'color': AppTheme.royalBlue,
          };
        }).whereType<Map<String, dynamic>>().toList()
          ..sort((a, b) => (b['sortKey'] as DateTime)
              .compareTo(a['sortKey'] as DateTime));

        for (final row in notifRows) {
          final entry = Map<String, dynamic>.from(row)..remove('sortKey');
          allNotifications.add(entry);
        }
      } catch (e) {
        // Handle error
      }

      // 2. Unread messages
      try {
        final unreadCount = await _chatService.getUnreadCount(staffId);
        if (unreadCount > 0) {
          allNotifications.add({
            'id': 'messages_${staffId}',
            'type': 'message',
            'title': 'New Messages',
            'message': 'You have $unreadCount unread message${unreadCount > 1 ? 's' : ''}',
            'isRead': false,
            'timestamp': DateTime.now(),
            'icon': Icons.message,
            'color': Colors.blue,
            'count': unreadCount,
          });
        }
      } catch (e) {
        // Handle error
      }

      // 3. Upcoming deadlines (if attorney assigned)
      if (_assignedAttorneyId != null) {
        try {
          final events = await _firestore
              .collection('calendar_events')
              .where('assignedTo', isEqualTo: _assignedAttorneyId)
              .where('eventDate', isGreaterThan: Timestamp.now())
              .orderBy('eventDate', descending: false)
              .limit(5)
              .get();

          for (var doc in events.docs) {
            final data = doc.data();
            final eventDate = (data['eventDate'] as Timestamp?)?.toDate();
            if (eventDate != null) {
              final daysUntil = eventDate.difference(DateTime.now()).inDays;
              if (daysUntil <= 7) {
                allNotifications.add({
                  'id': 'deadline_${doc.id}',
                  'type': 'deadline',
                  'title': data['title'] ?? 'Upcoming Deadline',
                  'message': daysUntil == 0
                      ? 'Due today'
                      : daysUntil == 1
                          ? 'Due tomorrow'
                          : 'Due in $daysUntil days',
                  'isRead': false,
                  'timestamp': eventDate,
                  'icon': Icons.calendar_today,
                  'color': Colors.orange,
                  'eventDate': eventDate,
                });
              }
            }
          }
        } catch (e) {
          // Handle error
        }
      }

      // 4. Pending tasks
      try {
        final tasks = await _taskService.getStaffTasks(staffId).first;
        final pendingTasks = tasks.where((t) => t.status == 'pending').take(5).toList();
        if (pendingTasks.isNotEmpty) {
          allNotifications.add({
            'id': 'tasks_${staffId}',
            'type': 'task',
            'title': 'Pending Tasks',
            'message': 'You have ${pendingTasks.length} pending task${pendingTasks.length > 1 ? 's' : ''}',
            'isRead': false,
            'timestamp': DateTime.now(),
            'icon': Icons.task,
            'color': Colors.red,
            'count': pendingTasks.length,
          });
        }
      } catch (e) {
        // Handle error
      }

      // 5. Recent activities (from activity logs)
      try {
        final activityLogs = await _staffService.getStaffActivityLogs(staffId).first;
        if (activityLogs.isNotEmpty) {
          final recentLogs = activityLogs.take(3).toList();
          for (var log in recentLogs) {
            final timestamp = log['timestamp'] as DateTime?;
            if (timestamp != null && 
                timestamp.isAfter(DateTime.now().subtract(const Duration(hours: 24)))) {
              allNotifications.add({
                'id': 'activity_${log['id']}',
                'type': 'activity',
                'title': _stringFrom(log['action'], 'Activity'),
                'message': _stringFrom(log['details']),
                'isRead': false,
                'timestamp': timestamp,
                'icon': _getActivityIcon(log['action']),
                'color': Colors.green,
              });
            }
          }
        }
      } catch (e) {
        // Handle error
      }

      // Sort by timestamp (newest first)
      allNotifications.sort((a, b) {
        final aTime = a['timestamp'] as DateTime? ?? DateTime(1970);
        final bTime = b['timestamp'] as DateTime? ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });

      return allNotifications;
    });
  }

  IconData _getActivityIcon(Object? action) {
    final s = _stringFrom(action);
    if (s.isEmpty) return Icons.info;
    final lowerAction = s.toLowerCase();
    if (lowerAction.contains('upload')) return Icons.upload;
    if (lowerAction.contains('note')) return Icons.note_add;
    if (lowerAction.contains('update')) return Icons.edit;
    if (lowerAction.contains('create')) return Icons.add;
    return Icons.history;
  }

  Future<void> _markAllAsRead(String staffId) async {
    if (_isMarkingAllRead) return;
    setState(() {
      _isMarkingAllRead = true;
    });

    try {
      await HearingNotificationFanoutService.instance
          .markAllInboxRowsRead(staffId);

      final query = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: staffId)
          .get();

      final batch = _firestore.batch();
      for (final doc in query.docs) {
        if (doc.data()['isRead'] == true) continue;
        final fsType = _stringFrom(doc.data()['type']).toLowerCase();
        if (_isCourtEmailSpam(fsType) ||
            hearingOrAppointmentBellType(fsType)) {
          continue;
        }
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (e) {
      // Handle error
    } finally {
      if (mounted) {
        setState(() {
          _isMarkingAllRead = false;
        });
      }
    }
  }

  Future<void> _markNotificationAsRead(String notificationId, String type) async {
    if (type == 'notification') {
      try {
        await _firestore.collection('notifications').doc(notificationId).update({
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        print('Error marking notification as read: $e');
      }
    }
    // Other types (message, task, deadline, activity) are dynamic and don't need marking
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: AppTheme.lightBackground,
        appBar: AppBar(
          title: const Text('Notifications'),
          backgroundColor: AppTheme.royalBlue,
        ),
        body: const Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.lightBackground,
      appBar: AppBar(
        title: const Text('Notifications & Reminders'),
        backgroundColor: AppTheme.royalBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: _isMarkingAllRead
                ? null
                : () => _markAllAsRead(user.uid),
            child: Text(
              _isMarkingAllRead ? 'Marking...' : 'Mark all read',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await HearingNotificationFanoutService.instance
              .syncStaffHearingNotifications(force: true);
          await HearingNotificationFanoutService.instance
              .syncRecentHearingsForInbox();
        },
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _getOtherNotifications(user.uid),
          builder: (context, snapshot) {
            final notifications = snapshot.data ?? [];

            final groupedNotifications = <String, List<Map<String, dynamic>>>{};
            for (var notification in notifications) {
              final timestamp = notification['timestamp'] as DateTime?;
              final dateKey = DateFormat('MMMM dd, yyyy').format(
                timestamp ?? DateTime.now(),
              );
              groupedNotifications.putIfAbsent(dateKey, () => []).add(notification);
            }

            final sortedDates = groupedNotifications.keys.toList()
              ..sort((a, b) {
                if (a == 'No date') return 1;
                if (b == 'No date') return -1;
                final dateA = DateFormat('MMMM dd, yyyy').parse(a);
                final dateB = DateFormat('MMMM dd, yyyy').parse(b);
                return dateB.compareTo(dateA);
              });

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(
                  child: AttorneyRemindersScreen(
                    showScaffold: false,
                    includeGlobalHearingsFallback: true,
                  ),
                ),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    notifications.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (notifications.isNotEmpty) ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'Other alerts',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, dateIndex) {
                          final dateKey = sortedDates[dateIndex];
                          final notificationsForDate =
                              groupedNotifications[dateKey]!;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom: 12,
                                  top: dateIndex > 0 ? 24 : 0,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.royalBlue.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        dateKey,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.royalBlue,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${notificationsForDate.length} ${notificationsForDate.length == 1 ? 'notification' : 'notifications'}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ...notificationsForDate.map(
                                (notification) => _buildNotificationCard(
                                  notification,
                                  user.uid,
                                ),
                              ),
                            ],
                          );
                        },
                        childCount: sortedDates.length,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notification, String staffId) {
    final isRead = notification['isRead'] as bool? ?? false;
    final timestamp = notification['timestamp'] as DateTime?;
    final title = _stringFrom(notification['title'], 'Notification');
    final message = _stringFrom(notification['message']);
    final icon = notification['icon'] is IconData
        ? notification['icon'] as IconData
        : Icons.notifications;
    final color = notification['color'] is Color
        ? notification['color'] as Color
        : AppTheme.royalBlue;
    final type = _stringFrom(notification['type'], 'notification');
    final notificationId = _stringFrom(notification['id']);
    final cardKey = _notificationCardKey(notification);
    final isHearing = type.contains('hearing') ||
        (notification['hearingDocId'] as String?)?.trim().isNotEmpty == true;
    final isExpandable =
        (type == 'notification' || isHearing) &&
        (message.trim().isNotEmpty || isHearing);
    final expanded = _expandedNotificationKeys.contains(cardKey);
    final previewSubtitle = _messagePreviewSubtitle(
      message,
      data: notification,
    );

    Future<void> onNonNotificationTap() async {
      if (!isRead && type == 'notification') {
        await _markNotificationAsRead(notificationId, type);
      }
      if (!mounted) return;
      if (type == 'message') {
        Navigator.pop(context);
      } else if (type == 'task') {
        Navigator.pop(context);
      } else if (type == 'deadline') {
        Navigator.pop(context);
      }
    }

    Future<void> onExpandableHeaderTap() async {
      final willExpand = !expanded;
      if (willExpand && !isRead) {
        await _markNotificationAsRead(notificationId, type);
      }
      setState(() {
        if (_expandedNotificationKeys.contains(cardKey)) {
          _expandedNotificationKeys.remove(cardKey);
        } else {
          _expandedNotificationKeys.add(cardKey);
        }
      });
    }

    final headerRow = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                        color: isRead ? Colors.grey[800] : Colors.black87,
                      ),
                    ),
                  ),
                  if (!isRead)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 4),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  if (isExpandable)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        color: AppTheme.mutedText,
                        size: 22,
                      ),
                    ),
                ],
              ),
              if (!expanded && previewSubtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  previewSubtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: Colors.grey[600],
                  ),
                ),
              ],
              if (timestamp != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('hh:mm a').format(timestamp),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      elevation: isRead ? 0 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isRead
            ? BorderSide(color: Colors.grey.shade200)
            : BorderSide(color: color.withOpacity(0.35), width: 1),
      ),
      child: isExpandable
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onExpandableHeaderTap,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Semantics(
                        button: true,
                        label: expanded
                            ? 'Collapse notification $title'
                            : 'Expand notification $title',
                        child: headerRow,
                      ),
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: expanded
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Divider(height: 1, color: Colors.grey.shade200),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isHearing ? 'Hearing details' : 'Details',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.royalBlue,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (isHearing)
                                    HearingNotificationDetailPanel(
                                      data: notification,
                                      hearingDocId:
                                          notification['hearingDocId']
                                              as String?,
                                    )
                                  else
                                    SelectableText(
                                      message,
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.45,
                                        color: Colors.grey[800],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            )
          : InkWell(
              onTap: onNonNotificationTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: color, size: 24),
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
                                  title,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight:
                                        isRead ? FontWeight.normal : FontWeight.bold,
                                    color: isRead ? Colors.grey[700] : Colors.black87,
                                  ),
                                ),
                              ),
                              if (!isRead)
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          if (message.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              message,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                          if (timestamp != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.access_time,
                                    size: 14, color: Colors.grey[500]),
                                const SizedBox(width: 4),
                                Text(
                                  DateFormat('hh:mm a').format(timestamp),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

