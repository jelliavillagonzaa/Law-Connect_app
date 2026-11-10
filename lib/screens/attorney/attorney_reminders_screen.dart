import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/lightweight_reminder_item.dart';
import '../../services/lightweight_reminders_inbox_service.dart';
import '../../services/attorney_inbox_read_store.dart';
import '../../services/hearing_notification_fanout_service.dart';
import '../../widgets/common/lightweight_reminder_tile.dart';
import '../../utils/hearing_notification_formatter.dart';
import '../../utils/hearing_order_detail.dart';
import '../../services/hearing_calendar_fields.dart';
import '../../widgets/common/hearing_notification_detail_panel.dart';

class AttorneyRemindersScreen extends StatefulWidget {
  const AttorneyRemindersScreen({
    super.key,
    this.showScaffold = true,
    this.includeGlobalHearingsFallback = true,
    this.hearingsOnly = false,
    this.skipHeavyWarmOnOpen = false,
    this.cacheOnlyOnOpen = false,
    this.parentOwnsRefresh = false,
    this.isLoading = false,
  });

  /// When false, renders only the inbox list (for embedding in staff notifications).
  final bool showScaffold;

  /// Clients only see their own `notifications` rows (not every firm `hearings` doc).
  final bool includeGlobalHearingsFallback;

  /// Client inbox: court hearing/order rows only (no appointment reminders).
  final bool hearingsOnly;

  /// When true, use cached inbox only on open; defer sync/warm (bell tap must stay instant).
  final bool skipHeavyWarmOnOpen;

  /// When true, never attach live Firestore inbox listeners (embedded lists / mobile).
  final bool cacheOnlyOnOpen;

  /// When true, parent screen loads inbox data (embedded staff notifications).
  final bool parentOwnsRefresh;

  /// Parent-driven loading state (embedded staff notifications).
  final bool isLoading;

  @override
  State<AttorneyRemindersScreen> createState() =>
      AttorneyRemindersScreenState();
}

class AttorneyRemindersScreenState extends State<AttorneyRemindersScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Set<String> _locallyReadRowKeys = <String>{};
  List<HearingInboxRow>? _rows;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _hearingsLiveSub;
  StreamSubscription<List<HearingInboxRow>>? _inboxSub;
  Timer? _inboxStreamDebounce;
  Timer? _deferredInboxTimer;
  Timer? _loadWatchdog;
  int _loadGen = 0;
  String? _lastInboxSignature;
  bool _inboxStreamAttached = false;
  List<Object>? _cachedListItems;
  String? _cachedListItemsSig;
  int _embeddedVisibleLimit = kIsWeb ? 6 : 12;
  bool _loadingMoreHearings = false;
  bool _loadingLight = true;
  List<LightweightReminderItem> _lightItems = [];

  /// Attorney Reminders must use the fanout inbox (notifications + hearings).
  /// The lightweight path hid court/appointment rows and showed an empty list.
  bool get _useLightweightInbox => false;

  bool get _isAttorneyStandalone =>
      widget.showScaffold &&
      widget.includeGlobalHearingsFallback &&
      !widget.hearingsOnly &&
      !widget.parentOwnsRefresh;

  /// Called from parent screens after a background sync (avoids rebuilding the whole widget).
  Future<void> refreshInbox() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    if (widget.parentOwnsRefresh) {
      try {
        final rows = await HearingNotificationFanoutService.instance
            .fetchStaffInboxLight(userId, notificationLimit: 40)
            .timeout(const Duration(seconds: 5));
        showInboxRows(rows);
        unawaited(
          HearingNotificationFanoutService.instance
              .fetchStaffInboxLight(
                userId,
                includeGlobalHearings: true,
                notificationLimit: 60,
                hearingsLimit: 40,
              )
              .then((full) {
                if (mounted) showInboxRows(full);
              })
              .catchError((_) {}),
        );
      } catch (_) {}
      return;
    }
    await _loadInboxOnce(userId, attachListeners: false, reuseCachedHearings: true);
  }

  void showInboxRows(List<HearingInboxRow> rows) {
    if (!mounted) return;
    final sig = _inboxSignature(rows);
    if (sig == _lastInboxSignature) return;
    _lastInboxSignature = sig;
    _cachedListItems = null;
    final copy = rows
        .where((r) => !isHearingRecordUpdateNotification(r.data))
        .toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _rows = copy);
    });
  }

  /// Hot reload on web can leave fields undefined — always read through these.
  List<HearingInboxRow> get _safeRows {
    try {
      return List<HearingInboxRow>.from(_rows ?? const []);
    } catch (_) {
      _rows = const [];
      return _rows!;
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
    _startInboxListener();
  }

  @override
  void reassemble() {
    super.reassemble();
    // Hot reload does not re-run [initState]; re-bind inbox on web/debug.
    _rows ??= const [];
    _locallyReadRowKeys = _safeLocallyReadKeys;
    _startInboxListener();
  }

  void _startInboxListener() {
    if (_isAttorneyStandalone) {
      final fanout = HearingNotificationFanoutService.instance;
      final uid = _auth.currentUser?.uid;
      List<HearingInboxRow> initial = const [];
      if (uid != null && uid.isNotEmpty) {
        final cached = fanout.peekInboxRows(
          uid,
          includeGlobalHearingsFallback: true,
        );
        if (cached != null) {
          initial = cached
              .where(
                (r) {
                  final slim = _slimAttorneyInboxData(r.data);
                  return !isHearingRecordUpdateNotification(slim) &&
                      !HearingCalendarFields.isNonCourtHearingSpam(slim);
                },
              )
              .toList();
        }
      }
      _rows = initial.isNotEmpty ? initial : null;
      _loadingMoreHearings = true;
      _loadWatchdog?.cancel();
      _loadWatchdog = Timer(const Duration(seconds: 8), () {
        if (!mounted) return;
        setState(() {
          _rows ??= const [];
          _loadingMoreHearings = false;
        });
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadAttorneyRemindersDirect());
      });
      return;
    }

    final userId = _auth.currentUser?.uid;
    final fanout = HearingNotificationFanoutService.instance;

    if (userId == null) {
      _rows = const [];
      return;
    }

    if (_useLightweightInbox) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadLightweightInbox(userId));
      });
      return;
    }

    _inboxSub?.cancel();
    _inboxSub = null;

    final cached = fanout.peekInboxRows(
      userId,
      includeGlobalHearingsFallback: widget.includeGlobalHearingsFallback,
      hearingsOnly: widget.hearingsOnly,
    );
    _rows = cached != null
        ? List<HearingInboxRow>.from(cached)
        : const <HearingInboxRow>[];
    _loadWatchdog?.cancel();
    _loadWatchdog = Timer(const Duration(milliseconds: 700), () {
      if (!mounted || _rows != null) return;
      setState(() => _rows = const []);
    });

    if (widget.parentOwnsRefresh) return;

    if (!widget.skipHeavyWarmOnOpen) {
      fanout.warmInbox(
        userId,
        includeGlobalHearingsFallback: widget.includeGlobalHearingsFallback,
        hearingsOnly: widget.hearingsOnly,
      );
      unawaited(_loadInboxOnce(userId, attachListeners: true));
      if (!kIsWeb) {
        _attachInboxStream(userId);
      }
      return;
    }

    if (widget.cacheOnlyOnOpen) return;

    // Embedded in a parent scroll view — defer one fetch after paint (parent may also refresh).
    if (!widget.showScaffold) {
      _scheduleDeferredInboxRefresh(userId, hadCache: cached != null);
      return;
    }

    // Bell tap: show cached rows immediately; defer network + Firestore listeners.
    _scheduleDeferredInboxRefresh(userId, hadCache: cached != null);
  }

  void _scheduleDeferredInboxRefresh(String userId, {required bool hadCache}) {
    if (widget.cacheOnlyOnOpen) return;

    _deferredInboxTimer?.cancel();
    final delay = kIsWeb
        ? const Duration(milliseconds: 80)
        : hadCache
            ? const Duration(milliseconds: 400)
            : const Duration(milliseconds: 80);
    _deferredInboxTimer = Timer(delay, () {
      if (!mounted) return;
      unawaited(
        _loadInboxOnce(
          userId,
          attachListeners: false,
          reuseCachedHearings: hadCache,
        ),
      );
    });
    if (kIsWeb) {
      Timer(delay + const Duration(seconds: 2), () {
        if (!mounted || _inboxStreamAttached) return;
        _attachInboxStream(userId);
      });
    }
  }

  void _attachInboxStream(String userId) {
    if (_inboxStreamAttached || kIsWeb) return;
    _inboxStreamAttached = true;
    final fanout = HearingNotificationFanoutService.instance;
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
        final sig = _inboxSignature(rows);
        if (sig == _lastInboxSignature) return;
        _inboxStreamDebounce?.cancel();
        _inboxStreamDebounce = Timer(const Duration(milliseconds: 350), () {
          if (!mounted) return;
          if (sig == _lastInboxSignature) return;
          _lastInboxSignature = sig;
          _cachedListItems = null;
          setState(() => _rows = rows
              .where((r) => !isHearingRecordUpdateNotification(r.data))
              .toList());
        });
      },
      onError: (_) {},
    );
  }

  String _inboxSignature(List<HearingInboxRow> rows) {
    final buf = StringBuffer('${rows.length}');
    for (final r in rows.take(40)) {
      buf.write('|${r.rowKey}:${r.isUnread}');
    }
    return buf.toString();
  }

  Future<void> _loadLightweightInbox(String userId) async {
    if (mounted) {
      setState(() {
        _loadingLight = true;
        _loadingMoreHearings = false;
      });
    }

    var items = <LightweightReminderItem>[];
    try {
      items = await LightweightRemindersInboxService.loadNotificationReminders(
        userId,
      );
      if (!mounted) return;

      await Future<void>.delayed(
        Duration(milliseconds: kIsWeb ? 800 : 1500),
      );
      if (!mounted) return;

      final merged = await LightweightRemindersInboxService.mergeGlobalHearings(
        userId,
        items,
      );
      if (!mounted) return;

      setState(() {
        _lightItems = merged;
        _loadingLight = false;
        _loadingMoreHearings = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          if (_lightItems.isEmpty && items.isNotEmpty) {
            _lightItems = items;
          }
          _loadingLight = false;
          _loadingMoreHearings = false;
        });
      }
    }
  }

  void _markLightItemRead(LightweightReminderItem item) {
    final userId = _auth.currentUser?.uid;
    if (userId == null || item.isRead) return;

    final idx = _lightItems.indexWhere((r) => r.rowKey == item.rowKey);
    if (idx >= 0 && mounted) {
      setState(() => _lightItems[idx] = item.markRead());
    }

    unawaited(
      HearingNotificationFanoutService.instance.markInboxRowAsRead(
        userId: userId,
        notificationDocId: item.notificationDocId,
        inboxRowKey: item.rowKey,
        rowData: item.hearingDocId != null
            ? {
                'hearingDocId': item.hearingDocId,
                'type': item.type,
                'title': item.title,
              }
            : null,
      ),
    );
  }

  Widget _buildLightweightBody() {
    if (_loadingLight) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(height: 14),
              Text(
                'Loading reminders…',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_lightItems.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          Icon(Icons.notifications_none, size: 64, color: Colors.grey[400]),
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
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: _listPadding(context),
      itemCount: _lightItems.length,
      cacheExtent: 200,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) {
        final item = _lightItems[index];
        return LightweightReminderTile(
          key: ValueKey(item.rowKey),
          item: item,
          onMarkRead: () => _markLightItemRead(item),
        );
      },
    );
  }

  Future<void> _loadInboxOnce(
    String userId, {
    bool attachListeners = true,
    bool reuseCachedHearings = false,
  }) async {
    final fanout = HearingNotificationFanoutService.instance;
    final gh = widget.includeGlobalHearingsFallback;
    final ho = widget.hearingsOnly;
    try {
      if (ho && !widget.skipHeavyWarmOnOpen) {
        unawaited(fanout.syncClientHearingNotifications());
      }

      final rows = await (!gh && ho
              ? fanout.fetchClientHearingInboxRowsOnce(userId, runSync: false)
              : fanout.fetchInboxRowsOnce(
                  userId,
                  includeGlobalHearingsFallback: gh,
                  hearingsOnly: ho,
                  attachListeners: attachListeners,
                  fetchGlobalHearings: !reuseCachedHearings,
                  reuseCachedHearings: reuseCachedHearings,
                ))
          .timeout(
        const Duration(seconds: 5),
        onTimeout: () =>
            fanout.peekInboxRows(
              userId,
              includeGlobalHearingsFallback: gh,
              hearingsOnly: ho,
            ) ??
            const <HearingInboxRow>[],
      );

      if (!mounted) return;
      final sig = _inboxSignature(rows);
      if (sig == _lastInboxSignature) return;
      _lastInboxSignature = sig;
      _cachedListItems = null;
      setState(() => _rows = rows);

      if (reuseCachedHearings && gh && !ho) {
        unawaited(
          fanout.fetchInboxRowsOnce(
            userId,
            includeGlobalHearingsFallback: gh,
            hearingsOnly: ho,
            attachListeners: false,
            fetchGlobalHearings: true,
          ).then((full) {
            if (!mounted) return;
            final fullSig = _inboxSignature(full);
            if (fullSig == _lastInboxSignature) return;
            _lastInboxSignature = fullSig;
            _cachedListItems = null;
            setState(() => _rows = full);
          }),
        );
      }

      // Heavy hearing scan runs in background — never block the reminders UI.
      if (gh && !ho && rows.where((r) => r.isHearingSource).isEmpty) {
        unawaited(_backgroundHearingSync(userId));
      }
    } catch (_) {
      if (mounted && _rows == null) {
        setState(() => _rows = const []);
      }
    }
  }

  Future<void> _backgroundHearingSync(String userId) async {
    final fanout = HearingNotificationFanoutService.instance;
    final gh = widget.includeGlobalHearingsFallback;
    final ho = widget.hearingsOnly;
    try {
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

  Future<void> _refreshInbox() async {
    if (_isAttorneyStandalone) {
      await _loadAttorneyRemindersDirect(force: true);
      return;
    }
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    if (_useLightweightInbox) {
      await _loadLightweightInbox(userId);
      return;
    }
    await _loadInboxOnce(userId);
  }

  DateTime _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Map<String, dynamic> _slimAttorneyInboxData(Map<String, dynamic> data) {
    String clip(dynamic value, [int max = 160]) {
      final s = HearingCalendarFields.asDisplayString(value);
      if (s.isEmpty) return '';
      if (s.length <= max) return s;
      return '${s.substring(0, max)}…';
    }

    return {
      'type': data['type'],
      'title': data['title'],
      'summary': clip(data['summary'], 240),
      'message': clip(data['message'], 160),
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

  Future<String?> _resolveAttorneyUserId() async {
    var userId = _auth.currentUser?.uid;
    if (userId != null && userId.isNotEmpty) return userId;
    try {
      final user = await _auth
          .authStateChanges()
          .firstWhere((u) => u != null)
          .timeout(const Duration(seconds: 8));
      return user?.uid;
    } catch (_) {
      return _auth.currentUser?.uid;
    }
  }

  HearingInboxRow _rowFromMap({
    required String rowKey,
    String? notificationDocId,
    required Map<String, dynamic> data,
    required DateTime sortTime,
  }) {
    return HearingInboxRow(
      rowKey: rowKey,
      notificationDocId: notificationDocId,
      data: data,
      sortTime: sortTime,
    );
  }

  /// Direct attorney inbox — notifications, hearings, appointments.
  /// Paints cached rows first; purge and extra queries run in the background.
  Future<void> _loadAttorneyRemindersDirect({bool force = false}) async {
    final userId = _auth.currentUser?.uid ?? await _resolveAttorneyUserId();
    if (userId == null || userId.isEmpty) {
      if (mounted) setState(() => _rows = const []);
      return;
    }

    final fanout = HearingNotificationFanoutService.instance;
    unawaited(fanout.loadAttorneyInboxAck(userId));
    unawaited(AttorneyInboxReadStore.instance.ensureLoaded(userId));
    unawaited(fanout.staffReadHearingIds(userId));
    var readHearingIds = fanout.peekReadHearingIds(userId);
    final cached = fanout.peekInboxRows(
      userId,
      includeGlobalHearingsFallback: true,
    );
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() {
        _rows = cached
            .where(
              (r) {
                final slim = _slimAttorneyInboxData(r.data);
                return !isHearingRecordUpdateNotification(slim) &&
                    !HearingCalendarFields.isNonCourtHearingSpam(slim);
              },
            )
            .toList();
        _loadingMoreHearings = true;
      });
    }

    final gen = ++_loadGen;
    final fs = FirebaseFirestore.instance;
    final rows = <HearingInboxRow>[];
    final keys = <String>{};

    void add(HearingInboxRow row) {
      if (keys.add(row.rowKey)) rows.add(row);
    }

    Future<void> loadNotifications(String field) async {
      try {
        final query =
            fs.collection('notifications').where(field, isEqualTo: userId);
        QuerySnapshot<Map<String, dynamic>> snap;
        try {
          snap = await query
              .orderBy('createdAt', descending: true)
              .limit(80)
              .get()
              .timeout(const Duration(seconds: 4));
        } catch (_) {
          snap = await query
              .limit(80)
              .get()
              .timeout(const Duration(seconds: 4));
        }
        for (final doc in snap.docs) {
          final raw = doc.data();
          final type = HearingCalendarFields.asDisplayString(raw['type']).toLowerCase();
          if (type == 'court_email_ingest' ||
              type == 'attorney_inbox_ack' ||
              type == 'attorney_read_keys' ||
              type == 'hearing_activity_update') {
            continue;
          }
          if (type.startsWith('court_') && !type.contains('hearing')) continue;
          final data = _slimAttorneyInboxData(raw);
          if (isHearingRecordUpdateNotification(data) ||
              clientCourtEmailSpamNotification(data) ||
              HearingCalendarFields.isNonCourtHearingSpam(data)) {
            continue;
          }
          if (data['isRead'] != true &&
              (readHearingIds.contains(doc.id) ||
                  readHearingIds.contains(
                    HearingCalendarFields.asDisplayString(data['hearingDocId']),
                  ))) {
            data['isRead'] = true;
          }
          add(
            _rowFromMap(
              rowKey: doc.id,
              notificationDocId: doc.id,
              data: data,
              sortTime: _asDate(raw['createdAt']),
            ),
          );
        }
        debugPrint('attorney inbox notifications[$field]=${snap.docs.length}');
      } catch (e) {
        debugPrint('attorney inbox notifications[$field] failed: $e');
      }
    }

    Future<void> loadHearings() async {
      try {
        final queryFutures = <Future<QuerySnapshot<Map<String, dynamic>>>>[
          fs
              .collection('hearings')
              .where('attorneyUid', isEqualTo: userId)
              .limit(80)
              .get()
              .catchError((_) => fs.collection('hearings').limit(0).get()),
          fs
              .collection('hearings')
              .where('attorneyId', isEqualTo: userId)
              .limit(80)
              .get()
              .catchError((_) => fs.collection('hearings').limit(0).get()),
        ];
        if (widget.includeGlobalHearingsFallback) {
          queryFutures.add(
            fs
                .collection('hearings')
                .orderBy('createdAt', descending: true)
                .limit(80)
                .get()
                .catchError((_) => fs
                    .collection('hearings')
                    .limit(80)
                    .get()
                    .catchError((_) => fs.collection('hearings').limit(0).get())),
          );
        }
        final snaps = await Future.wait(queryFutures).timeout(const Duration(seconds: 4));
        var kept = 0;
        for (final snap in snaps) {
          for (final doc in snap.docs) {
            final hd = doc.data();
            if (!HearingNotificationFanoutService.isDisplayableHearingRow(hd)) {
              continue;
            }
            if (HearingCalendarFields.isNonCourtHearingSpam(
              _slimAttorneyInboxData(hd),
            )) {
              continue;
            }
            if (keys.contains('hearing_${doc.id}')) continue;
            var already = false;
            for (final r in rows) {
              if (HearingCalendarFields.asDisplayString(r.data['hearingDocId']) ==
                  doc.id) {
                already = true;
                break;
              }
            }
            if (already) continue;
            kept++;
            final ts = _asDate(hd['createdAt'] ?? hd['updatedAt']);
            final sort = ts;
            final caseNo = HearingCalendarFields.asDisplayString(hd['caseNo']);
            final client = HearingCalendarFields.asDisplayString(hd['clientName']);
            final summary = HearingCalendarFields.asDisplayString(hd['summary']);
            final storedTitle = HearingCalendarFields.asDisplayString(hd['title']);
            final title = caseNo.isNotEmpty
                ? 'Court hearing — $caseNo'
                : (storedTitle.isNotEmpty
                    ? storedTitle
                    : 'Court hearing / order');
            add(
              _rowFromMap(
                rowKey: 'hearing_${doc.id}',
                data: _slimAttorneyInboxData({
                  'type': 'hearing_activity',
                  'title': title,
                  'summary': summary.isNotEmpty ? summary : client,
                  'message': summary.isNotEmpty ? summary : client,
                  'hearingDocId': doc.id,
                  if (caseNo.isNotEmpty) 'caseNo': caseNo,
                  if (client.isNotEmpty) 'clientName': client,
                  'createdAt': Timestamp.fromDate(sort),
                  'isRead': readHearingIds.contains(doc.id) ||
                      readHearingIds.contains('hearing_${doc.id}'),
                }),
                sortTime: sort,
              ),
            );
          }
        }
        debugPrint('attorney inbox hearings kept=$kept');
      } catch (e) {
        debugPrint('attorney inbox hearings failed: $e');
      }
    }

    Future<void> loadHearingNotifications() async {
      try {
        final snap = await fs
            .collection('hearing_notifications')
            .where('attorneyId', isEqualTo: userId)
            .limit(30)
            .get()
            .timeout(const Duration(seconds: 4));
        for (final doc in snap.docs) {
          final data = doc.data();
          if (HearingCalendarFields.isNonCourtHearingSpam(data)) continue;
          final title = HearingCalendarFields.asDisplayString(data['title']);
          if (title.isEmpty) continue;
          final created = _asDate(
            data['createdAt'] ?? data['notificationDate'] ?? data['hearingDate'],
          );
          final desc = HearingCalendarFields.asDisplayString(data['description']);
          add(
            _rowFromMap(
              rowKey: 'hn_${doc.id}',
              data: {
                'type': 'hearing',
                'title': title,
                'message': desc,
                'summary': desc,
                'isRead': data['status'] == 'sent' ||
                    data['isRead'] == true ||
                    readHearingIds.contains('hn_${doc.id}') ||
                    readHearingIds.contains(doc.id),
                'createdAt': Timestamp.fromDate(
                  created.millisecondsSinceEpoch == 0
                      ? DateTime.now()
                      : created,
                ),
              },
              sortTime: created.millisecondsSinceEpoch == 0
                  ? DateTime.now()
                  : created,
            ),
          );
        }
        debugPrint('attorney inbox hearing_notifications=${snap.docs.length}');
      } catch (e) {
        debugPrint('attorney inbox hearing_notifications failed: $e');
      }
    }

    Future<void> loadAppointments() async {
      try {
        final snap = await fs
            .collection('appointments')
            .where('attorneyId', isEqualTo: userId)
            .limit(20)
            .get()
            .timeout(const Duration(seconds: 4));
        for (final doc in snap.docs) {
          final data = doc.data();
          final status = HearingCalendarFields.asDisplayString(data['status']).toLowerCase();
          if (status == 'cancelled' || status == 'declined') continue;
          final when = _asDate(data['appointmentDateTime'] ?? data['createdAt']);
          final client =
              HearingCalendarFields.asDisplayString(data['clientName']);
          add(
            _rowFromMap(
              rowKey: 'appt_${doc.id}',
              data: {
                'type': 'appointment_scheduled',
                'title': 'Appointment with ${client.isEmpty ? 'Client' : client}',
                'message': HearingCalendarFields.asDisplayString(data['notes']),
                'summary': status.isEmpty ? 'Appointment' : status,
                'isRead': true,
                'createdAt': Timestamp.fromDate(
                  when.millisecondsSinceEpoch == 0 ? DateTime.now() : when,
                ),
              },
              sortTime:
                  when.millisecondsSinceEpoch == 0 ? DateTime.now() : when,
            ),
          );
        }
        debugPrint('attorney inbox appointments=${snap.docs.length}');
      } catch (e) {
        debugPrint('attorney inbox appointments failed: $e');
      }
    }

    Future<void> loadReminderJobs() async {
      try {
        QuerySnapshot<Map<String, dynamic>> snap;
        try {
          snap = await fs
              .collection('hearing_reminder_jobs')
              .orderBy('createdAt', descending: true)
              .limit(80)
              .get()
              .timeout(const Duration(seconds: 4));
        } catch (_) {
          snap = await fs
              .collection('hearing_reminder_jobs')
              .limit(80)
              .get()
              .timeout(const Duration(seconds: 4));
        }
        final covered = <String>{};
        for (final r in rows) {
          final hid = HearingCalendarFields.asDisplayString(r.data['hearingDocId']);
          if (hid.isNotEmpty) covered.add(hid);
          if (r.rowKey.startsWith('hearing_')) {
            covered.add(r.rowKey.substring('hearing_'.length));
          }
        }
        var addedJobs = 0;
        for (final doc in snap.docs) {
          final jd = doc.data();
          final hid = HearingCalendarFields.asDisplayString(jd['hearingDocId']);
          if (hid.isEmpty || !covered.add(hid)) continue;
          if (keys.contains('hearing_$hid')) continue;
          final snapMap = (jd['snapshot'] is Map)
              ? Map<String, dynamic>.from(jd['snapshot'] as Map)
              : <String, dynamic>{};
          if (HearingCalendarFields.isNonCourtHearingSpam(snapMap)) continue;
          final caseNo = HearingCalendarFields.asDisplayString(snapMap['caseNo']);
          final client =
              HearingCalendarFields.asDisplayString(snapMap['clientName']);
          final snapTitle =
              HearingCalendarFields.asDisplayString(snapMap['caseTitle']);
          final title = caseNo.isNotEmpty
              ? 'Court hearing — $caseNo'
              : (snapTitle.isNotEmpty ? snapTitle : 'Court hearing / order');
          final ts = _asDate(jd['createdAt'] ?? jd['scheduledFor']);
          final sort =
              ts.millisecondsSinceEpoch == 0 ? DateTime.now() : ts;
          add(
            _rowFromMap(
              rowKey: 'hearing_$hid',
              data: {
                'type': 'hearing_activity',
                'title': title,
                'summary': client,
                'message': HearingCalendarFields.asDisplayString(
                      snapMap['message'],
                    ).isNotEmpty
                    ? HearingCalendarFields.asDisplayString(snapMap['message'])
                    : client,
                'hearingDocId': hid,
                if (caseNo.isNotEmpty) 'caseNo': caseNo,
                if (client.isNotEmpty) 'clientName': client,
                if (snapTitle.isNotEmpty) 'caseTitle': snapTitle,
                if (HearingCalendarFields.asDisplayString(
                  snapMap['courtBranch'],
                ).isNotEmpty)
                  'location': HearingCalendarFields.asDisplayString(
                    snapMap['courtBranch'],
                  ),
                'createdAt': Timestamp.fromDate(sort),
                'isRead': readHearingIds.contains(hid) ||
                    readHearingIds.contains('hearing_$hid'),
              },
              sortTime: sort,
            ),
          );
          addedJobs++;
        }
        debugPrint(
          'attorney inbox reminder_jobs=${snap.docs.length} added=$addedJobs',
        );
      } catch (e) {
        debugPrint('attorney inbox reminder_jobs failed: $e');
      }
    }

    void commit({bool done = false}) {
      if (!mounted || gen != _loadGen) return;
      readHearingIds = fanout.peekReadHearingIds(userId);
      final flagged = rows
          .map((r) => _rowWithLocalRead(r, readHearingIds))
          .toList();
      final store = AttorneyInboxReadStore.instance;
      final applied = flagged.map(store.withReadFlag).toList();
      applied.sort((a, b) => b.sortTime.compareTo(a.sortTime));
      if (applied.isEmpty && !done) {
        final existing = _rows;
        if (existing != null && existing.isNotEmpty) return;
      }
      rows
        ..clear()
        ..addAll(applied);
      _loadWatchdog?.cancel();
      fanout.publishAttorneyInbox(userId, applied);
      _lastInboxSignature = _inboxSignature(applied);
      _cachedListItems = null;
      setState(() {
        _rows = List<HearingInboxRow>.from(applied);
        _loadingMoreHearings = !done && applied.isNotEmpty;
      });
      store.syncFromRows(applied);
    }

    try {
      try {
        await loadNotifications('userId')
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
      commit();

      try {
        await Future.wait<void>([
          loadHearings(),
          loadAppointments(),
          loadReminderJobs(),
        ]).timeout(const Duration(seconds: 6));
      } catch (_) {}
      commit();

      try {
        await Future.wait<void>([
          loadNotifications('attorneyId'),
          loadHearingNotifications(),
        ]).timeout(const Duration(seconds: 5));
      } catch (_) {}
      commit(done: true);
    } catch (_) {
      if (mounted && gen == _loadGen && _rows == null) {
        setState(() => _rows = const []);
      }
    } finally {
      _loadWatchdog?.cancel();
      if (mounted && gen == _loadGen) {
        setState(() {
          _rows ??= const [];
          _loadingMoreHearings = false;
        });
        _attachLiveHearings(userId);
      }
    }
  }

  void _attachLiveHearings(String userId) {
    if (!_isAttorneyStandalone) return;
    if (_hearingsLiveSub != null) return;
    final fs = FirebaseFirestore.instance;
    _hearingsLiveSub = fs
        .collection('hearings')
        .orderBy('createdAt', descending: true)
        .limit(80)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            _mergeLiveHearings(userId, snap);
          },
          onError: (_) {
            unawaited(_hearingsLiveSub?.cancel());
            _hearingsLiveSub = fs
                .collection('hearings')
                .limit(80)
                .snapshots()
                .listen(
                  (snap) {
                    if (!mounted) return;
                    _mergeLiveHearings(userId, snap);
                  },
                  onError: (_) {},
                );
          },
        );
  }

  void _mergeLiveHearings(
    String userId,
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final current = _rows ?? const <HearingInboxRow>[];
    final keys = current.map((r) => r.rowKey).toSet();
    // Notification rows (`hearing_inapp_<hid>_<uid>`) already cover a hearing.
    // Without this the live listener added a second row for every notice.
    final coveredHearingIds = <String>{
      for (final r in current)
        HearingCalendarFields.asDisplayString(r.data['hearingDocId']),
    }..remove('');
    final added = <HearingInboxRow>[];
    final readIds =
        HearingNotificationFanoutService.instance.peekReadHearingIds(userId);

    for (final doc in snap.docs) {
      final rowKey = 'hearing_${doc.id}';
      if (keys.contains(rowKey)) continue;
      if (coveredHearingIds.contains(doc.id)) continue;
      final hd = doc.data();
      if (!HearingNotificationFanoutService.isDisplayableHearingRow(hd)) {
        continue;
      }
      if (HearingCalendarFields.isNonCourtHearingSpam(hd)) continue;
      final ts = _asDate(hd['createdAt'] ?? hd['updatedAt']);
      final sort = ts.millisecondsSinceEpoch == 0 ? DateTime.now() : ts;
      final caseNo = HearingCalendarFields.asDisplayString(hd['caseNo']);
      final client = HearingCalendarFields.asDisplayString(hd['clientName']);
      final caseTitle = HearingCalendarFields.asDisplayString(hd['caseTitle']);
      final hearingTime = HearingCalendarFields.asDisplayString(hd['hearingTime']);
      final location = HearingCalendarFields.asDisplayString(hd['location']);
      final hearingDate = HearingCalendarFields.asDisplayString(hd['hearingDate']);
      final fullText = HearingCalendarFields.asDisplayString(hd['fullText']);
      final message = HearingCalendarFields.asDisplayString(hd['message']);
      added.add(
        _rowFromMap(
          rowKey: rowKey,
          data: {
            'type': 'hearing_activity',
            'title': caseNo.isNotEmpty
                ? 'Court hearing / order — $caseNo'
                : 'Court hearing / order',
            'summary': client,
            'message': HearingCalendarFields.asDisplayString(hd['summary'])
                    .isNotEmpty
                ? HearingCalendarFields.asDisplayString(hd['summary'])
                : client,
            'hearingDocId': doc.id,
            if (caseNo.isNotEmpty) 'caseNo': caseNo,
            if (client.isNotEmpty) 'clientName': client,
            if (caseTitle.isNotEmpty) 'caseTitle': caseTitle,
            if (hearingTime.isNotEmpty) 'hearingTime': hearingTime,
            if (location.isNotEmpty) 'location': location,
            if (hearingDate.isNotEmpty) 'hearingDate': hearingDate,
            if (fullText.isNotEmpty)
              'fullText': fullText
            else if (message.isNotEmpty)
              'fullText': message,
            'createdAt': Timestamp.fromDate(sort),
            'isRead': readIds.contains(doc.id) || readIds.contains(rowKey),
          },
          sortTime: sort,
        ),
      );
      keys.add(rowKey);
    }

    if (added.isEmpty) return;
    final store = AttorneyInboxReadStore.instance;
    final next = [...added.map(store.withReadFlag), ...current]
      ..sort((a, b) => b.sortTime.compareTo(a.sortTime));
    _cachedListItems = null;
    setState(() => _rows = next);
    HearingNotificationFanoutService.instance.publishAttorneyInbox(userId, next);
    store.syncFromRows(next);
  }

  @override
  void dispose() {
    _inboxSub?.cancel();
    _inboxSub = null;
    unawaited(_hearingsLiveSub?.cancel());
    _hearingsLiveSub = null;
    _inboxStreamDebounce?.cancel();
    _deferredInboxTimer?.cancel();
    _loadWatchdog?.cancel();
    super.dispose();
  }

  bool _isRowRead(HearingInboxRow row) {
    if (AttorneyInboxReadStore.instance.isRead(row)) return true;
    if (_safeLocallyReadKeys.contains(row.rowKey)) return true;
    final hid = HearingCalendarFields.asDisplayString(row.data['hearingDocId']);
    if (hid.isNotEmpty && _safeLocallyReadKeys.contains(hid)) return true;
    if (row.notificationDocId != null &&
        _safeLocallyReadKeys.contains(row.notificationDocId)) {
      return true;
    }
    return !row.isUnread;
  }

  HearingInboxRow _rowWithLocalRead(
    HearingInboxRow row,
    Set<String> readHearingIds,
  ) {
    final uid = _auth.currentUser?.uid ?? '';
    if (_isRowRead(row) ||
        (uid.isNotEmpty &&
            HearingNotificationFanoutService.instance
                .attorneyInboxTreatsAsRead(uid, row.sortTime)) ||
        readHearingIds.contains(row.rowKey) ||
        readHearingIds.contains(row.notificationDocId ?? '') ||
        readHearingIds.contains(
          (HearingCalendarFields.asDisplayString(row.data['hearingDocId'])),
        )) {
      if (!row.isUnread) return row;
      return HearingInboxRow(
        rowKey: row.rowKey,
        notificationDocId: row.notificationDocId,
        data: {...row.data, 'isRead': true},
        sortTime: row.sortTime,
      );
    }
    return row;
  }

  Future<void> _markRowAsRead(HearingInboxRow row) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null || _isRowRead(row)) return;

    setState(() {
      _safeLocallyReadKeys.add(row.rowKey);
      _cachedListItems = null;
    });
    unawaited(AttorneyInboxReadStore.instance.markOne(userId, row));
    AttorneyInboxReadStore.instance.syncFromRows(_safeRows);

    unawaited(
      HearingNotificationFanoutService.instance.markInboxRowAsRead(
        userId: userId,
        notificationDocId: row.notificationDocId,
        inboxRowKey: row.rowKey,
        rowData: row.data,
      ),
    );
  }

  Future<void> _markAllAsRead() async {
    final userId = _auth.currentUser?.uid ?? await _resolveAttorneyUserId();
    if (userId == null || userId.isEmpty) return;

    if (_useLightweightInbox) {
      setState(() {
        _lightItems = _lightItems.map((i) => i.markRead()).toList();
      });
      await HearingNotificationFanoutService.instance.markAllInboxRowsRead(
        userId,
      );
      return;
    }

    _loadGen++;
    final marked = _safeRows
        .map(
          (r) => HearingInboxRow(
            rowKey: r.rowKey,
            notificationDocId: r.notificationDocId,
            data: {...r.data, 'isRead': true},
            sortTime: r.sortTime,
          ),
        )
        .toList();
    final allKeys = <String>{};
    for (final r in marked) {
      allKeys.add(r.rowKey);
      final hid = HearingCalendarFields.asDisplayString(r.data['hearingDocId']);
      if (hid.isNotEmpty) allKeys.add(hid);
      final nid = r.notificationDocId?.trim() ?? '';
      if (nid.isNotEmpty) allKeys.add(nid);
    }
    setState(() {
      _locallyReadRowKeys.addAll(allKeys);
      _rows = marked;
      _cachedListItems = null;
    });
    HearingNotificationFanoutService.instance.publishAttorneyInbox(
      userId,
      marked,
    );
    await AttorneyInboxReadStore.instance.markAll(userId, marked);

    await HearingNotificationFanoutService.instance.markAllInboxRowsRead(
      userId,
      allNotificationTypes: true,
      includeGlobalHearingsFallback: widget.includeGlobalHearingsFallback,
      hearingsOnly: widget.hearingsOnly,
    );
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
    if (data['_lightweight'] == true) {
      return HearingCalendarFields.asDisplayString(data['summary']);
    }
    final type = HearingCalendarFields.asDisplayString(data['type']).toLowerCase();
    if (type.contains('hearing') ||
        HearingCalendarFields.asDisplayString(data['hearingDocId']).isNotEmpty) {
      return HearingNotificationFormatter.buildSummary(data);
    }

    final summary = HearingCalendarFields.asDisplayString(data['summary']);
    final remarks = HearingCalendarFields.asDisplayString(data['remarks']);
    if (summary.isNotEmpty) {
      return remarks.isNotEmpty ? '$summary • Remarks: $remarks' : summary;
    }
    if (remarks.isNotEmpty) return 'Remarks: $remarks';

    final typeLabel = HearingCalendarFields.asDisplayString(data['type']);
    return _getReminderTitle(typeLabel);
  }

  bool _hasExpandableBody(Map<String, dynamic> data, String message) {
    if (data['_lightweight'] == true) {
      return _isHearingDetail(data) || message.trim().isNotEmpty;
    }
    if (message.trim().isNotEmpty) return true;
    final type = HearingCalendarFields.asDisplayString(data['type']).toLowerCase();
    if (type.contains('hearing')) return true;
    if (HearingCalendarFields.asDisplayString(data['hearingDocId']).isNotEmpty) {
      return true;
    }
    return HearingNotificationFormatter.fieldsFromNotificationData(data)
        .isNotEmpty;
  }

  bool _isHearingDetail(Map<String, dynamic> data) {
    final type = HearingCalendarFields.asDisplayString(data['type']).toLowerCase();
    return type.contains('hearing') ||
        HearingCalendarFields.asDisplayString(data['hearingDocId']).isNotEmpty;
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

  List<Object> _buildListItemsForRows() {
    final rows = List<HearingInboxRow>.from(_safeRows)
      ..sort((a, b) => b.sortTime.compareTo(a.sortTime));

    final items = <Object>[];
    String? lastDate;
    for (final row in rows) {
      final dateKey = DateFormat('MMMM dd, yyyy').format(row.sortTime);
      if (dateKey != lastDate) {
        items.add(dateKey);
        lastDate = dateKey;
      }
      items.add(row);
    }
    return items;
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

  Widget _buildMarkAllReadAction() {
    return ValueListenableBuilder<int>(
      valueListenable: AttorneyInboxReadStore.instance.unreadCount,
      builder: (context, unreadCount, _) {
        if (unreadCount == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextButton.icon(
            onPressed: _markAllAsRead,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.done_all, color: Colors.white, size: 18),
            label: Text(
              'Mark read ($unreadCount)',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      },
    );
  }

  EdgeInsets _listPadding(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return EdgeInsets.fromLTRB(16, 12, 16, 24 + bottom);
  }

  Widget _buildBody() {
    if (_rows == null || (_safeRows.isEmpty && _loadingMoreHearings)) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(height: 14),
              Text(
                'Loading reminders…',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_safeRows.isEmpty) {
      if (_useLightweightInbox && _loadingMoreHearings) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(height: 14),
                Text(
                  'Loading court hearings…',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      if (!widget.showScaffold && widget.isLoading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(height: 14),
                Text(
                  'Loading reminders…',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      final emptyContent = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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

      if (!widget.showScaffold) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: emptyContent,
        );
      }

      return ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          ...emptyContent.children,
        ],
      );
    }

    final sig =
        '${_inboxSignature(_safeRows)}|${widget.hearingsOnly}|${_safeLocallyReadKeys.length}';
    final items = _cachedListItems != null && _cachedListItemsSig == sig
        ? _cachedListItems!
        : _buildListItemsForRows();
    if (_cachedListItemsSig != sig) {
      _cachedListItems = items;
      _cachedListItemsSig = sig;
    }

    Widget buildRow(int index) {
      final item = items[index];
      if (item is String) {
        if (item == '__gap__') {
          return const SizedBox(height: 8);
        }
        return _sectionHeader(item);
      }
      final row = item as HearingInboxRow;
      return RepaintBoundary(
        child: _ReminderCardTile(
          key: ValueKey(row.rowKey),
          row: row,
          isRead: _isRowRead(row),
          onMarkRead: () => _markRowAsRead(row),
          getReminderTitle: _getReminderTitle,
          getReminderIcon: _getReminderIcon,
          getReminderColor: _getReminderColor,
          listSubtitle: _listSubtitle,
          hasExpandableBody: _hasExpandableBody,
          isHearingDetail: _isHearingDetail,
        ),
      );
    }

    if (!widget.showScaffold) {
      if (items.isEmpty) return const SizedBox.shrink();
      final visibleCount = items.length > _embeddedVisibleLimit
          ? _embeddedVisibleLimit
          : items.length;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < visibleCount; i++) buildRow(i),
            if (items.length > _embeddedVisibleLimit)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: TextButton(
                  onPressed: () {
                    setState(() => _embeddedVisibleLimit += kIsWeb ? 6 : 12);
                  },
                  child: Text(
                    'Show more (${items.length - _embeddedVisibleLimit} remaining)',
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: _listPadding(context),
      itemCount: items.length + (_loadingMoreHearings ? 1 : 0),
      cacheExtent: kIsWeb ? 480 : 320,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: false,
      itemBuilder: (_, index) {
        if (_loadingMoreHearings && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  'Loading more court hearings…',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }
        final rowIndex = _loadingMoreHearings ? index - 1 : index;
        return buildRow(rowIndex);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final body =
        _useLightweightInbox ? _buildLightweightBody() : _buildBody();
    if (!widget.showScaffold) return body;

    return Scaffold(
      backgroundColor: AppTheme.lightGray,
      appBar: AppBar(
        title: const Text(
          'Reminders',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppTheme.royalBlue,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [_buildMarkAllReadAction()],
        actionsPadding: const EdgeInsets.only(right: 4),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _refreshInbox,
          child: body,
        ),
      ),
    );
  }
}

/// Expand/collapse is local so tapping a card does not rebuild the whole reminders list.
class _ReminderCardTile extends StatefulWidget {
  const _ReminderCardTile({
    super.key,
    required this.row,
    required this.isRead,
    required this.onMarkRead,
    required this.getReminderTitle,
    required this.getReminderIcon,
    required this.getReminderColor,
    required this.listSubtitle,
    required this.hasExpandableBody,
    required this.isHearingDetail,
  });

  final HearingInboxRow row;
  final bool isRead;
  final VoidCallback onMarkRead;
  final String Function(String type) getReminderTitle;
  final IconData Function(String type) getReminderIcon;
  final Color Function(String type) getReminderColor;
  final String Function(Map<String, dynamic> data) listSubtitle;
  final bool Function(Map<String, dynamic> data, String message) hasExpandableBody;
  final bool Function(Map<String, dynamic> data) isHearingDetail;

  @override
  State<_ReminderCardTile> createState() => _ReminderCardTileState();
}

class _ReminderCardTileState extends State<_ReminderCardTile> {
  bool _expanded = false;
  bool _detailReady = false;
  bool _loadingDetail = false;
  Map<String, dynamic>? _detailData;

  Future<void> _ensureDetailLoaded() async {
    if (_detailData != null || _loadingDetail) return;
    setState(() => _loadingDetail = true);
    try {
      final hid = HearingCalendarFields.asDisplayString(
        widget.row.data['hearingDocId'],
      );
      _detailData = await loadHearingOrderDetail(
        hearingDocId: hid,
        notificationDocId: widget.row.notificationDocId,
        seed: widget.row.data,
      );
    } catch (_) {}
    if (mounted) setState(() => _loadingDetail = false);
  }

  Future<void> _onHeaderTap() async {
    final willExpand = !_expanded;
    if (willExpand) {
      final hearing = widget.isHearingDetail(widget.row.data);
      setState(() {
        _expanded = true;
        _detailReady = !hearing;
      });
      if (!widget.isRead) widget.onMarkRead();
      if (hearing) {
        await _ensureDetailLoaded();
        if (mounted) setState(() => _detailReady = true);
      }
      return;
    }
    setState(() {
      _expanded = false;
      _detailReady = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.row.data;
    final detailData = _detailData ?? data;
    final type = HearingCalendarFields.asDisplayString(data['type']);
    final title = HearingCalendarFields.asDisplayString(data['title']).isNotEmpty
        ? HearingCalendarFields.asDisplayString(data['title'])
        : widget.getReminderTitle(type);
    final message = HearingCalendarFields.asDisplayString(data['message']);
    final subtitle = widget.listSubtitle(data);
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final isRead = widget.isRead;
    final color = widget.getReminderColor(type);
    final hasBody = widget.hasExpandableBody(data, message);

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
          child: Icon(widget.getReminderIcon(type), color: color, size: 24),
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
              if (!_expanded && subtitle.isNotEmpty) ...[
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
            _expanded ? Icons.expand_less : Icons.expand_more,
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
                    onTap: _onHeaderTap,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: header,
                    ),
                  ),
                ),
                if (_expanded)
                  Column(
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
                              widget.isHearingDetail(detailData)
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
                            if (widget.isHearingDetail(data) && !_detailReady)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              )
                            else if (widget.isHearingDetail(detailData))
                              HearingNotificationDetailPanel(
                                data: detailData,
                                hearingDocId: () {
                                  final hid =
                                      HearingCalendarFields.asDisplayString(
                                    detailData['hearingDocId'],
                                  );
                                  return hid.isEmpty ? null : hid;
                                }(),
                              )
                            else ...[
                              if (HearingCalendarFields.asDisplayString(detailData['remarks']).isNotEmpty) ...[
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFBEB),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFFDE68A),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(
                                            Icons.notes_rounded,
                                            size: 15,
                                            color: Color(0xFFB45309),
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            'Remarks:',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF92400E),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      SelectableText(
                                        HearingCalendarFields.asDisplayString(
                                          detailData['remarks'],
                                        ),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF78350F),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              SelectableText(
                                HearingCalendarFields.asDisplayString(
                                  detailData['message'],
                                ).isNotEmpty
                                    ? HearingCalendarFields.asDisplayString(
                                        detailData['message'],
                                      )
                                    : message,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.45,
                                  color: Colors.grey[800],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            )
          : InkWell(
              onTap: () {
                if (!isRead) widget.onMarkRead();
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: header,
              ),
            ),
    );
  }
}
