import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/hearing_notification_fanout_service.dart';
import '../../utils/hearing_notification_formatter.dart';
import '../../utils/screen_debug_probe.dart';
import '../../widgets/common/hearing_notification_detail_panel.dart';

/// Web-only notifications — no [AttorneyRemindersScreen], no live listeners on open.
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
  List<_FlatRow> _flatRows = const [];
  bool _loading = false;

  static const int _queryLimit = 40;

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
      Future<void>.delayed(
        kIsWeb ? const Duration(milliseconds: 400) : const Duration(seconds: 1),
        () {
          if (mounted) unawaited(_refresh(uid));
        },
      );
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
    return HearingNotificationFanoutService.instance.peekInboxRows(
          uid,
          includeGlobalHearingsFallback: false,
          hearingsOnly: true,
        ) ??
        const [];
  }

  Future<void> _refresh(String uid) => _probe.track('refresh', () async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final fanout = HearingNotificationFanoutService.instance;
      final hearings = await _probe.track(
        'fetchHearings',
        () => fanout.fetchClientHearingInboxRowsOnce(uid, runSync: false),
      );

      final snaps = await _probe.track('fetchOtherAlerts', () async {
        return Future.wait([
          _firestore
              .collection('notifications')
              .where('userId', isEqualTo: uid)
              .limit(_queryLimit)
              .get(),
          _firestore
              .collection('notifications')
              .where('clientId', isEqualTo: uid)
              .limit(_queryLimit)
              .get(),
        ]);
      });

      late final List<_FlatRow> rows;
      _probe.trackSync('mergeAndBuildRows', () {
        final others = _mergeOtherAlerts(snaps[0], snaps[1]);
        rows = _buildFlatRows(hearings, others);
      });

      if (!mounted) return;
      setState(() {
        _hearingRows = hearings;
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
        _flatRows = _buildFlatRows(_hearingRows, const []);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  });

  List<Map<String, dynamic>> _mergeOtherAlerts(
    QuerySnapshot<Map<String, dynamic>> a,
    QuerySnapshot<Map<String, dynamic>> b,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    for (final snap in [a, b]) {
      for (final doc in snap.docs) {
        final data = doc.data();
        if (clientCourtEmailSpamNotification(data)) continue;
        final type = (data['type'] as String? ?? '').toLowerCase();
        if (clientHearingInboxType(type)) continue;
        final ts = (data['createdAt'] as Timestamp?)?.toDate();
        merged[doc.id] = {
          'id': doc.id,
          'title': data['title'] ?? 'Notification',
          'message': data['message'] ?? '',
          'summary': data['summary'],
          'hearingDocId': data['hearingDocId'],
          'type': type,
          'isRead': data['isRead'] == true,
          'timestamp': ts,
          'sortKey': ts ?? DateTime.fromMillisecondsSinceEpoch(0),
        };
      }
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

  List<_FlatRow> _buildFlatRows(
    List<HearingInboxRow> hearings,
    List<Map<String, dynamic>> others,
  ) {
    final items = <_FlatRow>[];
    if (hearings.isNotEmpty) {
      items.add(const _FlatRow.header('New notice court hearings'));
      for (final row in hearings.take(20)) {
        items.add(_FlatRow.hearing(row));
      }
    }
    if (others.isNotEmpty) {
      if (items.isNotEmpty) items.add(const _FlatRow.gap());
      items.add(const _FlatRow.header('Other alerts'));
      String? lastDate;
      for (final n in others) {
        final ts = n['timestamp'] as DateTime?;
        final dateKey = DateFormat(
          'MMMM dd, yyyy',
        ).format(ts ?? DateTime.now());
        if (dateKey != lastDate) {
          items.add(_FlatRow.date(dateKey));
          lastDate = dateKey;
        }
        items.add(_FlatRow.other(n));
      }
    }
    return items;
  }

  Future<void> _markRead(String id) async {
    try {
      await _firestore.collection('notifications').doc(id).update({
        'isRead': true,
      });
    } catch (_) {}
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
        child: _WebHearingCard(row: row),
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

    return _probe.wrap(
      Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: AppTheme.royalBlue,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: AppTheme.white),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
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
                    _loading
                        ? 'Loading notifications...'
                        : 'No notifications yet',
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
                cacheExtent: 200,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
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
  const _WebHearingCard({required this.row});
  final HearingInboxRow row;

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
            title: Text(
              _title,
              style: const TextStyle(fontWeight: FontWeight.w600),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(title),
            subtitle: !_expanded && message.isNotEmpty
                ? Text(message, maxLines: 2, overflow: TextOverflow.ellipsis)
                : null,
            trailing: message.isNotEmpty
                ? Icon(_expanded ? Icons.expand_less : Icons.expand_more)
                : null,
            onTap: message.isEmpty
                ? null
                : () {
                    setState(() => _expanded = !_expanded);
                    if (_expanded) unawaited(widget.onMarkRead(id));
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
