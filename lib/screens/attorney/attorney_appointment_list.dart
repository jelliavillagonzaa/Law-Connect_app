import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/appointment_model.dart';
import '../../services/enhanced_appointment_service.dart';
import '../../services/auth_service.dart';
import 'appointment_scheduler_form.dart';
import '../../screens/client/chat_screen.dart';

class AttorneyAppointmentList extends StatefulWidget {
  const AttorneyAppointmentList({super.key});

  @override
  State<AttorneyAppointmentList> createState() =>
      _AttorneyAppointmentListState();
}

class _AttorneyAppointmentListState extends State<AttorneyAppointmentList>
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
    // Rebuild when the selected tab changes so filtering updates correctly
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

  // Filter appointments based on tab
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
          final statusLower = apt.status.toLowerCase();
          return aptDate == today && statusLower != 'completed';
        }).toList();
        break;
      case 1: // Completed: status == "completed"
        filtered = appointments
            .where((apt) => apt.status.toLowerCase() == 'completed')
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

  Future<void> _completeAppointment(AppointmentModel appointment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Appointment'),
        content: const Text('Mark this appointment as completed?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Complete', style: TextStyle(color: primaryRed)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final result = await _appointmentService.completeAppointment(
        appointment.id,
      );
      if (mounted) {
        if (result['success'] == true) {
          // Show success message - StreamBuilder will automatically update the UI
          // The appointment will disappear from "Today" and appear in "Completed" tab
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Appointment marked as completed'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['message'] ?? 'Failed to complete appointment',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _rescheduleAppointment(AppointmentModel appointment) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => AppointmentSchedulerForm(
          clientId: appointment.clientId,
          clientName: appointment.clientName,
          caseId: appointment.caseId,
          existingAppointment: appointment,
        ),
      ),
    );
    // StreamBuilder will automatically refresh
  }

  Future<void> _messageClient(AppointmentModel appointment) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          conversationId: null,
          otherUserId: appointment.clientId,
          otherUserName: appointment.clientName,
        ),
      ),
    );
  }

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
            'Appointments',
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
          'Appointments',
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
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () async {
              await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) => const AppointmentSchedulerForm(),
                ),
              );
              // StreamBuilder will automatically refresh
            },
            tooltip: 'New Appointment',
          ),
        ],
      ),
      body: StreamBuilder<List<AppointmentModel>>(
        stream: _appointmentService.getAttorneyAppointments(user.uid),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Date/Time and Status
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
                            size: 16,
                            color: primaryRed,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat(
                              'MMM dd, yyyy',
                            ).format(appointment.appointmentDateTime),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
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
                                color: primaryRed.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Today',
                                style: TextStyle(
                                  fontSize: 11,
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
            const SizedBox(height: 16),

            // Client Name
            Row(
              children: [
                Icon(Icons.person, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  appointment.clientName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Case Title (if available)
            if (appointment.caseTitle != null) ...[
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

            // Appointment Type
            Row(
              children: [
                Icon(
                  _getAppointmentTypeIcon(appointment.appointmentType),
                  size: 18,
                  color: primaryRed,
                ),
                const SizedBox(width: 8),
                Text(
                  _getAppointmentTypeLabel(appointment.appointmentType),
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ],
            ),

            // Notes (if available)
            if (appointment.notes != null && appointment.notes!.isNotEmpty) ...[
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

            // Action Buttons
            if (appointment.status != 'completed') ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionButton(
                    'Reschedule',
                    Icons.schedule,
                    () => _rescheduleAppointment(appointment),
                  ),
                  _buildActionButton(
                    'Message',
                    Icons.message,
                    () => _messageClient(appointment),
                  ),
                  _buildActionButton(
                    'Complete',
                    Icons.check_circle,
                    () => _completeAppointment(appointment),
                    isPrimary: true,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool isPrimary = false,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: isPrimary ? primaryRed : Colors.grey[700],
            side: BorderSide(color: isPrimary ? primaryRed : Colors.grey[300]!),
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'upcoming':
        return Colors.blue;
      case 'scheduled':
        return Colors.blue; // Legacy support
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
