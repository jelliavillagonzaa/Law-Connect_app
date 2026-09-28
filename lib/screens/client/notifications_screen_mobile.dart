import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/hearing_notification_fanout_service.dart';
import '../../utils/hearing_notification_formatter.dart';
import '../../widgets/common/hearing_notification_detail_panel.dart';

/// Client notification inbox (Android / iOS).
///
/// Opens from cached rows immediately, then loads a capped, user-scoped query.
/// Does not embed [AttorneyRemindersScreen] (that Column-in-SliverToBoxAdapter
/// layout built every hearing card on the UI isolate and ANR'd Android).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  static const int _listLimit = 40;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  List<HearingInboxRow> _hearingRows = const [];
  List<Map<String, dynamic>> _otherAlerts = const [];
  List<_InboxRow> _flatRows = const [];
  String _listSignature = '';

  bool _loading = false;
  bool _inFlight = false;
  bool _pendingRefresh = false;
  bool _markingAllRead = false;
  int _loadGen = 0;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _paintPeek();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = _authService.currentUser?.uid;
      if (uid == null || !mounted) return;
      unawaited(_refresh(uid, showSpinner: _flatRows.isEmpty));
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        final id = _authService.currentUser?.uid;
        if (id == null || !mounted) return;
        unawaited(_refresh(id, cacheFirst: false));
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;
    unawaited(_refresh(uid, cacheFirst: false));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _pollTimer = null;
    _loadGen++;
    super.dispose();
  }

  void _paintPeek() {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;
    final cached = HearingNotificationFanoutService.instance.peekInboxRows(
          uid,
          includeGlobalHearingsFallback: false,
          hearingsOnly: true,
        ) ??
        const <HearingInboxRow>[];
    final hearings = cached.take(_listLimit).map(_slimHearingRow).toList()
      ..sort((a, b) => b.sortTime.compareTo(a.sortTime));
    _hearingRows = hearings;
    _flatRows = _buildFlatRows(hearings, const []);
    _listSignature = _signature(hearings, const []);
  }

  Future<void> _refresh(
    String uid, {
    bool showSpinner = false,
    bool cacheFirst = true,
  }) async {
    if (_inFlight) {
      _pendingRefresh = true;
      return;
    }
    _inFlight = true;
    final gen = ++_loadGen;
    if (showSpinner && mounted) setState(() => _loading = true);

    try {
      if (cacheFirst) {
        await _applySnapshot(
          uid,
          gen,
          await _loadUserNotifications(uid, fromCache: true),
        );
        if (!mounted || gen != _loadGen) return;
      }
      await _applySnapshot(
        uid,
        gen,
        await _loadUserNotifications(uid, fromCache: false),
      );
    } catch (_) {
      if (mounted && gen == _loadGen && _flatRows.isEmpty) {
        setState(() => _loading = false);
      }
    } finally {
      _inFlight = false;
      if (mounted && gen == _loadGen) {
        if (_loading) setState(() => _loading = false);
        if (_pendingRefresh) {
          _pendingRefresh = false;
          unawaited(_refresh(uid, cacheFirst: false));
        }
      }
    }
  }

  Future<void> _applySnapshot(
    String uid,
    int gen,
    QuerySnapshot<Map<String, dynamic>>? snap,
  ) async {
    if (!mounted || gen != _loadGen) return;
    if (snap == null) {
      if (_flatRows.isNotEmpty) return;
    }
    final hearings = <HearingInboxRow>[];
    final others = <Map<String, dynamic>>[];
    if (snap != null) {
      for (final doc in snap.docs) {
        final data = doc.data();
        if (clientCourtEmailSpamNotification(data)) continue;
        final type = (data['type'] as String? ?? '').toLowerCase();
        if (clientHearingInboxType(type)) {
          final ts = (data['createdAt'] as Timestamp?)?.toDate() ??
              DateTime.fromMillisecondsSinceEpoch(0);
          hearings.add(
            HearingInboxRow(
              rowKey: doc.id,
              notificationDocId: doc.id,
              data: _slimMap(data),
              sortTime: ts,
            ),
          );
        } else {
          others.add(_slimOtherAlert(doc.id, data));
        }
      }
      hearings.sort((a, b) => b.sortTime.compareTo(a.sortTime));
      others.sort((a, b) {
        final at = a['timestamp'] as DateTime? ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b['timestamp'] as DateTime? ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
    }

    if (hearings.isEmpty) {
      final peeked = HearingNotificationFanoutService.instance.peekInboxRows(
            uid,
            includeGlobalHearingsFallback: false,
            hearingsOnly: true,
          ) ??
          const <HearingInboxRow>[];
      hearings.addAll(peeked.take(_listLimit).map(_slimHearingRow));
      hearings.sort((a, b) => b.sortTime.compareTo(a.sortTime));
    }

    final sig = _signature(hearings, others);
    if (sig == _listSignature) {
      if (_loading) setState(() => _loading = false);
      return;
    }
    setState(() {
      _hearingRows = hearings;
      _otherAlerts = others;
      _flatRows = _buildFlatRows(hearings, others);
      _listSignature = sig;
      _loading = false;
    });
  }

  Future<QuerySnapshot<Map<String, dynamic>>?> _loadUserNotifications(
    String uid, {
    required bool fromCache,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(_listLimit);
    try {
      if (fromCache) {
        return await query
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 1));
      }
      return await query.get().timeout(const Duration(seconds: 4));
    } catch (_) {
      query = _firestore
          .collection('notifications')
          .where('userId', isEqualTo: uid)
          .limit(_listLimit);
      try {
        if (fromCache) {
          return await query
              .get(const GetOptions(source: Source.cache))
              .timeout(const Duration(seconds: 1));
        }
        return await query.get().timeout(const Duration(seconds: 4));
      } catch (_) {
        return null;
      }
    }
  }

  HearingInboxRow _slimHearingRow(HearingInboxRow row) {
    return HearingInboxRow(
      rowKey: row.rowKey,
      notificationDocId: row.notificationDocId,
      data: _slimMap(row.data),
      sortTime: row.sortTime,
    );
  }

  Map<String, dynamic> _slimOtherAlert(String id, Map<String, dynamic> data) {
    final ts = (data['createdAt'] as Timestamp?)?.toDate();
    return {
      'id': id,
      'type': 'notification',
      'firestoreType': (data['type'] as String? ?? '').toLowerCase(),
      'title': data['title'] ?? 'Notification',
      'message': _clip(data['message'], 160),
      'summary': _clip(data['summary'], 240),
      'caseNo': data['caseNo'],
      'clientName': data['clientName'],
      'courtBranch': data['courtBranch'],
      'hearingDocId': data['hearingDocId'],
      'isRead': data['isRead'] == true,
      'timestamp': ts,
      'icon': Icons.notifications_outlined,
      'color': AppTheme.royalBlue,
    };
  }

  Map<String, dynamic> _slimMap(Map<String, dynamic> data) {
    return {
      'type': data['type'],
      'title': data['title'],
      'summary': _clip(data['summary'], 240),
      'message': _clip(data['message'], 160),
      'caseNo': data['caseNo'],
      'clientName': data['clientName'],
      'courtBranch': data['courtBranch'],
      'hearingDate': data['hearingDate'],
      'hearingTime': data['hearingTime'],
      'location': data['location'],
      'hearingDocId': data['hearingDocId'],
      'isRead': data['isRead'] == true,
      'createdAt': data['createdAt'],
    };
  }

  static String _clip(dynamic value, int max) {
    final s = (value as String?)?.trim() ?? '';
    if (s.isEmpty) return '';
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…';
  }

  String _signature(
    List<HearingInboxRow> hearings,
    List<Map<String, dynamic>> others,
  ) {
    final buf = StringBuffer('${hearings.length}:${others.length}');
    for (final r in hearings.take(40)) {
      buf.write('|h${r.rowKey}:${r.isUnread}');
    }
    for (final n in others.take(40)) {
      buf.write('|o${n['id']}:${n['isRead']}');
    }
    return buf.toString();
  }

  DateTime _inboxRowTime(_InboxRow row) {
    return row.hearing?.sortTime ??
        (row.other?['timestamp'] as DateTime?) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<_InboxRow> _buildFlatRows(
    List<HearingInboxRow> hearings,
    List<Map<String, dynamic>> others,
  ) {
    final mixed = <_InboxRow>[
      ...hearings.map(_InboxRow.hearing),
      ...others.map(_InboxRow.other),
    ]..sort((a, b) => _inboxRowTime(b).compareTo(_inboxRowTime(a)));

    final items = <_InboxRow>[];
    String? lastDate;
    for (final row in mixed) {
      final dateKey = DateFormat('MMMM dd, yyyy').format(_inboxRowTime(row));
      if (dateKey != lastDate) {
        items.add(_InboxRow.date(dateKey));
        lastDate = dateKey;
      }
      items.add(row);
    }
    return items;
  }

  int _unreadCount() {
    var n = _hearingRows.where((r) => r.isUnread).length;
    n += _otherAlerts.where((r) => r['isRead'] != true).length;
    return n;
  }

  Future<void> _markHearingRead(HearingInboxRow row) async {
    if (!row.isUnread) return;
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;

    final nextHearings = [
      for (final item in _hearingRows)
        if (item.rowKey == row.rowKey)
          HearingInboxRow(
            rowKey: item.rowKey,
            notificationDocId: item.notificationDocId,
            data: {...item.data, 'isRead': true},
            sortTime: item.sortTime,
          )
        else
          item,
    ];
    if (!mounted) return;
    setState(() {
      _hearingRows = nextHearings;
      _flatRows = _buildFlatRows(nextHearings, _otherAlerts);
      _listSignature = _signature(nextHearings, _otherAlerts);
    });

    unawaited(
      HearingNotificationFanoutService.instance.markInboxRowAsRead(
        userId: uid,
        notificationDocId: row.notificationDocId,
        inboxRowKey: row.rowKey,
        rowData: row.data,
      ),
    );
  }

  Future<void> _markOtherRead(String id) async {
    if (id.isEmpty) return;
    final nextOthers = [
      for (final row in _otherAlerts)
        if (row['id'] == id) {...row, 'isRead': true} else row,
    ];
    if (!mounted) return;
    setState(() {
      _otherAlerts = nextOthers;
      _flatRows = _buildFlatRows(_hearingRows, nextOthers);
      _listSignature = _signature(_hearingRows, nextOthers);
    });
    try {
      await _firestore.collection('notifications').doc(id).update({
        'isRead': true,
      });
    } catch (_) {}
  }

  Future<void> _markAllAsRead(String userId) async {
    if (_markingAllRead) return;
    setState(() => _markingAllRead = true);

    final otherIdsToMark = [
      for (final row in _otherAlerts)
        if (row['isRead'] != true) (row['id'] as String? ?? ''),
    ].where((id) => id.isNotEmpty).take(_listLimit).toList();

    final nextHearings = [
      for (final item in _hearingRows)
        HearingInboxRow(
          rowKey: item.rowKey,
          notificationDocId: item.notificationDocId,
          data: {...item.data, 'isRead': true},
          sortTime: item.sortTime,
        ),
    ];
    final nextOthers = [
      for (final row in _otherAlerts) {...row, 'isRead': true},
    ];
    setState(() {
      _hearingRows = nextHearings;
      _otherAlerts = nextOthers;
      _flatRows = _buildFlatRows(nextHearings, nextOthers);
      _listSignature = _signature(nextHearings, nextOthers);
    });

    try {
      unawaited(
        HearingNotificationFanoutService.instance
            .markAllInboxRowsRead(
              userId,
              includeGlobalHearingsFallback: false,
              hearingsOnly: true,
            )
            .timeout(const Duration(seconds: 4)),
      );

      if (otherIdsToMark.isNotEmpty) {
        final batch = _firestore.batch();
        for (final id in otherIdsToMark) {
          batch.update(_firestore.collection('notifications').doc(id), {
            'isRead': true,
          });
        }
        await batch.commit().timeout(const Duration(seconds: 4));
      }
    } catch (_) {
      /* keep optimistic rows */
    } finally {
      if (mounted) setState(() => _markingAllRead = false);
    }
  }

  Widget _buildListItem(_InboxRow item) {
    if (item.isHeader) {
      return Padding(
        key: ValueKey('hdr_${item.label}'),
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(
          item.label!,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.grey[700],
            letterSpacing: 0.2,
          ),
        ),
      );
    }
    if (item.isGap) {
      return const SizedBox(key: ValueKey('gap'), height: 8);
    }
    if (item.isDate) {
      return Padding(
        key: ValueKey('date_${item.label}'),
        padding: const EdgeInsets.only(bottom: 12, top: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.royalBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                item.label!,
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
    if (item.hearing != null) {
      final row = item.hearing!;
      return RepaintBoundary(
        key: ValueKey('hearing_${row.rowKey}'),
        child: _ClientHearingCard(
          row: row,
          onMarkRead: _markHearingRead,
        ),
      );
    }
    final other = item.other!;
    final id = other['id'] as String? ?? '';
    return RepaintBoundary(
      key: ValueKey('other_$id'),
      child: _ClientOtherCard(data: other, onMarkRead: _markOtherRead),
    );
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

    final unread = _unreadCount();
    return Scaffold(
      backgroundColor: AppTheme.lightGray,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: AppTheme.royalBlue,
        iconTheme: const IconThemeData(color: AppTheme.white),
        actions: [
          TextButton(
            onPressed: _markingAllRead ? null : () => _markAllAsRead(user.uid),
            child: Text(
              _markingAllRead
                  ? 'Marking...'
                  : (unread > 0 ? 'Mark all read' : 'Mark all read'),
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.white),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(user.uid, showSpinner: false),
        child: _loading && _flatRows.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                ],
              )
            : _flatRows.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
                      Icon(
                        Icons.notifications_none,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No notifications yet',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pull down to refresh',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    cacheExtent: 320,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    itemCount: _flatRows.length,
                    itemBuilder: (context, index) =>
                        _buildListItem(_flatRows[index]),
                  ),
      ),
    );
  }
}

class _InboxRow {
  const _InboxRow.header(this.label)
      : isHeader = true,
        isGap = false,
        isDate = false,
        hearing = null,
        other = null;
  const _InboxRow.gap()
      : isHeader = false,
        isGap = true,
        isDate = false,
        label = null,
        hearing = null,
        other = null;
  const _InboxRow.date(this.label)
      : isHeader = false,
        isGap = false,
        isDate = true,
        hearing = null,
        other = null;
  const _InboxRow.hearing(this.hearing)
      : isHeader = false,
        isGap = false,
        isDate = false,
        label = null,
        other = null;
  const _InboxRow.other(this.other)
      : isHeader = false,
        isGap = false,
        isDate = false,
        label = null,
        hearing = null;

  final bool isHeader;
  final bool isGap;
  final bool isDate;
  final String? label;
  final HearingInboxRow? hearing;
  final Map<String, dynamic>? other;
}

class _ClientHearingCard extends StatefulWidget {
  const _ClientHearingCard({required this.row, required this.onMarkRead});
  final HearingInboxRow row;
  final Future<void> Function(HearingInboxRow row) onMarkRead;

  @override
  State<_ClientHearingCard> createState() => _ClientHearingCardState();
}

class _ClientHearingCardState extends State<_ClientHearingCard> {
  bool _expanded = false;
  late final String _title;
  late final String _subtitle;

  @override
  void initState() {
    super.initState();
    final data = widget.row.data;
    _title = data['title'] as String? ?? 'Court hearing';
    _subtitle = HearingNotificationFormatter.buildSummary(data);
  }

  void _toggleExpanded() {
    final next = !_expanded;
    setState(() => _expanded = next);
    if (next && widget.row.isUnread) {
      unawaited(widget.onMarkRead(widget.row));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRead = !widget.row.isUnread;
    const color = AppTheme.royalBlue;
    final createdAt = (widget.row.data['createdAt'] as Timestamp?)?.toDate() ??
        widget.row.sortTime;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggleExpanded,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.gavel, color: color, size: 28),
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
                                  _title,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: isRead
                                        ? FontWeight.w600
                                        : FontWeight.bold,
                                    color: isRead
                                        ? Colors.grey[700]
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              if (!isRead)
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin:
                                      const EdgeInsets.only(left: 8, top: 6),
                                  decoration: const BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              Icon(
                                _expanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                color: AppTheme.mutedText,
                                size: 22,
                              ),
                            ],
                          ),
                          if (!_expanded && _subtitle.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              _subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 14,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                DateFormat('MMM dd, yyyy • hh:mm a')
                                    .format(createdAt),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Divider(height: 1, color: Colors.grey.shade200),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Hearing details',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.royalBlue,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      HearingNotificationDetailPanel(
                        data: widget.row.data,
                        hearingDocId:
                            widget.row.data['hearingDocId'] as String?,
                        enrichFromRelatedHearings: false,
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ClientOtherCard extends StatefulWidget {
  const _ClientOtherCard({required this.data, required this.onMarkRead});
  final Map<String, dynamic> data;
  final Future<void> Function(String id) onMarkRead;

  @override
  State<_ClientOtherCard> createState() => _ClientOtherCardState();
}

class _ClientOtherCardState extends State<_ClientOtherCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final title = widget.data['title'] as String? ?? 'Notification';
    final message = widget.data['message'] as String? ?? '';
    final id = widget.data['id'] as String? ?? '';
    final isRead = widget.data['isRead'] == true;
    final timestamp = widget.data['timestamp'] as DateTime?;
    final icon = widget.data['icon'] is IconData
        ? widget.data['icon'] as IconData
        : Icons.notifications_outlined;
    final color = widget.data['color'] is Color
        ? widget.data['color'] as Color
        : AppTheme.royalBlue;
    final preview = (widget.data['summary'] as String?)?.trim().isNotEmpty ==
            true
        ? widget.data['summary'] as String
        : message;
    final isExpandable = message.trim().isNotEmpty;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (isExpandable) {
                  final willExpand = !_expanded;
                  setState(() => _expanded = willExpand);
                  if (willExpand && !isRead) unawaited(widget.onMarkRead(id));
                } else if (!isRead) {
                  unawaited(widget.onMarkRead(id));
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
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
                                    fontWeight: isRead
                                        ? FontWeight.w600
                                        : FontWeight.bold,
                                    color: isRead
                                        ? Colors.grey[700]
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              if (!isRead)
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin:
                                      const EdgeInsets.only(left: 8, top: 6),
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              if (isExpandable)
                                Icon(
                                  _expanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  color: AppTheme.mutedText,
                                  size: 22,
                                ),
                            ],
                          ),
                          if (!_expanded && preview.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              preview,
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
                                Icon(
                                  Icons.access_time,
                                  size: 14,
                                  color: Colors.grey[500],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  DateFormat('MMM dd, yyyy • hh:mm a')
                                      .format(timestamp),
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
          ),
          if (_expanded && isExpandable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SelectableText(
                message,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Colors.grey[800],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
