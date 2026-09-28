import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/hearing_notification_fanout_service.dart';
import '../../utils/hearing_notification_formatter.dart';
import '../../utils/screen_debug_probe.dart';
import '../../widgets/common/hearing_notification_detail_panel.dart';

/// Web client notifications — live inbox so named parties see new hearings immediately.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _WebNotificationsScreenState();
}

class _WebNotificationsScreenState extends State<NotificationsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  final ScreenDebugProbe _probe = ScreenDebugProbe('client_notifications');

  List<HearingInboxRow> _hearingRows = const [];
  List<Map<String, dynamic>> _otherAlerts = const [];
  List<_FlatRow> _flatRows = const [];
  bool _loading = false;
  bool _inFlight = false;
  bool _pendingRefresh = false;
  bool _markingAllRead = false;

  @override
  void initState() {
    super.initState();
    _probe.attach();
    _probe.event('initState');
    _hearingRows = _peekHearings();
    _flatRows = _buildFlatRows(_hearingRows, const []);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = _authService.currentUser?.uid;
      if (uid == null) return;
      _probe.event('postFrame');
      unawaited(_refresh(uid, showSpinner: false));
    });
  }

  @override
  void dispose() {
    _probe.event('dispose');
    _probe.detach();
    super.dispose();
  }

  List<HearingInboxRow> _peekHearings() {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return const [];
    final rows = HearingNotificationFanoutService.instance.peekInboxRows(
          uid,
          includeGlobalHearingsFallback: false,
          hearingsOnly: true,
        ) ??
        const <HearingInboxRow>[];
    return List<HearingInboxRow>.from(rows)
      ..sort((a, b) => b.sortTime.compareTo(a.sortTime));
  }

  Future<void> _refresh(
    String uid, {
    bool showSpinner = false,
    bool forceSync = false,
  }) => _probe.track('refresh', () async {
    if (_inFlight) {
      _pendingRefresh = true;
      return;
    }
    _inFlight = true;
    if (showSpinner && mounted) {
      setState(() => _loading = true);
      Timer(const Duration(seconds: 4), () {
        if (!mounted || !_loading) return;
        setState(() => _loading = false);
      });
    }
    try {
      final fanout = HearingNotificationFanoutService.instance;
      final hearings = await _probe.track(
        'fetchHearings',
        () => fanout.fetchClientHearingInboxRowsOnce(
              uid,
              runSync: false,
              forceSync: forceSync,
            ),
      );

      if (forceSync) {
        unawaited(fanout.syncClientHearingNotifications(force: true));
      }

      List<QuerySnapshot<Map<String, dynamic>>> snaps;
      try {
        final query = _firestore
            .collection('notifications')
            .where('userId', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .limit(40);
        QuerySnapshot<Map<String, dynamic>> snap;
        try {
          snap = await query
              .get(const GetOptions(source: Source.cache))
              .timeout(const Duration(seconds: 1));
          if (snap.docs.isEmpty) {
            snap = await query.get().timeout(const Duration(seconds: 2));
          }
        } catch (_) {
          try {
            snap = await _firestore
                .collection('notifications')
                .where('userId', isEqualTo: uid)
                .limit(40)
                .get()
                .timeout(const Duration(seconds: 2));
          } catch (_) {
            snap = await query.get().timeout(const Duration(seconds: 1));
          }
        }
        snaps = [snap];
      } catch (_) {
        snaps = const [];
      }

      late final List<_FlatRow> rows;
      late final List<Map<String, dynamic>> others;
      late final List<HearingInboxRow> slimHearings;
      _probe.trackSync('mergeAndBuildRows', () {
        others = _mergeOtherAlertsFromDocs(
          snaps.expand((s) => s.docs),
        );
        slimHearings = hearings.take(80).map(_slimHearingRow).toList()
          ..sort((a, b) => b.sortTime.compareTo(a.sortTime));
        rows = _buildFlatRows(slimHearings, others);
      });

      if (!mounted) return;
      setState(() {
        _hearingRows = slimHearings;
        _otherAlerts = others;
        _flatRows = rows;
      });
      _probe.event(
        'refresh:done',
        detail: 'hearings=${hearings.length} rows=${rows.length}',
      );
    } catch (e, st) {
      _probe.event('refresh:ERROR', detail: '$e\n$st');
      if (!mounted) return;
      setState(() {
        _hearingRows = _peekHearings();
        _otherAlerts = const [];
        _flatRows = _buildFlatRows(_hearingRows, const []);
      });
    } finally {
      _inFlight = false;
      if (mounted) setState(() => _loading = false);
      if (_pendingRefresh) {
        _pendingRefresh = false;
        unawaited(_refresh(uid, showSpinner: false));
      }
    }
  });

  int _unreadCount() {
    var n = _hearingRows.where((r) => r.isUnread).length;
    n += _otherAlerts.where((r) => r['isRead'] != true).length;
    return n;
  }

  static String _clipInboxText(dynamic value, int max) {
    final s = (value as String?)?.trim() ?? '';
    if (s.isEmpty) return '';
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…';
  }

  HearingInboxRow _slimHearingRow(HearingInboxRow row) {
    final d = row.data;
    return HearingInboxRow(
      rowKey: row.rowKey,
      notificationDocId: row.notificationDocId,
      data: {
        'type': d['type'],
        'title': d['title'],
        'summary': _clipInboxText(d['summary'], 240),
        'message': _clipInboxText(d['message'], 160),
        'caseNo': d['caseNo'],
        'clientName': d['clientName'],
        'courtBranch': d['courtBranch'],
        'hearingDate': d['hearingDate'],
        'hearingTime': d['hearingTime'],
        'location': d['location'],
        'hearingDocId': d['hearingDocId'],
        'isRead': d['isRead'] == true,
        'createdAt': d['createdAt'],
      },
      sortTime: row.sortTime,
    );
  }

  List<Map<String, dynamic>> _mergeOtherAlertsFromDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    for (final doc in docs) {
      final data = doc.data();
      if (clientCourtEmailSpamNotification(data)) continue;
      final type = (data['type'] as String? ?? '').toLowerCase();
      if (clientHearingInboxType(type)) continue;
      final ts = (data['createdAt'] as Timestamp?)?.toDate();
      merged[doc.id] = {
        'id': doc.id,
        'title': data['title'] ?? 'Notification',
        'message': _clipInboxText(data['message'], 160),
        'summary': _clipInboxText(data['summary'], 240),
        'hearingDocId': data['hearingDocId'],
        'type': type,
        'isRead': data['isRead'] == true,
        'timestamp': ts,
        'sortKey': ts ?? DateTime.fromMillisecondsSinceEpoch(0),
      };
    }
    final list = merged.values.toList()
      ..sort(
        (x, y) =>
            (y['sortKey'] as DateTime).compareTo(x['sortKey'] as DateTime),
      );
    for (final row in list) {
      row.remove('sortKey');
    }
    return list;
  }

  List<Map<String, dynamic>> _mergeOtherAlerts(
    QuerySnapshot<Map<String, dynamic>> a,
    QuerySnapshot<Map<String, dynamic>> b,
  ) {
    return _mergeOtherAlertsFromDocs([...a.docs, ...b.docs]);
  }

  DateTime _inboxRowTime(_FlatRow row) {
    return row.hearing?.sortTime ??
        (row.other?['timestamp'] as DateTime?) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<_FlatRow> _buildFlatRows(
    List<HearingInboxRow> hearings,
    List<Map<String, dynamic>> others,
  ) {
    final mixed = <_FlatRow>[
      ...hearings.take(80).map(_FlatRow.hearing),
      ...others.map(_FlatRow.other),
    ]..sort((a, b) => _inboxRowTime(b).compareTo(_inboxRowTime(a)));

    final items = <_FlatRow>[];
    String? lastDate;
    for (final row in mixed) {
      final dateKey = DateFormat('MMMM dd, yyyy').format(_inboxRowTime(row));
      if (dateKey != lastDate) {
        items.add(_FlatRow.date(dateKey));
        lastDate = dateKey;
      }
      items.add(row);
    }
    return items;
  }

  Future<void> _markRead(String id) async {
    try {
      await _firestore.collection('notifications').doc(id).update({
        'isRead': true,
      });
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _otherAlerts = [
        for (final row in _otherAlerts)
          if (row['id'] == id) {...row, 'isRead': true} else row,
      ];
      _flatRows = _buildFlatRows(_hearingRows, _otherAlerts);
    });
  }

  Future<void> _markHearingRead(HearingInboxRow row) async {
    if (!row.isUnread) return;
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;
    try {
      await HearingNotificationFanoutService.instance.markInboxRowAsRead(
        userId: uid,
        notificationDocId: row.notificationDocId,
        rowData: row.data,
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _hearingRows = [
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
      _flatRows = _buildFlatRows(_hearingRows, _otherAlerts);
    });
  }

  Future<void> _markAllAsRead() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null || _markingAllRead) return;
    setState(() => _markingAllRead = true);
    try {
      await HearingNotificationFanoutService.instance.markAllInboxRowsRead(
        uid,
        includeGlobalHearingsFallback: false,
        hearingsOnly: true,
      );

      final userIdQuery = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: uid)
          .where('isRead', isEqualTo: false)
          .get();
      final clientIdQuery = await _firestore
          .collection('notifications')
          .where('clientId', isEqualTo: uid)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      final seen = <String>{};
      for (final doc in [...userIdQuery.docs, ...clientIdQuery.docs]) {
        if (!seen.add(doc.id)) continue;
        final data = doc.data();
        if (clientCourtEmailSpamNotification(data)) continue;
        batch.update(doc.reference, {'isRead': true});
      }
      if (seen.isNotEmpty) await batch.commit();

      if (!mounted) return;
      setState(() {
        _hearingRows = [
          for (final item in _hearingRows)
            HearingInboxRow(
              rowKey: item.rowKey,
              notificationDocId: item.notificationDocId,
              data: {...item.data, 'isRead': true},
              sortTime: item.sortTime,
            ),
        ];
        _otherAlerts = [
          for (final row in _otherAlerts) {...row, 'isRead': true},
        ];
        _flatRows = _buildFlatRows(_hearingRows, _otherAlerts);
      });
    } catch (_) {
      /* keep existing rows */
    } finally {
      if (mounted) setState(() => _markingAllRead = false);
    }
  }

  Widget _buildListItem(_FlatRow item) {
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
        child: Text(
          item.label!,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppTheme.royalBlue,
          ),
        ),
      );
    }
    if (item.hearing != null) {
      final row = item.hearing!;
      return RepaintBoundary(
        key: ValueKey('hearing_${row.rowKey}'),
        child: _WebHearingCard(row: row, onMarkRead: _markHearingRead),
      );
    }
    final other = item.other!;
    final id = other['id'] as String? ?? '';
    return RepaintBoundary(
      key: ValueKey('other_$id'),
      child: _WebOtherCard(data: other, onMarkRead: _markRead),
    );
  }

  @override
  Widget build(BuildContext context) {
    _probe.onBuild(detail: 'rows=${_flatRows.length} loading=$_loading');
    final user = _authService.currentUser;
    if (user == null) {
      return _probe.wrap(
        Scaffold(
          appBar: AppBar(title: const Text('Notifications')),
          body: const Center(child: Text('Not logged in')),
        ),
      );
    }

    final unread = _unreadCount();
    return _probe.wrap(
      Scaffold(
      backgroundColor: AppTheme.lightGray,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: AppTheme.royalBlue,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: AppTheme.white),
        actions: [
          TextButton(
              onPressed: _markingAllRead ? null : _markAllAsRead,
              child: Text(
                _markingAllRead
                    ? 'Marking...'
                    : (unread > 0
                        ? 'Mark read ($unread)'
                        : 'Mark all read'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            TextButton(
              onPressed: () => _refresh(user.uid),
              child: const Text(
                'Refresh',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(user.uid),
        child: _flatRows.isEmpty
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
                cacheExtent: 480,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                itemCount: _flatRows.length,
                itemBuilder: (context, index) =>
                    _buildListItem(_flatRows[index]),
              ),
      ),
      ),
    );
  }
}

class _FlatRow {
  const _FlatRow.header(this.label)
    : isHeader = true,
      isGap = false,
      isDate = false,
      hearing = null,
      other = null;
  const _FlatRow.gap()
    : isHeader = false,
      isGap = true,
      isDate = false,
      label = null,
      hearing = null,
      other = null;
  const _FlatRow.date(this.label)
    : isHeader = false,
      isGap = false,
      isDate = true,
      hearing = null,
      other = null;
  const _FlatRow.hearing(this.hearing)
    : isHeader = false,
      isGap = false,
      isDate = false,
      label = null,
      other = null;
  const _FlatRow.other(this.other)
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

class _WebHearingCard extends StatefulWidget {
  const _WebHearingCard({required this.row, required this.onMarkRead});
  final HearingInboxRow row;
  final Future<void> Function(HearingInboxRow row) onMarkRead;

  @override
  State<_WebHearingCard> createState() => _WebHearingCardState();
}

class _WebHearingCardState extends State<_WebHearingCard> {
  bool _expanded = false;
  bool _showDetail = false;
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
    setState(() {
      _expanded = next;
      if (!next) _showDetail = false;
    });
    if (next) {
      if (widget.row.isUnread) {
        unawaited(widget.onMarkRead(widget.row));
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _expanded) setState(() => _showDetail = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.gavel, color: AppTheme.royalBlue),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    _title,
                    style: TextStyle(
                      fontWeight: widget.row.isUnread
                          ? FontWeight.bold
                          : FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.row.isUnread)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            subtitle: _subtitle.isNotEmpty
                ? Text(_subtitle, maxLines: 2, overflow: TextOverflow.ellipsis)
                : null,
            trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            onTap: _toggleExpanded,
          ),
          if (_expanded && _showDetail)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: HearingNotificationDetailPanel(
                data: widget.row.data,
                hearingDocId: widget.row.data['hearingDocId'] as String?,
                enrichFromRelatedHearings: false,
              ),
            ),
        ],
      ),
    );
  }
}

class _WebOtherCard extends StatefulWidget {
  const _WebOtherCard({required this.data, required this.onMarkRead});
  final Map<String, dynamic> data;
  final Future<void> Function(String id) onMarkRead;

  @override
  State<_WebOtherCard> createState() => _WebOtherCardState();
}

class _WebOtherCardState extends State<_WebOtherCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final title = widget.data['title'] as String? ?? 'Notification';
    final message = widget.data['message'] as String? ?? '';
    final id = widget.data['id'] as String? ?? '';
    final isRead = widget.data['isRead'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                    ),
                  ),
                ),
                if (!isRead)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            subtitle: !_expanded && message.isNotEmpty
                ? Text(message, maxLines: 2, overflow: TextOverflow.ellipsis)
                : null,
            trailing: message.isNotEmpty
                ? Icon(_expanded ? Icons.expand_less : Icons.expand_more)
                : null,
            onTap: () {
              if (message.isNotEmpty) {
                final willExpand = !_expanded;
                setState(() => _expanded = willExpand);
                if (willExpand && !isRead) unawaited(widget.onMarkRead(id));
              } else if (!isRead) {
                unawaited(widget.onMarkRead(id));
              }
            },
          ),
          if (_expanded && message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(message),
            ),
        ],
      ),
    );
  }
}
