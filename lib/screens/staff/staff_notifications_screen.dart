import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/lightweight_reminder_item.dart';
import '../../services/lightweight_reminders_inbox_service.dart';
import '../../services/staff_auth_service.dart';
import '../../services/hearing_notification_fanout_service.dart';
import '../../utils/hearing_notification_formatter.dart';
import '../../widgets/common/hearing_notification_detail_panel.dart';
import '../../widgets/common/lightweight_reminder_tile.dart';

class StaffNotificationsScreen extends StatefulWidget {
  const StaffNotificationsScreen({super.key});

  @override
  State<StaffNotificationsScreen> createState() => _StaffNotificationsScreenState();
}

class _StaffNotificationsScreenState extends State<StaffNotificationsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final StaffAuthService _staffAuthService = StaffAuthService();
  bool _isMarkingAllRead = false;
  String? _assignedAttorneyId;
  List<Map<String, dynamic>> _extraAlerts = [];
  List<Map<String, dynamic>> _notifications = [];
  bool _extrasLoaded = false;
  bool _loadingExtras = false;
  bool _refreshInFlight = false;
  bool _loadingReminders = false;
  bool _loadingInbox = false;
  List<LightweightReminderItem> _reminderItems = [];
  List<Map<String, dynamic>> _mergedNotificationsCache = [];
  List<_StaffAlertRow> _flatRowsCache = [];
  static const int _inboxQueryLimit = 35;

  static String _stringFrom(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    if (value is String) return value;
    return value.toString();
  }

  static bool _isCourtEmailSpam(Map<String, dynamic> data) {
    return clientCourtEmailSpamNotification(data);
  }

  /// First paragraph / first line / short excerpt for the collapsed row (full body expands on tap).
  String? _messagePreviewSubtitle(
    String message, {
    Map<String, dynamic>? data,
  }) {
    if (data != null) {
      final type = _stringFrom(data['type']).toLowerCase();
      if (type.contains('hearing') ||
          _stringFrom(data['hearingDocId']).isNotEmpty) {
        final line = HearingNotificationFormatter.buildSummary(data);
        if (line.isNotEmpty) return line;
      }
    }

    final summary = _stringFrom(data?['summary']).trim();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      unawaited(_loadRemindersInbox(uid));
      unawaited(_loadExtraAlertsOnce(uid));
      unawaited(_loadStaffData());
    });
  }

  /// Notifications + global hearings in one pass so read rows are not late-loaded.
  Future<void> _loadRemindersInbox(String staffId, {bool force = false}) async {
    if (_loadingInbox && !force) return;
    _loadingInbox = true;

    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection('notifications')
          .where('userId', isEqualTo: staffId);

      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await query
            .orderBy('createdAt', descending: true)
            .limit(_inboxQueryLimit)
            .get()
            .timeout(const Duration(seconds: 4));
      } catch (_) {
        snap = await query
            .limit(_inboxQueryLimit)
            .get()
            .timeout(const Duration(seconds: 4));
      }
      if (!mounted) return;

      final parsed = _parseInboxDocs(snap.docs);
      var reminders = parsed.reminders;

      reminders = await LightweightRemindersInboxService.mergeGlobalHearings(
        staffId,
        reminders,
      ).timeout(const Duration(seconds: 4), onTimeout: () => reminders);
      if (!mounted) return;

      setState(() {
        _reminderItems = reminders;
        _notifications = parsed.others;
        _loadingReminders = false;
        _rebuildNotificationCaches();
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingReminders = false);
      }
    } finally {
      _loadingInbox = false;
    }
  }

  ({List<LightweightReminderItem> reminders, List<Map<String, dynamic>> others})
      _parseInboxDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final reminders = <LightweightReminderItem>[];
    final others = <Map<String, dynamic>>[];

    for (final doc in docs) {
      final data = doc.data();
      final ts = (data['createdAt'] as Timestamp?)?.toDate();
      final fsType = _stringFrom(data['type']).toLowerCase();
      if (_isCourtEmailSpam(data)) continue;

      if (hearingOrAppointmentBellType(fsType)) {
        final item = LightweightReminderItem.fromNotificationDoc(doc.id, data);
        if (item != null) reminders.add(item);
      } else {
        others.add({
          'id': doc.id,
          'type': 'notification',
          'firestoreType': fsType,
          'title': _stringFrom(data['title'], 'Notification'),
          'message': LightweightReminderItem.truncate(
            _stringFrom(data['summary']).isNotEmpty
                ? _stringFrom(data['summary'])
                : _stringFrom(data['message']),
            200,
          ),
          'summary': LightweightReminderItem.truncate(_stringFrom(data['summary'])),
          'caseNo': _stringFrom(data['caseNo']),
          'clientName': _stringFrom(data['clientName']),
          'courtBranch': _stringFrom(data['courtBranch']),
          'isRead': data['isRead'] == true,
          'timestamp': ts,
          'icon': Icons.notifications,
          'color': AppTheme.royalBlue,
        });
      }
    }

    reminders.sort((a, b) => b.sortTime.compareTo(a.sortTime));
    others.sort((a, b) {
      final aTime = a['timestamp'] as DateTime? ?? DateTime(1970);
      final bTime = b['timestamp'] as DateTime? ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });

    return (reminders: reminders, others: others);
  }

  Future<void> _markReminderRead(LightweightReminderItem item) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || item.isRead) return;

    final twins = _reminderItems.where((row) {
      if (row.isRead) return false;
      if (row.rowKey == item.rowKey) return true;
      final key = item.duplicateCaseKey;
      if (key == null || row.duplicateCaseKey != key) return false;
      return row.sortTime.difference(item.sortTime).abs() <=
          LightweightReminderItem.duplicateWindow;
    }).toList();
    if (mounted && twins.isNotEmpty) {
      setState(() {
        for (final twin in twins) {
          final idx = _reminderItems.indexWhere((r) => r.rowKey == twin.rowKey);
          if (idx >= 0) _reminderItems[idx] = twin.markRead();
        }
        _rebuildNotificationCaches();
      });
    }

    for (final twin in twins) {
      unawaited(
        HearingNotificationFanoutService.instance.markInboxRowAsRead(
          userId: uid,
          notificationDocId: twin.notificationDocId,
          rowData: twin.hearingDocId != null
              ? {
                  'hearingDocId': twin.hearingDocId,
                  'type': twin.type,
                  'title': twin.title,
                }
              : null,
        ),
      );
    }
  }

  Future<void> _handlePullRefresh(String uid) async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    try {
      await Future.wait([
        _loadRemindersInbox(uid, force: true),
        _loadExtraAlertsOnce(uid, force: true),
      ]);
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> _loadStaffData() async {
    final staff = await _staffAuthService.getCurrentStaff();
    if (!mounted) return;
    if (staff != null) {
      setState(() => _assignedAttorneyId = staff.assignedAttorneyId);
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        unawaited(_loadExtraAlertsOnce(uid, force: true));
      }
      return;
    }

    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser?.uid)
          .get();
      if (!mounted) return;
      final attorneyId =
          (userDoc.data()?['assignedAttorneyId'] as String?)?.trim() ?? '';
      if (attorneyId.isNotEmpty) {
        setState(() => _assignedAttorneyId = attorneyId);
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          unawaited(_loadExtraAlertsOnce(uid, force: true));
        }
      }
    } catch (_) {}
  }

  Future<String?> _resolveAssignedAttorneyId() async {
    final cached = _assignedAttorneyId?.trim();
    if (cached != null && cached.isNotEmpty) return cached;

    final staff = await _staffAuthService.getCurrentStaff();
    final fromStaff = staff?.assignedAttorneyId.trim();
    if (fromStaff != null && fromStaff.isNotEmpty) {
      if (mounted) setState(() => _assignedAttorneyId = fromStaff);
      return fromStaff;
    }

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return null;
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final attorneyId =
          (userDoc.data()?['assignedAttorneyId'] as String?)?.trim() ?? '';
      if (attorneyId.isNotEmpty && mounted) {
        setState(() => _assignedAttorneyId = attorneyId);
      }
      return attorneyId.isEmpty ? null : attorneyId;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadExtraAlertsOnce(String staffId, {bool force = false}) async {
    if (_extrasLoaded && !force) return;
    final extras = <Map<String, dynamic>>[];

    final attorneyId = await _resolveAssignedAttorneyId();
    if (attorneyId != null) {
      try {
        final events = await _firestore
            .collection('calendar_events')
            .where('assignedTo', isEqualTo: attorneyId)
            .where('eventDate', isGreaterThan: Timestamp.now())
            .orderBy('eventDate')
            .limit(5)
            .get()
            .timeout(const Duration(seconds: 4));
        for (final doc in events.docs) {
          final data = doc.data();
          final eventDate = (data['eventDate'] as Timestamp?)?.toDate();
          if (eventDate == null) continue;
          final daysUntil = eventDate.difference(DateTime.now()).inDays;
          if (daysUntil <= 7) {
            extras.add({
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
            });
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _extraAlerts = extras;
      _extrasLoaded = true;
      _loadingExtras = false;
      _rebuildNotificationCaches();
    });
  }

  void _rebuildNotificationCaches() {
    final merged = <Map<String, dynamic>>[..._notifications, ..._extraAlerts];
    merged.sort((a, b) {
      final aTime = a['timestamp'] as DateTime? ?? DateTime(1970);
      final bTime = b['timestamp'] as DateTime? ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });
    _mergedNotificationsCache = merged;
    _flatRowsCache = _buildNewestFirstFeed(merged);
  }

  /// One list: newest notify time on top (hearings + other alerts together).
  List<_StaffAlertRow> _buildNewestFirstFeed(
    List<Map<String, dynamic>> notifications,
  ) {
    final usedIds = <String>{};
    final timed = <({DateTime t, _StaffAlertRow row})>[];

    for (final r in LightweightReminderItem.collapseSameCase(_reminderItems)) {
      usedIds.add(r.rowKey);
      if (r.notificationDocId != null) usedIds.add(r.notificationDocId!);
      timed.add((t: r.sortTime, row: _StaffAlertRow.reminder(r)));
    }
    for (final n in notifications) {
      final id = (n['id'] as String?) ?? '';
      if (id.isNotEmpty && usedIds.contains(id)) continue;
      timed.add((
        t: n['timestamp'] as DateTime? ?? DateTime(1970),
        row: _StaffAlertRow.notification(n),
      ));
    }
    timed.sort((a, b) => b.t.compareTo(a.t));

    final rows = <_StaffAlertRow>[];
    DateTime? lastDay;
    for (final item in timed) {
      final d = item.t;
      final day = DateTime(d.year, d.month, d.day);
      if (lastDay == null || day != lastDay) {
        rows.add(_StaffAlertRow.date(DateFormat('MMMM dd, yyyy').format(d)));
        lastDay = day;
      }
      rows.add(item.row);
    }
    return rows;
  }

  Future<void> _markAllAsRead(String staffId) async {
    if (_isMarkingAllRead) return;
    setState(() {
      _isMarkingAllRead = true;
    });

    try {
      await HearingNotificationFanoutService.instance
          .markAllInboxRowsRead(staffId);

      if (mounted) {
        setState(() {
          _reminderItems =
              _reminderItems.map((row) => row.markRead()).toList();
          _rebuildNotificationCaches();
        });
      }

      final query = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: staffId)
          .limit(200)
          .get();

      final batch = _firestore.batch();
      for (final doc in query.docs) {
        if (doc.data()['isRead'] == true) continue;
        final fsType = _stringFrom(doc.data()['type']).toLowerCase();
        if (_isCourtEmailSpam(doc.data()) ||
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
        onRefresh: () => _handlePullRefresh(user.uid),
        child: _buildNotificationList(user),
      ),
    );
  }

  Widget _buildNotificationList(User user) {
    final flatRows = _flatRowsCache;
    final loading = _loadingReminders || _loadingExtras;
    final empty = !loading && flatRows.isEmpty;

    return CustomScrollView(
      cacheExtent: 400,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (empty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              child: Text(
                'No notifications yet. Pull down to refresh.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ),
          ),
        if (flatRows.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _buildAlertListItem(flatRows[index], user.uid),
                childCount: flatRows.length,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAlertListItem(_StaffAlertRow row, String staffId) {
    if (row.isDate) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 12),
        child: Text(
          row.label!,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppTheme.royalBlue,
          ),
        ),
      );
    }
    if (row.reminder != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: LightweightReminderTile(
          key: ValueKey(row.reminder!.rowKey),
          item: row.reminder!,
          onMarkRead: () => _markReminderRead(row.reminder!),
        ),
      );
    }
    return _buildNotificationCard(row.notification!, staffId);
  }

  Widget _buildNotificationCard(Map<String, dynamic> notification, String staffId) {
    return _StaffNotificationCard(
      notification: notification,
      staffId: staffId,
      onMarkRead: _markNotificationAsRead,
      stringFrom: _stringFrom,
      messagePreviewSubtitle: _messagePreviewSubtitle,
    );
  }
}

class _StaffNotificationCard extends StatefulWidget {
  const _StaffNotificationCard({
    required this.notification,
    required this.staffId,
    required this.onMarkRead,
    required this.stringFrom,
    required this.messagePreviewSubtitle,
  });

  final Map<String, dynamic> notification;
  final String staffId;
  final Future<void> Function(String notificationId, String type) onMarkRead;
  final String Function(dynamic value, [String fallback]) stringFrom;
  final String? Function(String message, {Map<String, dynamic>? data})
      messagePreviewSubtitle;

  @override
  State<_StaffNotificationCard> createState() => _StaffNotificationCardState();
}

class _StaffNotificationCardState extends State<_StaffNotificationCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final notification = widget.notification;
    final isRead = notification['isRead'] as bool? ?? false;
    final timestamp = notification['timestamp'] as DateTime?;
    final title = widget.stringFrom(notification['title'], 'Notification');
    final message = widget.stringFrom(notification['message']);
    final icon = notification['icon'] is IconData
        ? notification['icon'] as IconData
        : Icons.notifications;
    final color = notification['color'] is Color
        ? notification['color'] as Color
        : AppTheme.royalBlue;
    final type = widget.stringFrom(notification['type'], 'notification');
    final notificationId = widget.stringFrom(notification['id']);
    final isHearing = type.contains('hearing') ||
        widget.stringFrom(notification['hearingDocId']).isNotEmpty;
    final isExpandable =
        (type == 'notification' || isHearing) &&
        (message.trim().isNotEmpty || isHearing);
    final previewSubtitle = widget.messagePreviewSubtitle(
      message,
      data: notification,
    );

    Future<void> onNonNotificationTap() async {
      if (!isRead && type == 'notification') {
        await widget.onMarkRead(notificationId, type);
      }
      if (!mounted) return;
      if (type == 'message' || type == 'task' || type == 'deadline') {
        Navigator.pop(context);
      }
    }

    void onExpandableHeaderTap() {
      final willExpand = !_expanded;
      setState(() => _expanded = willExpand);
      if (willExpand && !isRead && type == 'notification') {
        unawaited(widget.onMarkRead(notificationId, type));
      }
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
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        color: AppTheme.mutedText,
                        size: 22,
                      ),
                    ),
                ],
              ),
              if (!_expanded && previewSubtitle != null) ...[
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
                      child: headerRow,
                    ),
                  ),
                ),
                if (_expanded) ...[
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
                            hearingDocId: () {
                              final hid =
                                  widget.stringFrom(notification['hearingDocId']);
                              return hid.isEmpty ? null : hid;
                            }(),
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
              ],
            )
          : InkWell(
              onTap: onNonNotificationTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: headerRow,
              ),
            ),
    );
  }
}

class _StaffAlertRow {
  const _StaffAlertRow.date(this.label)
      : isDate = true,
        notification = null,
        reminder = null;
  const _StaffAlertRow.notification(this.notification)
      : isDate = false,
        label = null,
        reminder = null;
  const _StaffAlertRow.reminder(this.reminder)
      : isDate = false,
        label = null,
        notification = null;

  final bool isDate;
  final String? label;
  final Map<String, dynamic>? notification;
  final LightweightReminderItem? reminder;
}

