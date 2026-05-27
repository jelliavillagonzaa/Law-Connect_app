import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';

class CaseListScreen extends StatelessWidget {
  const CaseListScreen({super.key});

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return AppTheme.warning;
      case 'accepted':
        return AppTheme.success;
      case 'in_progress':
        return AppTheme.navy;
      case 'completed':
        return AppTheme.success;
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    // TODO: Fetch cases from Firestore
    final cases = <Map<String, dynamic>>[]; // Placeholder

    return Scaffold(
      backgroundColor: AppTheme.lightBackground,
      appBar: AppBar(
        title: const Text('Cases'),
      ),
      body: cases.isEmpty
          ? EmptyState(
              icon: Icons.folder_outlined,
              title: 'No Cases',
              message: 'You don\'t have any cases assigned yet',
            )
          : ListView.builder(
              itemCount: cases.length,
              itemBuilder: (context, index) {
                final caseData = cases[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _getStatusColor(caseData['status'] ?? 'pending')
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.folder_outlined,
                        color: _getStatusColor(caseData['status'] ?? 'pending'),
                      ),
                    ),
                    title: Text(
                      caseData['title'] ?? 'Case Title',
                      style: AppTheme.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          'Client: ${caseData['clientName'] ?? 'Unknown'}',
                          style: AppTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getStatusColor(
                              caseData['status'] ?? 'pending',
                            ).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            (caseData['status'] ?? 'pending').toUpperCase(),
                            style: AppTheme.caption.copyWith(
                              color: _getStatusColor(
                                caseData['status'] ?? 'pending',
                              ),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: AppTheme.textSecondary,
                    ),
                    onTap: () {
                      // TODO: Navigate to case details
                    },
                  ),
                );
              },
            ),
    );
  }
}

