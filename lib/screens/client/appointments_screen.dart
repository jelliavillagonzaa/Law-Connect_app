import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import '../../models/appointment_model.dart';
import '../../services/enhanced_appointment_service.dart';
import '../../services/auth_service.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen>
    with SingleTickerProviderStateMixin {
  final EnhancedAppointmentService _appointmentService =
      EnhancedAppointmentService();
  final AuthService _authService = AuthService();

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Ensure UI rebuilds when user switches tabs so filtering updates
    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<AppointmentModel> _filterAppointments(
    List<AppointmentModel> appointments,
    int tabIndex,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    List<AppointmentModel> filtered;

    switch (tabIndex) {
      case 0: // Today: date == today AND status != "completed"
        filtered = appointments.where((apt) {
          final aptDate = DateTime(
            apt.appointmentDateTime.year,
            apt.appointmentDateTime.month,
            apt.appointmentDateTime.day,
          );
          return aptDate == today && apt.status != 'completed';
        }).toList();
        break;
      case 1: // Completed: status == "completed"
        filtered = appointments
            .where((apt) => apt.status == 'completed')
            .toList();
        break;
      default:
        filtered = [];
    }

    filtered.sort(
      (a, b) => a.appointmentDateTime.compareTo(b.appointmentDateTime),
    );
    return filtered;
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

    final isWeb = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: AppTheme.lightBackground,
      appBar: AppBar(
        title: const Text('Appointments'),
        backgroundColor: AppTheme.royalBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Today'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: StreamBuilder<List<AppointmentModel>>(
        stream: _appointmentService.getClientAppointments(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppTheme.error,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Error loading appointments',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    snapshot.error.toString(),
                    style: AppTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final allAppointments = snapshot.data ?? [];
          final filteredAppointments = _filterAppointments(
            allAppointments,
            _tabController.index,
          );

          if (filteredAppointments.isEmpty) {
            return _buildEmptyState(_tabController.index);
          }

          return RefreshIndicator(
            onRefresh: () async {
              // StreamBuilder automatically updates when Firestore data changes
            },
            child: ListView.builder(
              padding: EdgeInsets.all(isWeb ? 24 : 16),
              itemCount: filteredAppointments.length,
              itemBuilder: (context, index) {
                return _buildAppointmentCard(filteredAppointments[index]);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(int tabIndex) {
    const tabNames = ['Today', 'Completed'];
    return EmptyState(
      icon: Icons.calendar_today_outlined,
      title: 'No ${tabNames[tabIndex]} Appointments',
      message:
          'You don\'t have any ${tabNames[tabIndex].toLowerCase()} appointments yet.',
    );
  }

  Widget _buildAppointmentCard(AppointmentModel appointment) {
    final isToday =
        DateTime(
          appointment.appointmentDateTime.year,
          appointment.appointmentDateTime.month,
          appointment.appointmentDateTime.day,
        ) ==
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date / Time row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_today,
                            size: 16,
                            color: AppTheme.royalBlue,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat(
                              'MMM dd, yyyy',
                            ).format(appointment.appointmentDateTime),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 16,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat(
                              'hh:mm a',
                            ).format(appointment.appointmentDateTime),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          if (isToday) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.royalBlue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Today',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.royalBlue,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Status chip
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(appointment.status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _getStatusColor(appointment.status),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    appointment.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(appointment.status),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),

            // Attorney name (if available)
            if (appointment.attorneyName != null &&
                appointment.attorneyName!.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.person_outline, size: 18, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    appointment.attorneyName!,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Case title (if available)
            if (appointment.caseTitle != null &&
                appointment.caseTitle!.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.folder_copy, size: 18, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      appointment.caseTitle!,
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Appointment type
            Row(
              children: [
                Icon(Icons.event, size: 18, color: AppTheme.royalBlue),
                const SizedBox(width: 8),
                Text(
                  appointment.appointmentType,
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ],
            ),

            // Notes (if any)
            if (appointment.notes != null &&
                appointment.notes!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  appointment.notes!,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'upcoming':
        return Colors.blue;
      case 'scheduled':
        return Colors.blue; // legacy support
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'rescheduled':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}
