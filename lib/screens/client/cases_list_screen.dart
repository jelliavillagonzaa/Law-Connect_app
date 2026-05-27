import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/case_service.dart';
import '../../models/case_model.dart';
import '../../pages/case/case_detail_page.dart';

class CasesListScreen extends StatelessWidget {
  const CasesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: AppTheme.lightBackground,
        appBar: AppBar(
          backgroundColor: AppTheme.navy,
          title: const Text(
            'Cases',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          elevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: const Center(
          child: Text('Please log in to view your cases'),
        ),
      );
    }

    final caseService = CaseService();

    return Scaffold(
      backgroundColor: AppTheme.lightBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.navy,
        title: const Text(
          'My Cases',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<List<CaseModel>>(
        stream: caseService.getCasesForUser(user.uid, 'client'),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading cases: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final cases = snapshot.data ?? [];

          if (cases.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.folder_open,
                    size: 64,
                    color: AppTheme.textSecondary.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No cases yet',
                    style: AppTheme.heading4.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your attorney will create cases for you.\nYou will be notified when a new case is created.',
                    style: AppTheme.bodyMedium.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: cases.length,
            itemBuilder: (context, index) {
              return _buildCaseCard(context, cases[index]);
            },
          );
        },
      ),
    );
  }

  Widget _buildCaseCard(BuildContext context, CaseModel caseModel) {
    Color statusColor;
    Color statusBgColor;
    switch (caseModel.status.toLowerCase()) {
      case 'active':
      case 'in_progress':
      case 'open':
      case 'ongoing':
        statusColor = Colors.white;
        statusBgColor = const Color(0xFF4A90E2);
        break;
      case 'pending':
      case 'under_review':
        statusColor = Colors.white;
        statusBgColor = const Color(0xFFFF9500);
        break;
      case 'completed':
      case 'closed':
        statusColor = Colors.white;
        statusBgColor = const Color(0xFFFF6B6B);
        break;
      default:
        statusColor = Colors.white;
        statusBgColor = AppTheme.textSecondary;
    }

    // Get hearing date from progress or case data
    String? hearingDateStr;
    if (caseModel.progress != null) {
      final hearingDate = caseModel.progress!['hearingDate'];
      if (hearingDate != null) {
        try {
          final date = hearingDate is DateTime
              ? hearingDate
              : DateTime.parse(hearingDate.toString());
          hearingDateStr = DateFormat('MMM dd, yyyy').format(date);
        } catch (e) {
          // Ignore parsing errors
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CaseDetailPage(caseId: caseModel.id),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Blue briefcase icon on left
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.navy.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.folder_copy_rounded,
                      color: AppTheme.navy,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Case info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          caseModel.caseTitle,
                          style: AppTheme.heading4.copyWith(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          caseModel.caseType,
                          style: AppTheme.bodyMedium.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusBgColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      caseModel.status.length > 10
                          ? caseModel.status.substring(0, 10)
                          : caseModel.status,
                      style: AppTheme.caption.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Arrow icon
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: AppTheme.textSecondary,
                    size: 16,
                  ),
                ],
              ),
              if (hearingDateStr != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Hearing: $hearingDateStr',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
