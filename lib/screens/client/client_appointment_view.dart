import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/appointment_model.dart';
import '../../services/enhanced_appointment_service.dart';
import '../../services/auth_service.dart';

class ClientAppointmentView extends StatefulWidget {
  const ClientAppointmentView({super.key});

  @override
  State<ClientAppointmentView> createState() => _ClientAppointmentViewState();
}

class _ClientAppointmentViewState extends State<ClientAppointmentView>
    with SingleTickerProviderStateMixin {
  final EnhancedAppointmentService _appointmentService =
      EnhancedAppointmentService();
  final AuthService _authService = AuthService();

  late TabController _tabController;

  // Color constants
  static const Color primaryRed = Color(0xFF1A4D8F); // Royal Blue

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Filter appointments based on tab (clients can only view)
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

  // Clients cannot reschedule - only view appointments

  String _getAppointmentTypeLabel(String type) {
    switch (type) {
      case 'in_office':
        return 'In-office';
      case 'phone_call':
        return 'Phone Call';
      case 'online_meeting':
        return 'Online Meeting';
      default:
        return type;
    }
  }

  IconData _getAppointmentTypeIcon(String type) {
    switch (type) {
      case 'in_office':
        return Icons.business;
      case 'phone_call':
        return Icons.phone;
      case 'online_meeting':
        return Icons.video_call;
      default:
        return Icons.event;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width > 600;
    final user = _authService.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          backgroundColor: primaryRed,
          title: const Text(
            'My Appointments',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          elevation: 0,
        ),
        body: const Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: primaryRed,
        title: const Text(
          'My Appointments',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
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
                  Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading appointments',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
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
              // StreamBuilder will automatically refresh
            },
            child: ListView.builder(
              padding: EdgeInsets.all(isWeb ? 32 : 16),
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
    final tabNames = ['Today', 'Completed'];
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No ${tabNames[tabIndex].toLowerCase()} appointments',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Date and Time
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 20,
                            color: primaryRed,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat(
                              'EEEE, MMMM dd, yyyy',
                            ).format(appointment.appointmentDateTime),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 18,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat(
                              'hh:mm a',
                            ).format(appointment.appointmentDateTime),
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (isToday) ...[
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: primaryRed.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Today',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: primaryRed,
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: primaryRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: primaryRed, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getAppointmentTypeIcon(appointment.appointmentType),
                        size: 16,
                        color: primaryRed,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _getAppointmentTypeLabel(appointment.appointmentType),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: primaryRed,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),

            // Attorney Name
            if (appointment.attorneyName != null) ...[
              Row(
                children: [
                  Icon(Icons.person, size: 18, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    'Attorney: ${appointment.attorneyName}',
                    style: const TextStyle(fontSize: 15, color: Colors.black87),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Case Title (if available)
            if (appointment.caseTitle != null) ...[
              Row(
                children: [
                  Icon(Icons.folder_copy, size: 18, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Case: ${appointment.caseTitle}',
                      style: TextStyle(fontSize: 15, color: Colors.grey[700]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Notes (if available)
            if (appointment.notes != null && appointment.notes!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.note, size: 18, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        appointment.notes!,
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Clients can only view appointments, not reschedule
          ],
        ),
      ),
    );
  }
}
