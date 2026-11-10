import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../models/appointment_model.dart';
import '../../pages/case/case_detail_page.dart';
import '../../pages/chat/chat_page.dart';
import '../../services/auth_service.dart';
import '../../services/enhanced_appointment_service.dart';
import '../../theme/app_theme.dart';
import 'chat_screen.dart';
import '../../utils/quiet_console.dart';
import '../../widgets/empty_state.dart';
import 'attorney_selection_screen.dart';
import 'request_appointment_screen.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final EnhancedAppointmentService _appointmentService =
      EnhancedAppointmentService();

  late TabController _tabController;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _appointmentSubscription;

  List<AppointmentModel> _allAppointments = const [];
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startListening();
    });
  }

  @override
  void dispose() {
    _appointmentSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _startListening() {
    final user = _authService.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    _appointmentSubscription?.cancel();
    final query = FirebaseFirestore.instance
        .collection('appointments')
        .where('clientId', isEqualTo: user.uid);

    _appointmentSubscription = query.snapshots().listen(
      (snapshot) {
        if (!mounted) return;
        _applyAppointments(snapshot.docs);
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _error = safeErrorString(e);
          _isLoading = false;
        });
      },
    );
  }

  Future<void> _refresh() async {
    final user = _authService.currentUser;
    if (user == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('clientId', isEqualTo: user.uid)
          .get();
      if (mounted) {
        _applyAppointments(snapshot.docs);
      }
    } catch (e) {
      if (mounted && _allAppointments.isEmpty) {
        setState(() => _error = safeErrorString(e));
      }
    }
  }

  void _applyAppointments(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final list = <AppointmentModel>[];
    for (final doc in docs) {
      try {
        list.add(AppointmentModel.fromFirestore(doc));
      } catch (_) {}
    }

    setState(() {
      _allAppointments = list;
      _error = null;
      _isLoading = false;
    });
  }

  List<AppointmentModel> _getUpcomingAppointments() {
    final now = DateTime.now();
    final list = _allAppointments.where((apt) {
      final status = apt.status.toLowerCase().trim();
      if (status == 'completed' ||
          status == 'cancelled' ||
          status == 'declined') {
        return false;
      }
      // If the appointment date/time has already passed, it is considered completed/past
      return !apt.appointmentDateTime.isBefore(now);
    }).toList();

    // Sort ascending: nearest appointment first
    list.sort((a, b) => a.appointmentDateTime.compareTo(b.appointmentDateTime));
    return list;
  }

  List<AppointmentModel> _getCompletedAppointments() {
    final now = DateTime.now();
    final list = _allAppointments.where((apt) {
      final status = apt.status.toLowerCase().trim();
      if (status == 'cancelled' || status == 'declined') {
        return false;
      }
      // Appointments with past date/time or status == 'completed'
      return status == 'completed' || apt.appointmentDateTime.isBefore(now);
    }).toList();

    // Sort descending: most recently completed first
    list.sort((a, b) => b.appointmentDateTime.compareTo(a.appointmentDateTime));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: AppTheme.lightBackground,
        appBar: AppBar(title: const Text('Appointments')),
        body: const Center(child: Text('Not logged in')),
      );
    }

    final upcoming = _getUpcomingAppointments();
    final completed = _getCompletedAppointments();
    final isWeb = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: AppTheme.lightBackground,
      appBar: AppBar(
        title: const Text('Appointments'),
        backgroundColor: AppTheme.royalBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        actions: [
          IconButton(
            tooltip: 'Book Appointment',
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () => openRequestAppointmentFlow(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: AppTheme.gold,
          indicatorWeight: 3,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Upcoming'),
                  if (upcoming.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.gold,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${upcoming.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.deepNavy,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Completed'),
                  if (completed.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${completed.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.gold,
        foregroundColor: AppTheme.deepNavy,
        elevation: 3,
        icon: const Icon(Icons.calendar_month, size: 20),
        label: const Text(
          'Book Appointment',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        onPressed: () => openRequestAppointmentFlow(),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUpcomingTab(upcoming, isWeb),
          _buildCompletedTab(completed, isWeb),
        ],
      ),
    );
  }

  Widget _buildUpcomingTab(List<AppointmentModel> appointments, bool isWeb) {
    if (_isLoading && _allAppointments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _allAppointments.isEmpty) {
      return _buildErrorState();
    }

    if (appointments.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.15),
            EmptyState(
              icon: Icons.event_available_outlined,
              title: 'No Upcoming Appointments',
              message:
                  'You don\'t have any scheduled appointments. Need legal advice? Book a consultation with our attorneys.',
              actionLabel: 'Book an Appointment',
              onAction: () => openRequestAppointmentFlow(),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          isWeb ? 24 : 16,
          16,
          isWeb ? 24 : 16,
          88, // padding for floating action button
        ),
        itemCount: appointments.length,
        itemBuilder: (context, index) {
          return _buildUpcomingAppointmentCard(appointments[index]);
        },
      ),
    );
  }

  Widget _buildCompletedTab(List<AppointmentModel> appointments, bool isWeb) {
    if (_isLoading && _allAppointments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _allAppointments.isEmpty) {
      return _buildErrorState();
    }

    if (appointments.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.15),
            const EmptyState(
              icon: Icons.history_toggle_off,
              title: 'No Completed Appointments',
              message:
                  'Your consultation history will appear here once your sessions are concluded.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          isWeb ? 24 : 16,
          16,
          isWeb ? 24 : 16,
          88,
        ),
        itemCount: appointments.length,
        itemBuilder: (context, index) {
          return _buildCompletedAppointmentCard(appointments[index]);
        },
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppTheme.error),
            const SizedBox(height: 16),
            const Text(
              'Error loading appointments',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              style: AppTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _startListening,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingAppointmentCard(AppointmentModel appointment) {
    final status = appointment.status.toLowerCase().trim();
    final isPending = status == 'pending';
    final dt = appointment.appointmentDateTime;

    final relativeText = _getRelativeDateText(dt);
    final statusColor = _getStatusColor(status);
    final statusLabel = _getStatusLabel(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPending
              ? Colors.amber.shade200
              : Colors.grey.withValues(alpha: 0.15),
          width: isPending ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Relative tag and Status Chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isPending
                  ? Colors.amber.withValues(alpha: 0.08)
                  : AppTheme.royalBlue.withValues(alpha: 0.04),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                // Relative tag
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: relativeText == 'Today'
                        ? AppTheme.gold
                        : AppTheme.royalBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    relativeText.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: relativeText == 'Today'
                          ? AppTheme.deepNavy
                          : AppTheme.royalBlue,
                    ),
                  ),
                ),
                const Spacer(),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPending
                            ? Icons.schedule
                            : Icons.check_circle_outline,
                        size: 13,
                        color: statusColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date & Time Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.royalBlue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.calendar_month,
                        color: AppTheme.royalBlue,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('EEEE, MMM dd, yyyy').format(dt),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.darkText,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 14,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                DateFormat('hh:mm a').format(dt),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Attorney info
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppTheme.royalBlue.withValues(alpha: 0.1),
                      child: const Icon(
                        Icons.person,
                        size: 20,
                        color: AppTheme.royalBlue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appointment.attorneyName != null &&
                                    appointment.attorneyName!.trim().isNotEmpty
                                ? appointment.attorneyName!
                                : 'Assigned Attorney',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.darkText,
                            ),
                          ),
                          Text(
                            _getAppointmentTypeLabel(appointment.appointmentType),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Case topic if present
                if (appointment.caseTitle != null &&
                    appointment.caseTitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          appointment.caseTitle!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],

                // Pending Banner
                if (isPending) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.amber.shade900,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Awaiting attorney confirmation. You will be notified once confirmed.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Notes if present
                if (appointment.notes != null &&
                    appointment.notes!.trim().isNotEmpty &&
                    appointment.notes !=
                        'Client requested an appointment via app.') ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      appointment.notes!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                // Action Buttons Row
                Row(
                  children: [
                    // Message Attorney
                    if (appointment.attorneyId != null &&
                        appointment.attorneyId!.isNotEmpty) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.royalBlue,
                            side: const BorderSide(color: AppTheme.royalBlue),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          icon: const Icon(Icons.chat_bubble_outline, size: 16),
                          label: const Text(
                            'Message',
                            style: TextStyle(fontSize: 12),
                          ),
                          onPressed: () {
                            Get.to(
                              () => ChatScreen(
                                otherUserId: appointment.attorneyId!,
                                otherUserName: appointment.attorneyName ??
                                    'Attorney',
                                otherUserRole: 'attorney',
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],

                    // Cancel button
                    IconButton(
                      tooltip: 'Cancel Appointment',
                      icon: const Icon(
                        Icons.cancel_outlined,
                        color: AppTheme.error,
                        size: 20,
                      ),
                      onPressed: () => _confirmCancelAppointment(appointment),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedAppointmentCard(AppointmentModel appointment) {
    final dt = appointment.appointmentDateTime;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Completed tag
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green.shade700, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 14, color: Colors.green.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'COMPLETED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('MMM dd, yyyy').format(dt),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Attorney & Type
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.green.withValues(alpha: 0.1),
                      child: Icon(Icons.person, color: Colors.green.shade700, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appointment.attorneyName != null &&
                                    appointment.attorneyName!.trim().isNotEmpty
                                ? appointment.attorneyName!
                                : 'Assigned Attorney',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.darkText,
                            ),
                          ),
                          Text(
                            '${_getAppointmentTypeLabel(appointment.appointmentType)} • ${DateFormat('hh:mm a').format(dt)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                if (appointment.caseTitle != null &&
                    appointment.caseTitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.folder_copy_outlined, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          appointment.caseTitle!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],

                // Consultation notes / Summary if any
                if (appointment.notes != null &&
                    appointment.notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Consultation Notes',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          appointment.notes!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                // Completed Action buttons
                Row(
                  children: [
                    // Book Follow-up
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.royalBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text(
                          'Book Follow-up',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: () {
                          if (appointment.attorneyId != null &&
                              appointment.attorneyId!.isNotEmpty) {
                            Get.to(
                              () => RequestAppointmentScreen(
                                attorneyId: appointment.attorneyId!,
                                attorneyName: appointment.attorneyName ??
                                    'Attorney',
                              ),
                            );
                          } else {
                            openRequestAppointmentFlow();
                          }
                        },
                      ),
                    ),

                    // View Case (if connected to a case)
                    if (appointment.caseId != null &&
                        appointment.caseId!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.royalBlue,
                          side: const BorderSide(color: AppTheme.royalBlue),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        icon: const Icon(Icons.folder_open, size: 16),
                        label: const Text('Case', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          Get.to(() => CaseDetailPage(caseId: appointment.caseId!));
                        },
                      ),
                    ],

                    // Chat icon
                    if (appointment.attorneyId != null &&
                        appointment.attorneyId!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: 'Message Attorney',
                        icon: const Icon(
                          Icons.chat_bubble_outline,
                          color: AppTheme.royalBlue,
                          size: 18,
                        ),
                        onPressed: () {
                          Get.to(
                            () => ChatPage(
                              attorneyId: appointment.attorneyId!,
                              attorneyName: appointment.attorneyName ?? 'Attorney',
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  void _confirmCancelAppointment(AppointmentModel appointment) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Appointment?'),
        content: Text(
          'Are you sure you want to cancel your consultation scheduled for ${DateFormat('MMM dd, yyyy at hh:mm a').format(appointment.appointmentDateTime)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Keep Appointment'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                final res = await _appointmentService.cancelAppointment(
                  appointment.id,
                );
                if (!mounted) return;
                if (res['success'] == true) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Appointment has been cancelled.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(res['message'] ?? 'Failed to cancel appointment.'),
                      backgroundColor: AppTheme.error,
                    ),
                  );
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: ${safeErrorString(e)}'),
                    backgroundColor: AppTheme.error,
                  ),
                );
              }
            },
            child: const Text('Cancel Appointment'),
          ),
        ],
      ),
    );
  }

  String _getRelativeDateText(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diffDays = target.difference(today).inDays;

    if (diffDays == 0) return 'Today';
    if (diffDays == 1) return 'Tomorrow';
    if (diffDays == -1) return 'Yesterday';
    if (diffDays > 1 && diffDays <= 7) return 'In $diffDays days';
    if (diffDays > 7) return DateFormat('MMM dd').format(dt);
    return 'Past';
  }

  String _getAppointmentTypeLabel(String type) {
    switch (type.toLowerCase().trim()) {
      case 'in_office':
        return '🏢 In-Office Meeting';
      case 'phone_call':
        return '📞 Phone Consultation';
      case 'online_meeting':
        return '💻 Online Video Call';
      default:
        return '📅 $type';
    }
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase().trim()) {
      case 'pending':
        return 'PENDING APPROVAL';
      case 'upcoming':
      case 'scheduled':
      case 'confirmed':
        return 'CONFIRMED';
      case 'rescheduled':
        return 'RESCHEDULED';
      case 'completed':
        return 'COMPLETED';
      case 'cancelled':
        return 'CANCELLED';
      default:
        return status.toUpperCase();
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase().trim()) {
      case 'pending':
        return Colors.orange.shade800;
      case 'upcoming':
      case 'scheduled':
      case 'confirmed':
        return const Color(0xFF1B5E20); // Deep green
      case 'completed':
        return const Color(0xFF2E7D32);
      case 'rescheduled':
        return Colors.blue.shade800;
      case 'cancelled':
        return AppTheme.error;
      default:
        return Colors.grey.shade700;
    }
  }
}
