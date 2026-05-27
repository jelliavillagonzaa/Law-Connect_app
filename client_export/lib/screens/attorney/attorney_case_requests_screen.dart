import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/attorney/case_requests_widget.dart';
import '../../theme/app_theme.dart';
import 'attorney_create_case_screen.dart';

class AttorneyCaseRequestsScreen extends StatelessWidget {
  /// When true, renders without [Scaffold] (used inside [AttorneyDashboard] tabs).
  final bool embedded;
  final String? attorneyId;

  const AttorneyCaseRequestsScreen({
    super.key,
    this.embedded = false,
    this.attorneyId,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = attorneyId ?? user?.uid;
    if (uid == null || uid.isEmpty) {
      const body = Center(child: Text('Please log in to view case requests'));
      if (embedded) return body;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Create Case'),
          backgroundColor: AppTheme.royalBlue,
          foregroundColor: Colors.white,
        ),
        body: body,
      );
    }

    final content = CaseRequestsWidget(
      attorneyId: uid,
      isMobile: MediaQuery.of(context).size.width < 800,
    );

    if (embedded) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Case'),
        backgroundColor: AppTheme.royalBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create Case',
            onPressed: () => _openCreateCase(context),
          ),
        ],
      ),
      body: content,
    );
  }

  void _openCreateCase(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AttorneyCreateCaseScreen(),
      ),
    ).then((created) {
      if (created == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Case created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    });
  }
}
