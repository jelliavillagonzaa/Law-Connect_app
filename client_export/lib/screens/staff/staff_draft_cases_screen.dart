import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import '../../services/staff_service.dart';
import '../../services/staff_auth_service.dart';
import '../../models/case_model.dart';
import '../../theme/app_theme.dart';
import 'staff_create_case_draft_screen.dart';

class StaffDraftCasesScreen extends StatefulWidget {
  const StaffDraftCasesScreen({super.key});

  @override
  State<StaffDraftCasesScreen> createState() => _StaffDraftCasesScreenState();
}

class _StaffDraftCasesScreenState extends State<StaffDraftCasesScreen> {
  final StaffService _staffService = StaffService();
  final StaffAuthService _staffAuthService = StaffAuthService();
  String? _assignedAttorneyId;

  @override
  void initState() {
    super.initState();
    _loadAttorneyId();
  }

  Future<void> _loadAttorneyId() async {
    final staff = await _staffAuthService.getCurrentStaff();
    if (staff != null && mounted) {
      setState(() {
        _assignedAttorneyId = staff.assignedAttorneyId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Draft Cases'),
          backgroundColor: AppTheme.royalBlue,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Please log in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Draft Cases'),
        backgroundColor: AppTheme.royalBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Create Draft Case',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StaffCreateCaseDraftScreen(),
                ),
              ).then((created) {
                if (created == true) {
                  setState(() {}); // Refresh
                }
              });
            },
          ),
        ],
      ),
      body: _assignedAttorneyId == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<CaseModel>>(
              stream: _staffService.getAttorneyCases(_assignedAttorneyId!),
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
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        Text('Error: ${snapshot.error}'),
                      ],
                    ),
                  );
                }

                final allCases = snapshot.data ?? [];
                // Filter only draft cases (under_review status)
                final draftCases = allCases
                    .where((c) => c.status == 'under_review')
                    .toList();

                if (draftCases.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No draft cases',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create a draft case to get started',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const StaffCreateCaseDraftScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Create Draft Case'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.royalBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: draftCases.length,
                  itemBuilder: (context, index) {
                    final caseModel = draftCases[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.royalBlue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.description_outlined,
                            color: AppTheme.royalBlue,
                            size: 24,
                          ),
                        ),
                        title: Text(
                          caseModel.caseTitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              'Type: ${caseModel.caseType}',
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'DRAFT - Awaiting Attorney Review',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Created: ${DateFormat('MMM dd, yyyy').format(caseModel.createdAt)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.mutedText,
                              ),
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          // Navigate to case detail or show draft details
                          Get.snackbar(
                            'Draft Case',
                            'This case is awaiting attorney review',
                            backgroundColor: Colors.orange,
                            colorText: Colors.white,
                            duration: const Duration(seconds: 2),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
