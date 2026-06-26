import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import '../../services/auth_service.dart';
import '../../services/hearing_notification_fanout_service.dart';
import '../attorney/attorney_reminders_screen.dart';
import '../../utils/hearing_notification_formatter.dart';
import '../../widgets/common/hearing_notification_detail_panel.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  bool _isMarkingAllRead = false;
  final Set<String> _expandedNotificationKeys = <String>{};
  int _hearingSectionKey = 0;

  static const int _otherAlertsQueryLimit = 40;

  static String _stringFrom(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    if (value is String) return value;
    return value.toString();
  }

  static bool _isHearingInboxType(String fsType) {
    return clientHearingInboxType(fsType);
  }

  static bool _isCourtEmailSpam(Map<String, dynamic> data) {
    return clientCourtEmailSpamNotification(data);
  }

  String _notificationCardKey(Map<String, dynamic> notification) {
    final id = _stringFrom(notification['id']);
    return 'notification_$id';
  }

  String? _messagePreviewSubtitle(
    String message, {
    Map<String, dynamic>? data,
  }) {
    if (data != null && _isHearingInboxType(_stringFrom(data['type']))) {
      final line = HearingNotificationFormatter.buildSummary(data);
      if (line.isNotEmpty) return line;
    }

    final summary = (data?['summary'] as String?)?.trim();
    if (summary != null && summary.isNotEmpty) return summary;

    final t = message.trim();
    if (t.isEmpty) return null;
    if (t.length > 120) return '${t.substring(0, 117)}...';
    return t;
  }

  bool _isHearingNotification(Map<String, dynamic> notification) {
    return _isHearingInboxType(_stringFrom(notification['type'])) ||
        (notification['hearingDocId'] as String?)?.trim().isNotEmpty == true;
  }

  /// Merges userId + clientId notification queries without a blocking `.get()` per snapshot.
  Stream<List<Map<String, dynamic>>> _otherNotificationsStream(String userId) {
    final userIdStream = _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .limit(_otherAlertsQueryLimit)
        .snapshots();
    final clientIdStream = _firestore
        .collection('notifications')
        .where('clientId', isEqualTo: userId)
        .limit(_otherAlertsQueryLimit)
        .snapshots();

    return Stream<List<Map<String, dynamic>>>.multi((controller) {
      QuerySnapshot<Map<String, dynamic>>? lastUserIdSnapshot;
      QuerySnapshot<Map<String, dynamic>>? lastClientIdSnapshot;

      void emitMerged() {
        if (controller.isClosed) return;
        final merged = <String, Map<String, dynamic>>{};

        void addDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
          final data = Map<String, dynamic>.from(doc.data());
          if (_isCourtEmailSpam(data)) return;
          final fsType = _stringFrom(data['type']).toLowerCase();
          if (_isHearingInboxType(fsType)) return;

          final ts = (data['createdAt'] as Timestamp?)?.toDate();
          merged[doc.id] = {
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
            'icon': Icons.notifications_outlined,
            'color': AppTheme.royalBlue,
          };
        }

        for (final doc in lastUserIdSnapshot?.docs ?? const []) {
          addDoc(doc);
        }
        for (final doc in lastClientIdSnapshot?.docs ?? const []) {
          addDoc(doc);
        }

        final list = merged.values.toList()
          ..sort(
            (a, b) =>
                (b['sortKey'] as DateTime).compareTo(a['sortKey'] as DateTime),
          );
        for (final row in list) {
          row.remove('sortKey');
        }
        controller.add(list);
      }

      late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> subU;
      late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> subC;

      subU = userIdStream.listen(
        (snap) {
          lastUserIdSnapshot = snap;
          emitMerged();
        },
        onError: (err, _) => controller.addError(err),
      );
      subC = clientIdStream.listen(
        (snap) {
          lastClientIdSnapshot = snap;
          emitMerged();
        },
        onError: (err, _) => controller.addError(err),
      );

      controller.onCancel = () async {
        await subU.cancel();
        await subC.cancel();
      };
    });
  }

  Future<void> _markAllAsRead(String userId) async {
    if (_isMarkingAllRead) return;
    setState(() => _isMarkingAllRead = true);

    try {
      await HearingNotificationFanoutService.instance.markAllInboxRowsRead(
        userId,
        includeGlobalHearingsFallback: false,
        hearingsOnly: true,
      );

      final userIdQuery = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();
      final clientIdQuery = await _firestore
          .collection('notifications')
          .where('clientId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (final doc in userIdQuery.docs) {
        final data = doc.data();
        if (_isCourtEmailSpam(data)) continue;
        final fsType = _stringFrom(data['type']).toLowerCase();
        if (_isHearingInboxType(fsType)) continue;
        batch.update(doc.reference, {'isRead': true});
      }
      for (final doc in clientIdQuery.docs) {
        if (userIdQuery.docs.any((d) => d.id == doc.id)) continue;
        final data = doc.data();
        if (_isCourtEmailSpam(data)) continue;
        final fsType = _stringFrom(data['type']).toLowerCase();
        if (_isHearingInboxType(fsType)) continue;
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (_) {
      /* keep existing rows */
    } finally {
      if (mounted) setState(() => _isMarkingAllRead = false);
    }
  }

  Future<void> _markNotificationAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'isRead': true,
      });
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;

    // Keep Notifications lightweight: show cached hearing rows (rendered by
    // [AttorneyRemindersScreen]) and let the user pull-to-refresh to sync.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        HearingNotificationFanoutService.instance.prepareBellCount(uid),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: AppTheme.lightBackground,
        appBar: AppBar(title: const Text('Notifications')),
        body: const Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: AppTheme.royalBlue,
        iconTheme: const IconThemeData(color: AppTheme.white),
        actions: [
          TextButton(
            onPressed: _isMarkingAllRead ? null : () => _markAllAsRead(user.uid),
            child: Text(
              _isMarkingAllRead ? 'Marking...' : 'Mark all read',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.white),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _otherNotificationsStream(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'Error loading notifications',
              message: snapshot.error?.toString() ?? 'Please try again later.',
            );
          }

          final notifications = snapshot.data ?? [];
          final flatRows = _buildOtherAlertRows(notifications);

          return RefreshIndicator(
            onRefresh: () async {
              final fanout = HearingNotificationFanoutService.instance;
              await fanout.purgeClientCourtEmailNotices(user.uid);
              await fanout.syncClientHearingNotifications(force: false);
              await fanout.fetchClientHearingInboxRowsOnce(user.uid, runSync: false);
              if (mounted) setState(() => _hearingSectionKey++);
            },
            child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: AttorneyRemindersScreen(
                  key: ValueKey(_hearingSectionKey),
                  showScaffold: false,
                  includeGlobalHearingsFallback: false,
                  hearingsOnly: true,
                  skipHeavyWarmOnOpen: true,
                  cacheOnlyOnOpen: true,
                ),
              ),
              if (notifications.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Other alerts',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[700],
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildOtherAlertListItem(flatRows[index]),
                      childCount: flatRows.length,
                    ),
                  ),
                ),
              ] else
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
                ),
            ],
            ),
          );
        },
      ),
    );
  }

  List<_OtherAlertRow> _buildOtherAlertRows(List<Map<String, dynamic>> notifications) {
    final rows = <_OtherAlertRow>[];
    DateTime? lastDay;
    for (final n in notifications) {
      final ts = n['timestamp'] as DateTime?;
      final d = ts ?? DateTime.fromMillisecondsSinceEpoch(0);
      final day = DateTime(d.year, d.month, d.day);
      if (lastDay == null || day != lastDay) {
        rows.add(
          _OtherAlertRow.date(DateFormat('MMMM dd, yyyy').format(d)),
        );
        lastDay = day;
      }
      rows.add(_OtherAlertRow.notification(n));
    }
    return rows;
  }

  Widget _buildOtherAlertListItem(_OtherAlertRow row) {
    if (row.isDate) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 24),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.royalBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                row.label!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.royalBlue,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return _buildNotificationCard(row.notification!);
  }

  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    final isRead = notification['isRead'] as bool? ?? false;
    final timestamp = notification['timestamp'] as DateTime?;
    final title = _stringFrom(notification['title'], 'Notification');
    final message = _stringFrom(notification['message']);
    final icon = notification['icon'] is IconData
        ? notification['icon'] as IconData
        : Icons.notifications_outlined;
    final color = notification['color'] is Color
        ? notification['color'] as Color
        : AppTheme.royalBlue;
    final notificationId = _stringFrom(notification['id']);
    final cardKey = _notificationCardKey(notification);
    final isExpandable = message.trim().isNotEmpty ||
        _isHearingNotification(notification);
    final expanded = _expandedNotificationKeys.contains(cardKey);
    final previewSubtitle = _messagePreviewSubtitle(
      message,
      data: notification,
    );

    Future<void> onExpandableHeaderTap() async {
      final willExpand = !expanded;
      if (willExpand && !isRead) {
        await _markNotificationAsRead(notificationId);
      }
      setState(() {
        if (expanded) {
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
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(width: 12),
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
                        color: isRead ? Colors.grey[700] : Colors.black87,
                      ),
                    ),
                  ),
                  if (!isRead)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(left: 8, top: 6),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  if (isExpandable)
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: AppTheme.mutedText,
                      size: 22,
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
                      DateFormat('MMM dd, yyyy ΓÇó hh:mm a').format(timestamp),
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
      elevation: isRead ? 1 : 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isRead ? Colors.grey.shade200 : color.withValues(alpha: 0.45),
          width: isRead ? 1 : 2,
        ),
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
                                    _isHearingNotification(notification)
                                        ? 'Hearing details'
                                        : 'Details',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.royalBlue,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (_isHearingNotification(notification))
                                    HearingNotificationDetailPanel(
                                      data: notification,
                                      hearingDocId: notification['hearingDocId']
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
              onTap: () {
                if (!isRead) unawaited(_markNotificationAsRead(notificationId));
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: headerRow,
              ),
            ),
    );
  }
}

class _OtherAlertRow {
  const _OtherAlertRow.date(this.label)
    : isDate = true,
      notification = null;
  const _OtherAlertRow.notification(this.notification)
    : isDate = false,
      label = null;

  final bool isDate;
  final String? label;
  final Map<String, dynamic>? notification;
}
