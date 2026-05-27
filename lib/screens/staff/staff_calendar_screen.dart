import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/staff_service.dart';
import '../../services/staff_auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/hearing_calendar_fields.dart';
import '../../services/hearing_calendar_sync_service.dart';
import '../../models/case_model.dart';
import '../../models/user_model.dart';
import '../../widgets/common/hearing_calendar_event_body.dart';
import '../../widgets/common/hearing_notification_detail_panel.dart';

class StaffCalendarScreen extends StatefulWidget {
  const StaffCalendarScreen({super.key});

  @override
  State<StaffCalendarScreen> createState() => _StaffCalendarScreenState();
}

class _StaffCalendarScreenState extends State<StaffCalendarScreen> {
  final StaffService _staffService = StaffService();
  final StaffAuthService _staffAuthService = StaffAuthService();
  final NotificationService _notificationService = NotificationService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _assignedAttorneyId;
  DateTime _viewDate = DateTime.now();
  String _viewMode = 'month'; // 'month' or 'week'
  List<Map<String, dynamic>> _calendarEvents = [];
  List<Map<String, dynamic>> _hearingOverlay = [];
  List<CaseModel> _attorneyCases = [];
  bool _isLoading = true;
  bool _didAutoFocusHearingMonth = false;
  String? _syncAttachedAttorneyId;

  // Stream subscriptions
  StreamSubscription<List<CaseModel>>? _casesSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _eventsSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _hearingOverlaySub;
  StreamSubscription<List<Map<String, dynamic>>>? _notificationsSubscription;

  // Calendar color theme (match attorney calendar)
  static const Color calendarBlue = Color.fromARGB(255, 46, 109, 192);
  static const Color calendarGold = Color(0xFFF4C10F);
  static const Color sundayRed = Color(0xFFE53935);
  static const Color hearingEventColor = Color(0xFF5E35B1);

  @override
  void initState() {
    super.initState();
    _notificationService.initialize();
    _loadAttorneyId();
    _checkScheduledReminders();
  }

  Future<void> _checkScheduledReminders() async {
    // Defer the initial check to avoid issues during initState
    Future.microtask(() async {
      if (mounted) {
        await _staffService.checkAndSendScheduledReminders();
      }
    });

    // Also check periodically (every hour)
    Timer.periodic(const Duration(hours: 1), (timer) {
      if (mounted) {
        Future.microtask(() async {
          if (mounted) {
            await _staffService.checkAndSendScheduledReminders();
          }
        });
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _casesSubscription?.cancel();
    _eventsSubscription?.cancel();
    _hearingOverlaySub?.cancel();
    _notificationsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadAttorneyId() async {
    if (!mounted) return;

    final staff = await _staffAuthService.getCurrentStaff();
    if (!mounted) return;

    if (staff != null) {
      Future.microtask(() {
        if (mounted) {
          setState(() {
            _assignedAttorneyId = staff.assignedAttorneyId;
          });
        }
      });
      _loadAttorneyCases();
      _loadCalendarEvents();
      _subscribeHearingOverlay(staff.assignedAttorneyId);
      Future.microtask(
        () => _loadHearingsFromFirestoreFallback(staff.assignedAttorneyId),
      );
      _checkHearingNotifications();
    } else {
      Future.microtask(() {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      });
    }
  }

  void _loadAttorneyCases() {
    if (_assignedAttorneyId == null) return;

    _casesSubscription?.cancel();
    _casesSubscription = _staffService
        .getAttorneyCases(_assignedAttorneyId!)
        .listen((cases) {
          Future.microtask(() {
            if (mounted) {
              setState(() {
                _attorneyCases = cases;
              });
            }
          });
        });
  }

  void _loadCalendarEvents() {
    if (_assignedAttorneyId == null) {
      Future.microtask(() {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      });
      return;
    }

    Future.microtask(() {
      if (mounted) {
        setState(() => _isLoading = true);
      }
    });

    _eventsSubscription?.cancel();
    _eventsSubscription = _staffService
        .getCalendarEvents(_assignedAttorneyId!)
        .listen((events) {
          Future.microtask(() {
            if (mounted) {
              setState(() {
                _calendarEvents = events;
                _isLoading = false;
              });
            }
          });
        });
  }

  void _subscribeHearingOverlay(String? attorneyId) {
    final aid = attorneyId?.trim() ?? '';
    if (aid.isEmpty) return;

    _syncAttachedAttorneyId = aid;
    _hearingOverlaySub?.cancel();
    _hearingOverlaySub = HearingCalendarSyncService.instance
        .watchHearingEntriesForAttorney(aid)
        .listen(
      (rows) {
        if (mounted) {
          setState(() {
            _hearingOverlay = rows;
            _maybeFocusFirstHearingMonth(rows);
          });
        }
      },
      onError: (e) {
        debugPrint('Staff calendar hearings stream: $e');
      },
    );
  }

  Future<void> _loadHearingsFromFirestoreFallback(String? attorneyId) async {
    final aid = attorneyId?.trim() ?? '';
    if (aid.isEmpty) return;
    try {
      final casesSnap = await _firestore
          .collection('cases')
          .where('attorneyId', isEqualTo: aid)
          .get();
      final caseMaps = casesSnap.docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .toList();

      final hearingsSnap =
          await _firestore.collection('hearings').limit(500).get();
      final rows = HearingCalendarSyncService.instance.projectHearingsFromDocs(
        aid,
        caseMaps,
        hearingsSnap.docs,
      );
      if (!mounted || rows.isEmpty) return;
      setState(() {
        _hearingOverlay = rows;
        _maybeFocusFirstHearingMonth(rows);
      });
    } catch (e) {
      debugPrint('Staff calendar hearings fallback: $e');
    }
  }

  List<DateTime> _hearingMonthsOutsideView() {
    final seen = <String>{};
    final out = <DateTime>[];
    for (final ev in _hearingOverlay) {
      final d = _dateTimeFromField(ev['eventDate']);
      if (d == null) continue;
      if (d.year == _viewDate.year && d.month == _viewDate.month) continue;
      final key = '${d.year}-${d.month}';
      if (seen.add(key)) {
        out.add(DateTime(d.year, d.month));
      }
    }
    out.sort((a, b) {
      final c = a.year.compareTo(b.year);
      return c != 0 ? c : a.month.compareTo(b.month);
    });
    return out;
  }

  Widget _buildHearingsOutsideMonthBanner() {
    final months = _hearingMonthsOutsideView();
    if (months.isEmpty) return const SizedBox.shrink();
    return Material(
      color: calendarGold.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(Icons.event_note, size: 18, color: Colors.black87),
            Text(
              'Scheduled court hearings on file appear in another month — View:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[900],
              ),
            ),
            ...months.map(
              (m) => TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: calendarBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  setState(() {
                    _viewDate = DateTime(m.year, m.month);
                  });
                },
                child: Text(
                  DateFormat('MMMM yyyy').format(m),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime? _dateTimeFromField(dynamic raw) {
    if (raw is DateTime) return raw;
    if (raw is Timestamp) return raw.toDate();
    return null;
  }

  void _maybeFocusFirstHearingMonth(List<Map<String, dynamic>> rows) {
    if (_didAutoFocusHearingMonth || rows.isEmpty) return;
    final dates = <DateTime>[];
    for (final row in rows) {
      final d = _dateTimeFromField(row['eventDate']);
      if (d != null) dates.add(d);
    }
    if (dates.isEmpty) return;
    dates.sort();
    final hasInViewMonth = dates.any(
      (d) => d.year == _viewDate.year && d.month == _viewDate.month,
    );
    if (hasInViewMonth) return;
    _didAutoFocusHearingMonth = true;
    final first = dates.first;
    _viewDate = DateTime(first.year, first.month);
  }

  bool _isHearingCalendarEvent(Map<String, dynamic> ev) {
    if ((ev['hearingDocId'] as String?)?.trim().isNotEmpty == true) {
      return true;
    }
    return isAiSyncedCalendarEvent(ev);
  }

  String _hearingDisplayTitle(Map<String, dynamic> ev) {
    final caseNo = (ev['caseNo'] as String?)?.trim();
    if (caseNo != null && caseNo.isNotEmpty) return caseNo;
    final client = (ev['clientName'] as String?)?.trim();
    if (client != null && client.isNotEmpty) return client;
    final caseTitle = (ev['caseTitle'] as String?)?.trim();
    if (caseTitle != null && caseTitle.isNotEmpty) return caseTitle;
    final t = (ev['title'] as String?)?.trim();
    if (t != null && t.isNotEmpty) {
      return t.replaceFirst(RegExp(r'^\[AI\]\s*'), '');
    }
    return 'Hearing';
  }

  void _checkHearingNotifications() {
    if (_assignedAttorneyId == null) return;

    _notificationsSubscription?.cancel();
    _notificationsSubscription = _staffService
        .getUpcomingHearingNotifications(_assignedAttorneyId!)
        .listen((notifications) {
          if (!mounted) return;

          for (var notification in notifications) {
            final notificationDate =
                notification['notificationDate'] as DateTime?;
            if (notificationDate != null) {
              final now = DateTime.now();
              if (notificationDate.year == now.year &&
                  notificationDate.month == now.month &&
                  notificationDate.day == now.day) {
                _sendHearingNotification(notification);
              }
            }
          }
        });
  }

  Future<void> _sendHearingNotification(
    Map<String, dynamic> notification,
  ) async {
    if (!mounted) return;

    final hearingDate = notification['hearingDate'] as DateTime?;
    final title = notification['title'] as String? ?? 'Upcoming Hearing';
    final notificationId = notification['id'] as String?;

    if (hearingDate != null && notificationId != null) {
      final daysUntil = hearingDate.difference(DateTime.now()).inDays;
      final hearingDateStr = DateFormat(
        'EEEE, MMMM dd, yyyy • hh:mm a',
      ).format(hearingDate);

      if (mounted) {
        await _notificationService.showAlert(
          title: '🔔 Hearing Reminder',
          message: '$title\nDate: $hearingDateStr\n($daysUntil days remaining)',
        );
      }

      if (mounted) {
        await _staffService.markNotificationAsSent(notificationId);
      }
    }
  }

  List<Map<String, dynamic>> _getEventsForDate(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final out = <Map<String, dynamic>>[];
    final syncedHearingIds = <String>{};

    void addEvent(Map<String, dynamic> ev) {
      final eventDate = _dateTimeFromField(ev['eventDate']);
      if (eventDate == null) return;
      final evDay = DateTime(
        eventDate.year,
        eventDate.month,
        eventDate.day,
      );
      if (evDay != day) return;
      final hid = (ev['hearingDocId'] as String?)?.trim() ?? '';
      if (hid.isNotEmpty) {
        if (syncedHearingIds.contains(hid)) return;
        syncedHearingIds.add(hid);
      }
      out.add(Map<String, dynamic>.from(ev));
    }

    for (final ev in _hearingOverlay) {
      addEvent(ev);
    }
    for (final ev in _calendarEvents) {
      if (isFirestoreSyncedHearingCalendarRow(ev)) continue;
      if (ev['eventType'] == 'hearing') continue;
      addEvent(ev);
    }

    out.sort((a, b) {
      final ad = _dateTimeFromField(a['eventDate']);
      final bd = _dateTimeFromField(b['eventDate']);
      if (ad == null || bd == null) return 0;
      return ad.compareTo(bd);
    });
    return out;
  }

  Color _getEventTypeColor(String? type) {
    switch (type) {
      case 'deadline':
        return Colors.red;
      case 'hearing':
        return Colors.blue;
      case 'filing':
        return Colors.orange;
      case 'meeting':
        return Colors.green;
      case 'reminder':
        return Colors.purple;
      default:
        return calendarBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_assignedAttorneyId == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: calendarBlue,
          title: const Text(
            'Calendar & Schedule',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: const Center(child: Text('No attorney assigned')),
      );
    }

    final isMobile = MediaQuery.of(context).size.width < 800;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: calendarBlue,
        title: const Text(
          'Calendar & Schedule',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          if (!isMobile)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ToggleButtons(
                isSelected: [_viewMode == 'month', _viewMode == 'week'],
                onPressed: (index) {
                  Future.microtask(() {
                    if (mounted) {
                      setState(() {
                        _viewMode = index == 0 ? 'month' : 'week';
                      });
                    }
                  });
                },
                borderRadius: BorderRadius.circular(8),
                selectedColor: Colors.white,
                fillColor: Colors.white.withOpacity(0.2),
                color: Colors.white70,
                children: const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text('Month'),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text('Week'),
                  ),
                ],
              ),
            ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () => _showAddEventDialog(),
            tooltip: 'New Event',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildCalendarHeader(isMobile: isMobile),
                _buildWeekdayRow(isMobile: isMobile),
                _buildHearingsOutsideMonthBanner(),
                Expanded(
                  child: (isMobile || _viewMode == 'month')
                      ? _buildMonthView()
                      : _buildWeekView(),
                ),
              ],
            ),
    );
  }

  Widget _buildCalendarHeader({required bool isMobile}) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      color: calendarBlue,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white),
            onPressed: () {
              Future.microtask(() {
                if (mounted) {
                  setState(() {
                    _viewDate = _viewMode == 'month' || isMobile
                        ? DateTime(_viewDate.year, _viewDate.month - 1)
                        : _viewDate.subtract(const Duration(days: 7));
                  });
                }
              });
            },
          ),
          Flexible(
            child: Text(
              _viewMode == 'month' || isMobile
                  ? DateFormat('MMMM yyyy').format(_viewDate)
                  : 'Week of ${DateFormat('MMM dd').format(_viewDate)}',
              style: TextStyle(
                fontSize: isMobile ? 18 : 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 10 : 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: calendarGold,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  DateFormat('yyyy').format(_viewDate),
                  style: TextStyle(
                    fontSize: isMobile ? 14 : 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.white),
                onPressed: () {
                  Future.microtask(() {
                    if (mounted) {
                      setState(() {
                        _viewDate = _viewMode == 'month' || isMobile
                            ? DateTime(_viewDate.year, _viewDate.month + 1)
                            : _viewDate.add(const Duration(days: 7));
                      });
                    }
                  });
                },
              ),
            ],
          ),
          if (!isMobile)
            TextButton(
              onPressed: () {
                Future.microtask(() {
                  if (mounted) {
                    setState(() {
                      _viewDate = DateTime.now();
                    });
                  }
                });
              },
              child: const Text('Today', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );
  }

  Widget _buildWeekdayRow({required bool isMobile}) {
    const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: isMobile ? 8 : 10,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(labels.length, (index) {
          final isSunday = index == 0 || index == 6;
          return Expanded(
            child: Center(
              child: Text(
                labels[index],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSunday ? sundayRed : Colors.grey[700],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildMonthView() {
    final firstDayOfMonth = DateTime(_viewDate.year, _viewDate.month, 1);
    final lastDayOfMonth = DateTime(_viewDate.year, _viewDate.month + 1, 0);
    final firstDayWeekday = firstDayOfMonth.weekday;
    final daysInMonth = lastDayOfMonth.day;

    final List<DateTime> days = [];
    for (int i = firstDayWeekday - 1; i > 0; i--) {
      days.add(firstDayOfMonth.subtract(Duration(days: i)));
    }
    for (int i = 1; i <= daysInMonth; i++) {
      days.add(DateTime(_viewDate.year, _viewDate.month, i));
    }
    final remainingDays = 42 - days.length;
    for (int i = 1; i <= remainingDays; i++) {
      days.add(DateTime(_viewDate.year, _viewDate.month + 1, i));
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 200;
    final gridPadding = EdgeInsets.all(isWeb ? 8 : 16);
    final spacing = isWeb ? 4.0 : 8.0;
    final aspectRatio = isWeb ? 0.9 : 1.2;

    return GridView.builder(
      padding: gridPadding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: aspectRatio,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
      ),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final day = days[index];
        final isCurrentMonth = day.month == _viewDate.month;
        final isToday =
            day.year == DateTime.now().year &&
            day.month == DateTime.now().month &&
            day.day == DateTime.now().day;
        final dayEvents = _getEventsForDate(day);

        return _buildDayCell(day, isCurrentMonth, isToday, dayEvents);
      },
    );
  }

  Widget _buildWeekView() {
    final startOfWeek = _viewDate.subtract(
      Duration(days: _viewDate.weekday - 1),
    );
    final weekDays = List.generate(
      7,
      (i) => startOfWeek.add(Duration(days: i)),
    );

    return Row(
      children: weekDays
          .map((day) => Expanded(child: _buildWeekDayColumn(day)))
          .toList(),
    );
  }

  Widget _buildWeekDayColumn(DateTime day) {
    final isToday =
        day.year == DateTime.now().year &&
        day.month == DateTime.now().month &&
        day.day == DateTime.now().day;
    final dayEvents = _getEventsForDate(day);

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isToday ? calendarBlue : Colors.grey[300]!,
          width: isToday ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: dayEvents.isNotEmpty
                ? () => _showEventsForDate(day, dayEvents)
                : () => _showAddEventDialogForDate(day),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isToday
                    ? calendarBlue.withOpacity(0.08)
                    : Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    DateFormat('EEE').format(day),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isToday ? calendarBlue : Colors.black87,
                        ),
                      ),
                      if (dayEvents.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: calendarBlue,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${dayEvents.length}',
                            style: const TextStyle(
                              fontSize: 8,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(4),
              itemCount: dayEvents.length,
              itemBuilder: (context, index) {
                final event = dayEvents[index];
                return _buildTimeSlotEvent(event);
              },
            ),
          ),
          InkWell(
            onTap: () => _showAddEventDialogForDate(day),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.add, size: 20, color: Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell(
    DateTime day,
    bool isCurrentMonth,
    bool isToday,
    List<Map<String, dynamic>> events,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isToday
            ? calendarBlue.withOpacity(0.08)
            : Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isToday ? calendarBlue : Colors.grey[300]!,
          width: isToday ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: events.isNotEmpty
                ? () => _showEventsForDate(day, events)
                : () => _showAddEventDialogForDate(day),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isToday ? FontWeight.w600 : FontWeight.normal,
                      color: isCurrentMonth
                          ? (isToday
                                ? calendarBlue
                                : (day.weekday == DateTime.sunday
                                      ? sundayRed
                                      : Colors.black87))
                          : Colors.grey[400],
                    ),
                  ),
                  if (events.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: calendarBlue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${events.length}',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: events.length > 3 ? 3 : events.length,
              itemBuilder: (context, index) {
                final event = events[index];
                final when = _dateTimeFromField(event['eventDate']);
                final isHearing = _isHearingCalendarEvent(event);
                return InkWell(
                  onTap: () => _showEventDetails(event),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isHearing
                          ? hearingEventColor
                          : _getEventTypeColor(event['eventType']),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (when != null)
                          Text(
                            DateFormat('hh:mm a').format(when),
                            style: const TextStyle(
                              fontSize: 8,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        Text(
                          isHearing
                              ? _hearingDisplayTitle(event)
                              : (event['title'] ?? 'Event'),
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (events.length > 3)
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                '+${events.length - 3} more',
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeSlotEvent(Map<String, dynamic> event) {
    final when = _dateTimeFromField(event['eventDate']);
    final isHearing = _isHearingCalendarEvent(event);
    return InkWell(
      onTap: () => _showEventDetails(event),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isHearing
              ? hearingEventColor
              : _getEventTypeColor(event['eventType']),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (when != null)
              Text(
                DateFormat('hh:mm a').format(when),
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            Text(
              isHearing ? _hearingDisplayTitle(event) : (event['title'] ?? 'Event'),
              style: const TextStyle(fontSize: 12, color: Colors.white),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _showEventsForDate(DateTime date, List<Map<String, dynamic>> events) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width > 600
              ? 500
              : double.infinity,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('MMMM dd, yyyy').format(date),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Builder(
                builder: (context) {
                  final aiN = events.where(isAiSyncedCalendarEvent).length;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${events.length} scheduled item${events.length != 1 ? 's' : ''}',
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${events.length} calendar event${events.length != 1 ? 's' : ''}'
                        '${aiN > 0 ? ' ($aiN AI)' : ''}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final event = events[index];
                    final isHearing = _isHearingCalendarEvent(event);
                    final when = _dateTimeFromField(event['eventDate']);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: isHearing
                          ? hearingEventColor.withOpacity(0.06)
                          : null,
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          if (isHearing) {
                            _showHearingEventDetails(event);
                          } else {
                            _showEventDetails(event);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      isHearing
                                          ? _hearingDisplayTitle(event)
                                          : (event['title'] ?? 'Event'),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if (isAiSyncedCalendarEvent(event))
                                    const Padding(
                                      padding: EdgeInsets.only(left: 8),
                                      child: HearingAiSchedBadge(),
                                    ),
                                  if (isHearing) ...[
                                    Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: hearingEventColor.withOpacity(
                                          0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: hearingEventColor,
                                          width: 1,
                                        ),
                                      ),
                                      child: const Text(
                                        'Hearing',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: hearingEventColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ] else
                                    Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getEventTypeColor(
                                          event['eventType'],
                                        ).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: _getEventTypeColor(
                                            event['eventType'],
                                          ),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        event['eventType'] ?? 'event',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _getEventTypeColor(
                                            event['eventType'],
                                          ),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (when != null) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      size: 16,
                                      color: Colors.grey[600],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      DateFormat('hh:mm a').format(when),
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (isHearing) ...[
                                const SizedBox(height: 8),
                                HearingCalendarEventBody(
                                  data: event,
                                  dense: true,
                                  maxLines: 7,
                                ),
                              ] else if (event['description'] != null &&
                                  event['description']
                                      .toString()
                                      .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  event['description'],
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[700],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showAddEventDialogForDate(date);
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Event'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: calendarBlue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showHearingEventDetails(Map<String, dynamic> ev) async {
    var display = Map<String, dynamic>.from(ev);
    final hearingDocId = (ev['hearingDocId'] as String?)?.trim() ?? '';
    if (hearingDocId.isNotEmpty) {
      try {
        final snap =
            await _firestore.collection('hearings').doc(hearingDocId).get();
        if (snap.exists && snap.data() != null) {
          final hd = snap.data()!;
          final caseMaps = <Map<String, dynamic>>[];
          final caseId = (hd['caseId'] as String?)?.trim() ?? '';
          if (caseId.isNotEmpty) {
            final caseSnap =
                await _firestore.collection('cases').doc(caseId).get();
            if (caseSnap.exists && caseSnap.data() != null) {
              caseMaps.add({'id': caseSnap.id, ...caseSnap.data()!});
            }
          }
          final cn = (hd['caseNo'] as String?)?.trim() ?? '';
          final siblings = _hearingOverlay
              .where(
                (o) =>
                    cn.isNotEmpty &&
                    (o['caseNo'] as String?)?.trim() == cn,
              )
              .toList();
          display = await HearingCalendarFields.loadMergedHearingForDisplay(
            hearingDocId: hearingDocId,
            hearingData: hd,
            caseMaps: caseMaps,
            siblingRows: siblings,
          );
          display['hearingDocId'] = hearingDocId;
          display['readOnly'] = true;
          display['eventType'] = 'hearing';
          display['source'] =
              ev['source'] as String? ?? HearingCalendarSyncService.sourceTag;
        }
      } catch (_) {
        /* keep calendar snapshot */
      }
    }
    if (!mounted) return;
    _showHearingEventDetailsDialog(display);
  }

  void _showHearingEventDetailsDialog(Map<String, dynamic> ev) {
    final title = hearingCalendarDisplayTitle(ev);
    final isAi = isAiSyncedCalendarEvent(ev);
    final et = ev['eventType'];
    final typeLabel = et is String && et.isNotEmpty
        ? et[0].toUpperCase() + et.substring(1)
        : 'Event';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width > 600
              ? 500
              : double.infinity,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                if (isAi) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: calendarGold.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: calendarGold, width: 1),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 18,
                          color: Colors.black87,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Automated schedule — court hearing record from case file (case number, parties, time, venue).',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: hearingEventColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: hearingEventColor, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.gavel,
                        size: 18,
                        color: hearingEventColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        typeLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: hearingEventColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Court hearing particulars (case file record)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 12),
                HearingNotificationDetailPanel(
                  data: ev,
                  hearingDocId: (ev['hearingDocId'] as String?)?.trim(),
                  calendarOnly: true,
                  siblingRows: _hearingOverlay,
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEventDetails(Map<String, dynamic> event) {
    if (_isHearingCalendarEvent(event)) {
      _showHearingEventDetails(event);
      return;
    }
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width > 600
              ? 500
              : double.infinity,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        event['title'] ?? 'Event',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _getEventTypeColor(
                      event['eventType'],
                    ).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _getEventTypeColor(event['eventType']),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    event['eventType'] ?? 'event',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _getEventTypeColor(event['eventType']),
                    ),
                  ),
                ),
                if (_dateTimeFromField(event['eventDate']) != null) ...[
                  const SizedBox(height: 24),
                  _buildDetailRow(
                    icon: Icons.calendar_today,
                    label: 'Date',
                    value: DateFormat('EEEE, MMMM dd, yyyy').format(
                      _dateTimeFromField(event['eventDate'])!,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow(
                    icon: Icons.access_time,
                    label: 'Time',
                    value: DateFormat('hh:mm a').format(
                      _dateTimeFromField(event['eventDate'])!,
                    ),
                  ),
                ],
                if (event['description'] != null &&
                    event['description'].toString().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.note_outlined,
                        size: 20,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Description',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              event['description'],
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showAddEventDialogForDate(DateTime date) async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime? selectedDate = date;
    TimeOfDay? selectedTime = TimeOfDay.now();
    String? eventType;
    String? selectedCaseId;
    String? selectedClientId; // Single client from dropdown
    bool notifyClient = false;
    bool notifyAttorney = false; // To notify the assigned attorney

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          // Helper to safely update state - defer setState to avoid gesture conflicts
          void safeSetState(VoidCallback fn) {
            // Use Future.delayed to defer to next event loop iteration
            Future.delayed(Duration.zero, () {
              if (context.mounted) {
                setState(fn);
              }
            });
          }

          return AlertDialog(
            title: const Text('Add Calendar Event'),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            content: SizedBox(
              width: MediaQuery.of(context).size.width > 600
                  ? 500
                  : double.infinity,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Event Type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'deadline',
                          child: Text('Deadline'),
                        ),
                        DropdownMenuItem(
                          value: 'hearing',
                          child: Text('Hearing'),
                        ),
                        DropdownMenuItem(
                          value: 'filing',
                          child: Text('Filing'),
                        ),
                        DropdownMenuItem(
                          value: 'meeting',
                          child: Text('Meeting'),
                        ),
                        DropdownMenuItem(
                          value: 'reminder',
                          child: Text('Reminder'),
                        ),
                      ],
                      onChanged: (value) {
                        safeSetState(() {
                          eventType = value;
                          if (value != 'hearing') {
                            selectedCaseId = null;
                            selectedClientId = null;
                          }
                        });
                      },
                    ),
                    if (eventType == 'hearing') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Select Case (Optional)',
                          border: OutlineInputBorder(),
                          helperText: 'Link hearing to a case',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('No Case Selected'),
                          ),
                          ..._attorneyCases.map(
                            (caseModel) => DropdownMenuItem(
                              value: caseModel.id,
                              child: Text(caseModel.caseTitle),
                            ),
                          ),
                        ],
                        value: selectedCaseId,
                        onChanged: (value) {
                          safeSetState(() {
                            selectedCaseId = value;
                            if (value != null) {
                              try {
                                final selectedCase = _attorneyCases.firstWhere(
                                  (c) => c.id == value,
                                );
                                selectedClientId = selectedCase.clientId;
                              } catch (e) {
                                selectedClientId = null;
                              }
                            } else {
                              selectedClientId = null;
                            }
                          });
                        },
                      ),
                      if (selectedCaseId != null) ...[
                        const SizedBox(height: 8),
                        StreamBuilder<DocumentSnapshot>(
                          stream: _firestore
                              .collection('users')
                              .doc(selectedClientId)
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data!.exists) {
                              final data =
                                  snapshot.data!.data() as Map<String, dynamic>;
                              final client = UserModel.fromFirestore(
                                data,
                                selectedClientId!,
                              );
                              return Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.person,
                                      size: 16,
                                      color: Colors.blue,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Client: ${client.name}',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    ListTile(
                      title: Text(
                        selectedDate == null
                            ? 'Select Date'
                            : DateFormat('MMM dd, yyyy').format(selectedDate!),
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDate ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (date != null) {
                          safeSetState(() {
                            selectedDate = date;
                          });
                        }
                      },
                    ),
                    ListTile(
                      title: Text(
                        selectedTime == null
                            ? 'Select Time'
                            : selectedTime!.format(context),
                      ),
                      trailing: const Icon(Icons.access_time),
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: selectedTime ?? TimeOfDay.now(),
                        );
                        if (time != null) {
                          safeSetState(() {
                            selectedTime = time;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    // Select Client (Optional) dropdown
                    const Text(
                      'Select Client (Optional)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _loadClientsWithDetails(_assignedAttorneyId),
                      builder: (context, snapshot) {
                        final clients = snapshot.data ?? [];
                        return DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            hintText: 'Select a client *',
                            border: OutlineInputBorder(),
                          ),
                          value: selectedClientId,
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('No Client Selected'),
                            ),
                            ...clients.map(
                              (client) => DropdownMenuItem(
                                value: client['id'] as String,
                                child: Text(
                                  client['name'] as String? ?? 'Client',
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            safeSetState(() {
                              selectedClientId = value;
                              // If client is cleared and Client checkbox is checked, uncheck it
                              if (value == null && notifyClient) {
                                notifyClient = false;
                              }
                            });
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    // Send Reminders To section
                    const Text(
                      'Send Reminders To',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Staff always notified (current user)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Staff (You) - Always notified',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(),
                          // Client checkbox - only enabled if a client is selected
                          CheckboxListTile(
                            title: const Text('Client'),
                            value: notifyClient,
                            onChanged: selectedClientId != null
                                ? (value) {
                                    safeSetState(() {
                                      notifyClient = value ?? true;
                                    });
                                  }
                                : null,
                            activeColor: Colors.blue,
                            contentPadding: EdgeInsets.zero,
                            subtitle: selectedClientId == null
                                ? const Text(
                                    'Select a client first',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  )
                                : notifyClient
                                ? FutureBuilder<DocumentSnapshot>(
                                    future: _firestore
                                        .collection('users')
                                        .doc(selectedClientId)
                                        .get(),
                                    builder: (context, snapshot) {
                                      if (snapshot.hasData &&
                                          snapshot.data!.exists) {
                                        final data =
                                            snapshot.data!.data()
                                                as Map<String, dynamic>;
                                        final clientName =
                                            data['name'] ??
                                            data['fullName'] ??
                                            'Client';
                                        return Text(
                                          'Will remind: $clientName',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.blue,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  )
                                : null,
                          ),
                          // Attorney checkbox (to notify the assigned attorney)
                          CheckboxListTile(
                            title: const Text('Attorney'),
                            value: notifyAttorney,
                            onChanged: (value) {
                              safeSetState(() {
                                notifyAttorney = value ?? true;
                              });
                            },
                            activeColor: Colors.blue,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (titleController.text.isEmpty ||
                      selectedDate == null ||
                      selectedTime == null ||
                      eventType == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please fill all required fields'),
                      ),
                    );
                    return;
                  }

                  final eventDateTime = DateTime(
                    selectedDate!.year,
                    selectedDate!.month,
                    selectedDate!.day,
                    selectedTime!.hour,
                    selectedTime!.minute,
                  );

                  // If notifyClient is checked, use the selectedClientId from the dropdown
                  final clientIdsToRemind =
                      notifyClient && selectedClientId != null
                      ? [selectedClientId!]
                      : <String>[];

                  final shouldSendNow = true; // Always send immediately

                  final result = await _staffService.createCalendarEvent(
                    eventType: eventType!,
                    eventDate: eventDateTime,
                    title: titleController.text,
                    description: descriptionController.text.isEmpty
                        ? null
                        : descriptionController.text,
                    caseId: selectedCaseId,
                    assignedTo: _assignedAttorneyId,
                    clientId: selectedClientId,
                    remindAttorney:
                        notifyAttorney, // Based on checkbox selection
                    remindClient: notifyClient,
                    selectedClientIds: clientIdsToRemind,
                    sendNow: shouldSendNow,
                    notifyStaff:
                        true, // Staff (current user) is always notified
                  );

                  if (result['success'] == true && eventType == 'hearing') {
                    final daysUntil = eventDateTime
                        .difference(DateTime.now())
                        .inDays;
                    if (daysUntil >= 2) {
                      final notificationDate = eventDateTime.subtract(
                        const Duration(days: 2),
                      );
                      final notificationDateStr = DateFormat(
                        'EEEE, MMMM dd, yyyy',
                      ).format(notificationDate);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Hearing scheduled! Notification will be sent on $notificationDateStr (2 days before)',
                          ),
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    }
                  }

                  if (result['success'] == true) {
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Event created successfully'),
                        ),
                      );
                      _loadCalendarEvents();
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result['message'] ?? 'Failed to create event',
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddEventDialog() async {
    await _showAddEventDialogForDate(DateTime.now());
  }

  Future<List<Map<String, dynamic>>> _loadClientsWithDetails(
    String? attorneyId,
  ) async {
    if (attorneyId == null) return [];

    try {
      final casesSnapshot = await _firestore
          .collection('cases')
          .where('attorneyId', isEqualTo: attorneyId)
          .get();

      final clientIds = <String>{};
      for (var doc in casesSnapshot.docs) {
        final data = doc.data();
        final clientId = data['clientId'] as String?;
        if (clientId != null && clientId.trim().isNotEmpty) {
          clientIds.add(clientId);
        }
      }

      if (clientIds.isEmpty) return [];

      final clients = <Map<String, dynamic>>[];
      for (var clientId in clientIds) {
        if (clientId.trim().isEmpty) continue;
        try {
          final clientDoc = await _firestore
              .collection('users')
              .doc(clientId)
              .get();
          if (clientDoc.exists) {
            final clientData = clientDoc.data()!;
            final clientName =
                clientData['name'] ?? clientData['fullName'] ?? 'Client';
            clients.add({'id': clientId, 'name': clientName});
          }
        } catch (e) {
          print('Error loading client $clientId: $e');
        }
      }

      clients.sort(
        (a, b) => (a['name'] as String).compareTo(b['name'] as String),
      );

      return clients;
    } catch (e) {
      print('Error loading clients: $e');
      return [];
    }
  }
}
