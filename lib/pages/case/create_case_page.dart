import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../screens/attorney/attorney_create_case_screen.dart';
import '../../screens/staff/staff_create_case_draft_screen.dart';
import '../../screens/client/send_request_screen.dart';
import '../../theme/app_theme.dart';

/// Legacy entry point for case creation.
/// Matches the web process by routing according to user role:
/// - Attorneys: [AttorneyCreateCaseScreen] (full case creation with client directory, signature, and staff assignment)
/// - Staff: [StaffCreateCaseDraftScreen] (case draft under review)
/// - Clients: [SendRequestScreen] (clients send requests to attorneys, who then create the case)
class CreateCasePage extends StatefulWidget {
  const CreateCasePage({super.key});

  @override
  State<CreateCasePage> createState() => _CreateCasePageState();
}

class _CreateCasePageState extends State<CreateCasePage> {
  String? _role;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _resolveRole();
  }

  Future<void> _resolveRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final role = (doc.data()?['role'] as String? ?? 'client').toLowerCase().trim();
      if (mounted) {
        setState(() {
          _role = role;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading spinner while fetching user role
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.lightBackground,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // If role not determined (e.g. Firestore error), show fallback
    if (_role == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Create Case'),
          backgroundColor: AppTheme.royalBlue,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load your profile. Please try again.'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() => _isLoading = true);
                  _resolveRole();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Each destination screen already contains its own Scaffold + AppBar.
    // Do NOT wrap them in another Scaffold.
    if (_role == 'attorney' || _role == 'admin') {
      return const AttorneyCreateCaseScreen();
    } else if (_role == 'staff') {
      return const StaffCreateCaseDraftScreen();
    } else {
      // Clients send a request to their attorney (mirrors the web flow)
      return const SendRequestScreen();
    }
  }
}


