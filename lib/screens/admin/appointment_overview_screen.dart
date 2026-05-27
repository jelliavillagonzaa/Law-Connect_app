import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/card_row.dart';
import 'admin_appointment_scheduler_form.dart';

class AppointmentOverviewScreen extends StatelessWidget {
  const AppointmentOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: Fetch all appointments from Firestore
    final appointments = <Map<String, dynamic>>[]; // Placeholder

    return Scaffold(
      backgroundColor: AppTheme.lightBackground,
      appBar: AppBar(
        title: const Text('Appointment Overview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () async {
              await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) => const AdminAppointmentSchedulerForm(),
                ),
              );
              // TODO: Refresh appointments list
            },
            tooltip: 'Schedule Appointment',
          ),
        ],
      ),
      body: appointments.isEmpty
          ? EmptyState(
              icon: Icons.calendar_today_outlined,
              title: 'No Appointments',
              message: 'No appointments found in the system',
            )
          : ListView.builder(
              itemCount: appointments.length,
              itemBuilder: (context, index) {
                final appointment = appointments[index];
                return CardRow(
                  label:
                      '${appointment['clientName'] ?? 'Client'} - ${appointment['attorneyName'] ?? 'Attorney'}',
                  value:
                      '${appointment['date'] ?? 'Date'} at ${appointment['time'] ?? 'Time'}',
                  icon: Icons.calendar_today_outlined,
                  onTap: () {
                    // TODO: Navigate to appointment details
                  },
                );
              },
            ),
    );
  }
}
