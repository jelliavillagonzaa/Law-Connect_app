import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../models/appointment_model.dart';
import '../../models/user_model.dart';
import '../../pages/attorney/confirm_appointment_schedule_page.dart';
import '../../services/chat_service.dart';
import '../../services/enhanced_appointment_service.dart';
import '../../widgets/staff/staff_ui_theme.dart';
import 'staff_client_chat_screen.dart';

class StaffPendingAppointmentsScreen extends StatefulWidget {
  final bool embedded;
  final String? assignedAttorneyId;
  final Stream<List<AppointmentModel>>? sharedAppointmentsStream;
  final List<AppointmentModel>? initialAppointments;

  const StaffPendingAppointmentsScreen({
    super.key,
    this.embedded = false,
    this.assignedAttorneyId,
    this.sharedAppointmentsStream,
    this.initialAppointments,
  });

  @override
  State<StaffPendingAppointmentsScreen> createState() =>
      _StaffPendingAppointmentsScreenState();
}

class _StaffPendingAppointmentsScreenState
    extends State<StaffPendingAppointmentsScreen> {
  final EnhancedAppointmentService _appointmentService =
      EnhancedAppointmentService();
  final ChatService _chatService = ChatService();

  String? _assignedAttorneyId;
  Stream<List<AppointmentModel>>? _appointmentsStream;
  List<AppointmentModel>? _initialAppointments;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Map<String, String> _resolvedClientNames = {};
  final Set<String> _pendingNameFetches = {};

  bool _looksLikeEmailOrUsername(String name) {
    final s = name.trim();
    if (s.isEmpty) return true;
    if (s.contains('@')) return true;
    final lower = s.toLowerCase();
    if (lower == 'client' || lower == 'user' || lower == 'someone') return true;
    // Detect raw usernames (e.g. meathsjambo7252005) with digits and no spaces
    if (!s.contains(' ') && RegExp(r'\d{3,}').hasMatch(s)) return true;
    return false;
  }

  String _cleanFallbackName(String raw) {
    var s = raw.trim();
    if (s.contains('@')) {
      s = s.split('@').first;
    }
    s = s.replaceAll(RegExp(r'\d+$'), '');
    if (s.isEmpty) return 'Client';
    return s
        .split(RegExp(r'[._\s]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
        .join(' ');
  }

  String _getClientDisplayName(AppointmentModel appointment) {
    if (_resolvedClientNames.containsKey(appointment.clientId)) {
      return _resolvedClientNames[appointment.clientId]!;
    }
    final raw = appointment.clientName.trim();
    if (!_looksLikeEmailOrUsername(raw)) {
      return raw;
    }
    _resolveClientNameAsync(appointment.clientId, appointment.clientName);
    return _cleanFallbackName(raw);
  }

  Future<void> _resolveClientNameAsync(String clientId, String fallback) async {
    if (clientId.isEmpty || _pendingNameFetches.contains(clientId)) return;
    _pendingNameFetches.add(clientId);
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(clientId).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final resolved = UserModel.resolveDisplayName(data).trim();
        if (resolved.isNotEmpty && !_looksLikeEmailOrUsername(resolved)) {
          if (mounted) {
            setState(() {
              _resolvedClientNames[clientId] = resolved;
            });
          }
          return;
        }
      }
      final psSnap = await FirebaseFirestore.instance
          .collection('pending_signups')
          .where('userId', isEqualTo: clientId)
          .limit(1)
          .get();
      if (psSnap.docs.isNotEmpty) {
        final psData = psSnap.docs.first.data();
        final first = (psData['firstName'] ?? '').toString().trim();
        final middle = (psData['middleName'] ?? '').toString().trim();
        final last = (psData['lastName'] ?? '').toString().trim();
        final full = [first, middle, last].where((s) => s.isNotEmpty).join(' ');
        if (full.isNotEmpty) {
          if (mounted) {
            setState(() {
              _resolvedClientNames[clientId] = full;
            });
          }
          return;
        }
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _assignedAttorneyId = widget.assignedAttorneyId;
    _initialAppointments = widget.initialAppointments;

    // 1. Synchronously hook stream - instant Frame 0 setup
    _initStreamSynchronously();

    // 2. Hydrate from cache immediately if no initial appointments passed
    if (_initialAppointments == null || _initialAppointments!.isEmpty) {
      _loadCachedAppointmentsFast();
    }

    // 3. Resolve assigned attorney in background without blocking UI
    if (_assignedAttorneyId == null || _assignedAttorneyId!.trim().isEmpty) {
      _resolveAttorneyIdInBackground();
    }
  }

  @override
  void didUpdateWidget(StaffPendingAppointmentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assignedAttorneyId != widget.assignedAttorneyId ||
        oldWidget.sharedAppointmentsStream != widget.sharedAppointmentsStream ||
        oldWidget.initialAppointments != widget.initialAppointments) {
      _assignedAttorneyId = widget.assignedAttorneyId;
      if (widget.initialAppointments != null &&
          widget.initialAppointments!.isNotEmpty) {
        _initialAppointments = widget.initialAppointments;
      }
      _initStreamSynchronously();
      setState(() {});
    }
  }

  void _initStreamSynchronously() {
    if (widget.sharedAppointmentsStream != null) {
      _appointmentsStream = widget.sharedAppointmentsStream;
      return;
    }

    final aid = _assignedAttorneyId?.trim() ?? '';
    if (aid.isNotEmpty) {
      _appointmentsStream = _appointmentService.getAttorneyAppointments(aid);
    } else {
      _appointmentsStream = _createGeneralPendingStream();
    }
  }

  Stream<List<AppointmentModel>> _createGeneralPendingStream() {
    return FirebaseFirestore.instance
        .collection('appointments')
        .where('status', isEqualTo: 'pending')
        .limit(100)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => AppointmentModel.fromFirestore(doc))
              .toList();
          list.sort(
            (a, b) => a.appointmentDateTime.compareTo(b.appointmentDateTime),
          );
          return list;
        });
  }

  Future<void> _loadCachedAppointmentsFast() async {
    try {
      final aid = _assignedAttorneyId?.trim() ?? '';
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('appointments');
      if (aid.isNotEmpty) {
        query = query.where('attorneyId', isEqualTo: aid);
      } else {
        query = query.where('status', isEqualTo: 'pending');
      }

      final cached = await query
          .limit(50)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(milliseconds: 300));

      if (cached.docs.isNotEmpty && mounted) {
        final list = <AppointmentModel>[];
        for (final doc in cached.docs) {
          try {
            list.add(AppointmentModel.fromFirestore(doc));
          } catch (_) {}
        }
        list.sort(
          (a, b) => a.appointmentDateTime.compareTo(b.appointmentDateTime),
        );
        if (mounted &&
            (_initialAppointments == null || _initialAppointments!.isEmpty)) {
          setState(() {
            _initialAppointments = list;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _resolveAttorneyIdInBackground() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      DocumentSnapshot<Map<String, dynamic>>? doc;
      try {
        doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.cache));
      } catch (_) {}
      if (doc == null || !doc.exists) {
        doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 2));
      }
      final aid = (doc.data()?['assignedAttorneyId'] as String?)?.trim() ?? '';
      if (aid.isNotEmpty && mounted && aid != _assignedAttorneyId) {
        setState(() {
          _assignedAttorneyId = aid;
          if (widget.sharedAppointmentsStream == null) {
            _appointmentsStream = _appointmentService.getAttorneyAppointments(aid);
          }
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent();

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: StaffUi.background,
      appBar: AppBar(
        title: Text(
          'Pending Appointments',
          style: StaffUi.style(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: StaffUi.navyDeep,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: content,
    );
  }

  Widget _buildContent() {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    return Container(
      color: StaffUi.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeaderSection(isDesktop: isDesktop),
          Expanded(
            child: StreamBuilder<List<AppointmentModel>>(
              stream: _appointmentsStream,
              initialData: _initialAppointments,
              builder: (context, snapshot) {
                final hasAnyData = (snapshot.hasData && snapshot.data!.isNotEmpty) ||
                    (_initialAppointments != null && _initialAppointments!.isNotEmpty);

                if (snapshot.connectionState == ConnectionState.waiting &&
                    !hasAnyData) {
                  return _buildLoadingShimmer();
                }

                if (snapshot.hasError && !hasAnyData) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 48, color: StaffUi.danger),
                          const SizedBox(height: 12),
                          Text(
                            'Could not load pending appointment requests',
                            style: StaffUi.style(
                              color: StaffUi.danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${snapshot.error}',
                            style: StaffUi.style(
                              fontSize: 12,
                              color: StaffUi.muted,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () {
                              _initStreamSynchronously();
                              setState(() {});
                            },
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Retry'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: StaffUi.navy,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final rawList = snapshot.data ?? _initialAppointments ?? [];
                // Filter status == 'pending'
                var pending = rawList
                    .where((apt) => apt.status.toLowerCase() == 'pending')
                    .toList();

                // If assigned attorney is specified, filter by it
                final aid = _assignedAttorneyId?.trim() ?? '';
                if (aid.isNotEmpty) {
                  pending = pending
                      .where((apt) =>
                          apt.attorneyId == null ||
                          apt.attorneyId!.isEmpty ||
                          apt.attorneyId == aid)
                      .toList();
                }

                // Filter by search query
                if (_searchQuery.trim().isNotEmpty) {
                  final q = _searchQuery.trim().toLowerCase();
                  pending = pending.where((apt) {
                    final resolvedName = _getClientDisplayName(apt).toLowerCase();
                    final clientMatch =
                        apt.clientName.toLowerCase().contains(q) ||
                        resolvedName.contains(q);
                    final notesMatch =
                        apt.notes != null && apt.notes!.toLowerCase().contains(q);
                    final typeMatch =
                        apt.appointmentType.toLowerCase().contains(q);
                    return clientMatch || notesMatch || typeMatch;
                  }).toList();
                }

                if (pending.isEmpty) {
                  return _buildEmptyState();
                }

                if (isDesktop) {
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final appointment in pending)
                          SizedBox(
                            width: 360,
                            child: _buildAppointmentCard(
                              appointment,
                              isDesktop: true,
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
                  padding: const EdgeInsets.all(16),
                  itemCount: pending.length,
                  itemBuilder: (context, index) {
                    final appointment = pending[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildAppointmentCard(
                        appointment,
                        isDesktop: false,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderSection({required bool isDesktop}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 24 : 16,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: StaffUi.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'Pending Appointments',
                      style: StaffUi.style(
                        fontSize: isDesktop ? 20 : 17,
                        fontWeight: FontWeight.bold,
                        color: StaffUi.navyDeep,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF59E0B)),
                      ),
                      child: Text(
                        'STAFF MANAGED',
                        style: StaffUi.style(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Review, accept, or decline client consultation requests',
                  style: StaffUi.style(
                    fontSize: 12,
                    color: StaffUi.muted,
                  ),
                ),
              ],
            ),
          ),
          if (isDesktop) ...[
            const SizedBox(width: 16),
            SizedBox(
              width: 280,
              height: 38,
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                style: StaffUi.style(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search client or topic...',
                  hintStyle: StaffUi.style(fontSize: 13, color: StaffUi.muted),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: StaffUi.background,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: StaffUi.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: StaffUi.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: StaffUi.navy),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingShimmer() {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      itemCount: 4,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: StaffUi.line),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 130,
                    height: 16,
                    decoration: BoxDecoration(
                      color: StaffUi.line.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 65,
                    height: 18,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: 140,
                height: 14,
                decoration: BoxDecoration(
                  color: StaffUi.line.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                height: 22,
                decoration: BoxDecoration(
                  color: StaffUi.background,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: StaffUi.line.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 54,
                    height: 30,
                    decoration: BoxDecoration(
                      color: StaffUi.line.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 62,
                    height: 30,
                    decoration: BoxDecoration(
                      color: StaffUi.line.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.event_available_rounded,
                size: 42,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No matching pending requests'
                  : 'No pending appointment requests',
              style: StaffUi.style(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: StaffUi.navyDeep,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Try adjusting your search terms.'
                  : 'All client consultation requests have been accepted or scheduled.',
              style: StaffUi.style(
                fontSize: 13,
                color: StaffUi.muted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppointmentCard(
    AppointmentModel appointment, {
    required bool isDesktop,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showAppointmentDetails(appointment),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: StaffUi.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1: Date/Time + Meeting Type & PENDING Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: StaffUi.navy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.calendar_today_rounded,
                    size: 14,
                    color: StaffUi.navy,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('MMM dd, yyyy • hh:mm a')
                            .format(appointment.appointmentDateTime),
                        style: StaffUi.style(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: StaffUi.navyDeep,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _formatMeetingType(appointment.appointmentType),
                        style: StaffUi.style(
                          fontSize: 11,
                          color: StaffUi.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF59E0B)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: Color(0xFFD97706),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'PENDING',
                        style: StaffUi.style(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFB45309),
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Row 2: Client Info
            Builder(
              builder: (context) {
                final clientDisplayName = _getClientDisplayName(appointment);
                return Row(
                  children: [
                    CircleAvatar(
                      radius: 11,
                      backgroundColor: StaffUi.goldSoft,
                      child: Text(
                        clientDisplayName.isNotEmpty
                            ? clientDisplayName[0].toUpperCase()
                            : 'C',
                        style: StaffUi.style(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: StaffUi.navyDeep,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'Client: $clientDisplayName',
                        style: StaffUi.style(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: StaffUi.text,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                );
              },
            ),

            // Compact notes / reason if present
            if (appointment.notes != null &&
                appointment.notes!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: StaffUi.background,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  appointment.notes!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StaffUi.style(
                    fontSize: 11.5,
                    color: StaffUi.text.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 10),

            // Row 3: Action buttons (Compact & neat)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Message Client
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                  tooltip: 'Message Client',
                  color: StaffUi.navy,
                  onPressed: () => unawaited(_openChatWithClient(appointment)),
                  style: IconButton.styleFrom(
                    backgroundColor: StaffUi.navy.withValues(alpha: 0.08),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(30, 30),
                    fixedSize: const Size(30, 30),
                  ),
                ),
                const SizedBox(width: 6),
                // Decline Button
                OutlinedButton(
                  onPressed: () => _showDeclineDialog(appointment),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: StaffUi.danger,
                    side: BorderSide(
                      color: StaffUi.danger.withValues(alpha: 0.4),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: const Size(54, 30),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: Text(
                    'Decline',
                    style: StaffUi.style(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: StaffUi.danger,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Accept Button
                ElevatedButton(
                  onPressed: () async {
                    await Get.to(
                      () => ConfirmAppointmentSchedulePage(
                        pendingRequest: appointment,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: StaffUi.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    minimumSize: const Size(62, 30),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Accept',
                    style: StaffUi.style(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatMeetingType(String raw) {
    switch (raw.toLowerCase().replaceAll('-', '_').trim()) {
      case 'in_office':
        return 'In-office Consultation';
      case 'online_meeting':
      case 'online':
        return 'Online Video Meeting';
      case 'phone_call':
      case 'phone':
        return 'Phone Consultation';
      default:
        return raw.isNotEmpty ? raw : 'General Consultation';
    }
  }

  Future<void> _showAppointmentDetails(AppointmentModel appointment) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: StaffUi.navy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.event_note, color: StaffUi.navy, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                'Appointment Request',
                style: StaffUi.style(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: StaffUi.navyDeep,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow(
                'Requested Date:',
                DateFormat('EEEE, MMMM dd, yyyy')
                    .format(appointment.appointmentDateTime),
              ),
              const SizedBox(height: 6),
              _detailRow(
                'Time Slot:',
                DateFormat('hh:mm a').format(appointment.appointmentDateTime),
              ),
              const SizedBox(height: 6),
              _detailRow('Client Name:', _getClientDisplayName(appointment)),
              const SizedBox(height: 6),
              _detailRow(
                'Consultation Mode:',
                _formatMeetingType(appointment.appointmentType),
              ),
              if (appointment.notes != null &&
                  appointment.notes!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Client Notes:',
                  style: StaffUi.style(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: StaffUi.navyDeep,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: StaffUi.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    appointment.notes!,
                    style: StaffUi.style(fontSize: 12, color: StaffUi.text),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Close',
                style: StaffUi.style(color: StaffUi.muted),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _showDeclineDialog(appointment);
              },
              child: Text(
                'Decline',
                style: StaffUi.style(
                  color: StaffUi.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await Get.to(
                  () => ConfirmAppointmentSchedulePage(
                    pendingRequest: appointment,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: StaffUi.navy,
                foregroundColor: Colors.white,
              ),
              child: Text(
                'Accept',
                style: StaffUi.style(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: StaffUi.style(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: StaffUi.muted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: StaffUi.style(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: StaffUi.text,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showDeclineDialog(AppointmentModel appointment) async {
    final TextEditingController reasonController = TextEditingController();
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                'Decline Appointment Request',
                style: StaffUi.style(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: StaffUi.navyDeep,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Provide an optional explanation for declining this appointment request. The client will be notified.',
                    style: StaffUi.style(fontSize: 12.5, color: StaffUi.muted),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    maxLines: 3,
                    style: StaffUi.style(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Reason (optional)...',
                      hintStyle: StaffUi.style(fontSize: 13, color: StaffUi.muted),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: StaffUi.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: StaffUi.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: StaffUi.danger),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancel',
                    style: StaffUi.style(color: StaffUi.muted),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(dialogContext);
                          setDialogState(() => isSubmitting = true);
                          final result = await _appointmentService
                              .updateRequestStatus(
                                appointment.id,
                                status: 'declined',
                                declineReason: reasonController.text,
                              );
                          if (!dialogContext.mounted) return;
                          nav.pop();

                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                result['success'] == true
                                    ? 'Appointment request declined.'
                                    : (result['message'] ?? 'Failed to decline'),
                              ),
                              backgroundColor: result['success'] == true
                                  ? Colors.orange[800]
                                  : StaffUi.danger,
                            ),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: StaffUi.danger,
                    foregroundColor: Colors.white,
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          'Decline Request',
                          style: StaffUi.style(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openChatWithClient(AppointmentModel appointment) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Opening client chat...'),
          duration: Duration(milliseconds: 600),
        ),
      );
    }

    try {
      final chatId = await _chatService.getOrCreateChat(
        user.uid,
        appointment.clientId,
      );

      Get.to(
        () => StaffClientChatScreen(
          chatId: chatId,
          clientId: appointment.clientId,
          clientName: _getClientDisplayName(appointment),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open chat: $e'),
            backgroundColor: StaffUi.danger,
          ),
        );
      }
    }
  }
}
