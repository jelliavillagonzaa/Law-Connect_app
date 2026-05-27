import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/hearing_notification_fanout_service.dart';
import '../../utils/hearing_notification_formatter.dart';
import '../../widgets/common/hearing_notification_detail_panel.dart';

class AttorneyRemindersScreen extends StatefulWidget {
  const AttorneyRemindersScreen({
    super.key,
    this.showScaffold = true,
    this.includeGlobalHearingsFallback = true,
    this.hearingsOnly = false,
  });

  /// When false, renders only the inbox list (for embedding in staff notifications).
  final bool showScaffold;

  /// Clients only see their own `notifications` rows (not every firm `hearings` doc).
  final bool includeGlobalHearingsFallback;

  /// Client inbox: court hearing/order rows only (no appointment reminders).
  final bool hearingsOnly;

  @override
  State<AttorneyRemindersScreen> createState() =>
      _AttorneyRemindersScreenState();
}

class _AttorneyRemindersScreenState extends State<AttorneyRemindersScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Set<String> _expandedKeys = <String>{};
  Set<String> _locallyReadRowKeys = <String>{};
  List<HearingInboxRow>? _rows;
  bool _inboxReady = false;
  StreamSubscription<List<HearingInboxRow>>? _inboxSub;

  /// Hot reload on web can leave fields undefined — always read through these.
  List<HearingInboxRow> get _safeRows {
    try {
      return List<HearingInboxRow>.from(_rows ?? const []);
    } catch (_) {
      _rows = const [];
      return _rows!;
    }
  }

  Set<String> get _safeExpandedKeys {
    try {
      return _expandedKeys;
    } catch (_) {
      _expandedKeys = <String>{};
      return _expandedKeys;
    }
  }

  Set<String> get _safeLocallyReadKeys {
    try {
      return _locallyReadRowKeys;
    } catch (_) {
      _locallyReadRowKeys = <String>{};
      return _locallyReadRowKeys;
    }
  }

  @override
  void initState() {
    super.initState();
    // Show list/empty immediately; stream + one-shot fetch fill in after.
    _inboxReady = true;
    _startInboxListener();
  }

  @override
  void reassemble() {
    super.reassemble();
    // Hot reload does not re-run [initState]; re-bind inbox on web/debug.
    _rows ??= const [];
    _expandedKeys = _safeExpandedKeys;
    _locallyReadRowKeys = _safeLocallyReadKeys;
    _startInboxListener();
  }

  void _startInboxListener() {
    final userId = _auth.currentUser?.uid;
    final fanout = HearingNotificationFanoutService.instance;

    if (userId == null) {
      return;
    }

    _inboxSub?.cancel();
    _inboxSub = null;

    final cached = fanout.peekInboxRows(
      userId,
      includeGlobalHearingsFallback: widget.includeGlobalHearingsFallback,
      hearingsOnly: widget.hearingsOnly,
    );
    if (cached != null) {
      setState(() {
        _rows = List<HearingInboxRow>.from(cached);
      });
    }

    fanout.warmInbox(
      userId,
      includeGlobalHearingsFallback: widget.includeGlobalHearingsFallback,
      hearingsOnly: widget.hearingsOnly,
    );
    unawaited(_loadInboxOnce(userId));

    final clientHearingsOnly =
        widget.hearingsOnly && !widget.includeGlobalHearingsFallback;
    _inboxSub = (clientHearingsOnly
            ? fanout.watchClientHearingInboxRows(userId)
            : fanout.watchInboxRows(
                userId,
                includeGlobalHearingsFallback:
                    widget.includeGlobalHearingsFallback,
                hearingsOnly: widget.hearingsOnly,
              ))
        .listen(
      (rows) {
        if (!mounted) return;
        setState(() {
          _rows = List<HearingInboxRow>.from(rows);
          _inboxReady = true;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _inboxReady = true);
      },
    );
  }

  Future<void> _loadInboxOnce(String userId) async {
    final fanout = HearingNotificationFanoutService.instance;
    final gh = widget.includeGlobalHearingsFallback;
    final ho = widget.hearingsOnly;
    try {
      if (ho) {
        unawaited(fanout.syncClientHearingNotifications());
      }

      final rows = await (!gh && ho
              ? fanout.fetchClientHearingInboxRowsOnce(userId, runSync: false)
              : fanout.fetchInboxRowsOnce(
                  userId,
                  includeGlobalHearingsFallback: gh,
                  hearingsOnly: ho,
                ))
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () =>
            fanout.peekInboxRows(
              userId,
              includeGlobalHearingsFallback: gh,
              hearingsOnly: ho,
            ) ??
            const <HearingInboxRow>[],
      );

      if (!mounted) return;
      setState(() => _rows = rows);

      // Heavy hearing scan runs in background — never block the reminders UI.
      if (gh && !ho && rows.where((r) => r.isHearingSource).isEmpty) {
        unawaited(_backgroundHearingSync(userId));
      }
    } catch (_) {
      if (mounted) setState(() => _inboxReady = true);
    }
  }

  Future<void> _backgroundHearingSync(String userId) async {
    final fanout = HearingNotificationFanoutService.instance;
    final gh = widget.includeGlobalHearingsFallback;
    final ho = widget.hearingsOnly;
    try {
      await fanout.syncRecentHearingsForInbox();
      final rows = await fanout.fetchInboxRowsOnce(
        userId,
        includeGlobalHearingsFallback: gh,
        hearingsOnly: ho,
      );
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (_) {
      // Stream listener will still deliver updates.
    }
  }

  @override
  void dispose() {
    _inboxSub?.cancel();
    _inboxSub = null;
    super.dispose();
  }

  bool _isRowRead(HearingInboxRow row) {
    if (_safeLocallyReadKeys.contains(row.rowKey)) return true;
    return !row.isUnread;
  }

  int _unreadCount() =>
      _safeRows.where((row) => !_isRowRead(row)).length;

  Future<void> _markRowAsRead(HearingInboxRow row) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null || _isRowRead(row)) return;

    setState(() => _safeLocallyReadKeys.add(row.rowKey));

    await HearingNotificationFanoutService.instance.markInboxRowAsRead(
      userId: userId,
      notificationDocId: row.notificationDocId,
      rowData: row.data,
    );
  }

  Future<void> _markAllAsRead() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    await HearingNotificationFanoutService.instance.markAllInboxRowsRead(
      userId,
      includeGlobalHearingsFallback: widget.includeGlobalHearingsFallback,
      hearingsOnly: widget.hearingsOnly,
    );

    if (!mounted) return;
    setState(() => _safeLocallyReadKeys.clear());
  }

  IconData _getReminderIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('hearing')) return Icons.gavel;
    if (t == 'court_email_ingest' || t.startsWith('court_')) {
      return Icons.mail_outline;
    }
    switch (type) {
      case 'appointment_scheduled':
        return Icons.event;
      case 'appointment_3day_reminder':
        return Icons.schedule;
      case 'appointment_sameday_reminder':
        return Icons.notifications_active;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _getReminderColor(String type) {
    final t = type.toLowerCase();
    if (t.contains('hearing')) return AppTheme.royalBlue;
    if (t == 'court_email_ingest' || t.startsWith('court_')) {
      return Colors.deepPurple;
    }
    switch (type) {
      case 'appointment_scheduled':
        return Colors.blue;
      case 'appointment_3day_reminder':
        return Colors.orange;
      case 'appointment_sameday_reminder':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _listSubtitle(Map<String, dynamic> data) {
    final type = (data['type'] as String? ?? '').toLowerCase();
    if (type.contains('hearing') ||
        (data['hearingDocId'] as String?)?.trim().isNotEmpty == true) {
      return HearingNotificationFormatter.buildSummary(data);
    }

    final summary = (data['summary'] as String?)?.trim();
    if (summary != null && summary.isNotEmpty) return summary;

    final typeLabel = data['type'] as String? ?? '';
    return _getReminderTitle(typeLabel);
  }

  bool _hasExpandableBody(Map<String, dynamic> data, String message) {
    if (message.trim().isNotEmpty) return true;
    final type = (data['type'] as String? ?? '').toLowerCase();
    if (type.contains('hearing')) return true;
    if ((data['hearingDocId'] as String?)?.trim().isNotEmpty == true) {
      return true;
    }
    return HearingNotificationFormatter.fieldsFromNotificationData(data)
        .isNotEmpty;
  }

  bool _isHearingDetail(Map<String, dynamic> data) {
    final type = (data['type'] as String? ?? '').toLowerCase();
    return type.contains('hearing') ||
        (data['hearingDocId'] as String?)?.trim().isNotEmpty == true;
  }

  String _getReminderTitle(String type) {
    final t = type.toLowerCase();
    if (t.contains('hearing')) return 'Hearing / court';
    switch (type) {
      case 'appointment_scheduled':
        return 'Appointment Scheduled';
      case 'appointment_3day_reminder':
        return '3-Day Reminder';
      case 'appointment_sameday_reminder':
        return 'Same-Day Reminder';
      default:
        return 'Reminder';
    }
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.grey[700],
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildReminderCard(HearingInboxRow row) {
    final rowKey = row.rowKey;
    final data = row.data;
    final type = data['type'] as String? ?? '';
    final title = data['title'] as String? ?? _getReminderTitle(type);
    final message = data['message'] as String? ?? '';
    final subtitle = _listSubtitle(data);
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final isRead = _isRowRead(row);
    final color = _getReminderColor(type);
    final expanded = _safeExpandedKeys.contains(rowKey);
    final hasBody = _hasExpandableBody(data, message);

    Future<void> onHeaderTap() async {
      final willExpand = !expanded;
      if (willExpand && !isRead) {
        unawaited(_markRowAsRead(row));
      }
      setState(() {
        if (expanded) {
          _safeExpandedKeys.remove(rowKey);
        } else {
          _safeExpandedKeys.add(rowKey);
        }
      });
    }

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            _getReminderIcon(type),
            color: color,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                  color: isRead ? Colors.grey[700] : Colors.black87,
                  height: 1.3,
                ),
              ),
              if (!isRead)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Unread',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              if (!expanded && subtitle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: Colors.grey[600],
                  ),
                ),
              ],
              if (createdAt != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('MMM dd, yyyy • hh:mm a').format(createdAt),
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
        if (hasBody) ...[
          const SizedBox(width: 4),
          Icon(
            expanded ? Icons.expand_less : Icons.expand_more,
            color: AppTheme.mutedText,
            size: 26,
          ),
        ],
      ],
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      elevation: isRead ? 1 : 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isRead ? Colors.grey.shade200 : color.withOpacity(0.45),
          width: isRead ? 1 : 2,
        ),
      ),
      child: hasBody
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onHeaderTap,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: header,
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
                            Container(
                              color: Colors.grey.shade50,
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isHearingDetail(data)
                                        ? 'Hearing details'
                                        : 'Full message',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.royalBlue,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (_isHearingDetail(data))
                                    HearingNotificationDetailPanel(
                                      data: data,
                                      hearingDocId:
                                          data['hearingDocId'] as String?,
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
                if (!isRead) unawaited(_markRowAsRead(row));
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: header,
              ),
            ),
    );
  }

  Widget _buildMarkAllReadAction() {
    final unreadCount = _unreadCount();
    if (unreadCount == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton.icon(
        onPressed: _markAllAsRead,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(Icons.done_all, color: Colors.white, size: 18),
        label: Text(
          'Mark read ($unreadCount)',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }

  EdgeInsets _listPadding(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return EdgeInsets.fromLTRB(16, 12, 16, 24 + bottom);
  }

  Widget _buildBody() {
    if (_safeRows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          Icon(
            Icons.notifications_none,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Reminders',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              widget.hearingsOnly
                  ? 'Court hearings and orders for your cases appear here.\nTap a row to read the full order.'
                  : 'Hearings from your cases and appointment reminders appear here.\nTap a row to read the full order or message.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ),
        ],
      );
    }

    final hearingRows = _safeRows.where((r) => r.isHearingSource).toList();
    final appointmentRows = widget.hearingsOnly
        ? <HearingInboxRow>[]
        : _safeRows.where((r) => !r.isHearingSource).toList();

    final children = <Widget>[
      if (hearingRows.isNotEmpty) ...[
        _sectionHeader(
          widget.hearingsOnly
              ? 'New notice court hearings'
              : 'Court hearings & orders',
        ),
        ...hearingRows.map(_buildReminderCard),
      ],
      if (appointmentRows.isNotEmpty) ...[
        if (hearingRows.isNotEmpty) const SizedBox(height: 8),
        _sectionHeader('Appointments'),
        ...appointmentRows.map(_buildReminderCard),
      ],
    ];

    if (!widget.showScaffold) {
      if (children.isEmpty) return const SizedBox.shrink();
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: children,
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: _listPadding(context),
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();
    if (!widget.showScaffold) return body;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        title: const Text(
          'Reminders',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppTheme.royalBlue,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [_buildMarkAllReadAction()],
      ),
      body: SafeArea(top: false, child: body),
    );
  }
}
