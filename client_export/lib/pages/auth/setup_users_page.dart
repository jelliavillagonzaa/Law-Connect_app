import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/user_setup_service.dart';
import '../../widgets/common/app_button.dart';
import '../../theme/app_theme.dart';

/// Page to help set up admin and attorney users in Firestore
/// This should be used after creating users in Firebase Auth Console
class SetupUsersPage extends StatefulWidget {
  const SetupUsersPage({super.key});

  @override
  State<SetupUsersPage> createState() => _SetupUsersPageState();
}

class _SetupUsersPageState extends State<SetupUsersPage> {
  final UserSetupService _setupService = UserSetupService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isSettingUpAdmin = false;
  bool _isSettingUpAttorney = false;
  String _statusMessage = '';

  Future<void> _setupAdmin() async {
    setState(() {
      _isSettingUpAdmin = true;
      _statusMessage = 'Setting up admin user...';
    });

    try {
      // Try to sign in as admin
      final credential = await _auth.signInWithEmailAndPassword(
        email: 'admin@gmail.com',
        password: 'admin123',
      );

      if (credential.user != null) {
        await _setupService.setupAdminUser(
          'admin@gmail.com',
          credential.user!.uid,
        );
        setState(() {
          _statusMessage = '✅ Admin user setup complete!';
        });
        Get.snackbar(
          'Success',
          'Admin user setup complete!',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
        await _auth.signOut();
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Failed to setup admin user';
      if (e.code == 'user-not-found') {
        message = 'Admin user not found in Firebase Auth. Please create admin@gmail.com in Firebase Console first.';
      } else if (e.code == 'wrong-password') {
        message = 'Wrong password. Please check the password is admin123';
      } else {
        message = e.message ?? 'Failed to setup admin user';
      }
      setState(() {
        _statusMessage = '❌ $message';
      });
      Get.snackbar(
        'Error',
        message,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Error: $e';
      });
      Get.snackbar(
        'Error',
        'Failed to setup admin: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      setState(() {
        _isSettingUpAdmin = false;
      });
    }
  }

  Future<void> _setupAttorney() async {
    setState(() {
      _isSettingUpAttorney = true;
      _statusMessage = 'Setting up attorney user...';
    });

    try {
      // Try to sign in as attorney
      final credential = await _auth.signInWithEmailAndPassword(
        email: 'attorney@gmail.com',
        password: 'attorney123',
      );

      if (credential.user != null) {
        await _setupService.setupAttorneyUser(
          'attorney@gmail.com',
          credential.user!.uid,
          name: 'Attorney User',
          specialization: ['General Law', 'Criminal Defense'],
        );
        setState(() {
          _statusMessage = '✅ Attorney user setup complete!';
        });
        Get.snackbar(
          'Success',
          'Attorney user setup complete!',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
        await _auth.signOut();
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Failed to setup attorney user';
      if (e.code == 'user-not-found') {
        message = 'Attorney user not found in Firebase Auth. Please create attorney@gmail.com in Firebase Console first.';
      } else if (e.code == 'wrong-password') {
        message = 'Wrong password. Please check the password is attorney123';
      } else {
        message = e.message ?? 'Failed to setup attorney user';
      }
      setState(() {
        _statusMessage = '❌ $message';
      });
      Get.snackbar(
        'Error',
        message,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Error: $e';
      });
      Get.snackbar(
        'Error',
        'Failed to setup attorney: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      setState(() {
        _isSettingUpAttorney = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Test Users'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              const Text(
                'Setup Admin & Attorney Users',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This will create Firestore documents for admin and attorney users.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.mutedText,
                ),
              ),
              const SizedBox(height: 32),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Admin User',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Email: admin@gmail.com'),
                      const Text('Password: admin123'),
                      const SizedBox(height: 16),
                      AppButton(
                        text: 'Setup Admin User',
                        onPressed: _setupAdmin,
                        isLoading: _isSettingUpAdmin,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Attorney User',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Email: attorney@gmail.com'),
                      const Text('Password: attorney123'),
                      const SizedBox(height: 16),
                      AppButton(
                        text: 'Setup Attorney User',
                        onPressed: _setupAttorney,
                        isLoading: _isSettingUpAttorney,
                      ),
                    ],
                  ),
                ),
              ),
              if (_statusMessage.isNotEmpty) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _statusMessage.contains('✅')
                        ? Colors.green[100]
                        : Colors.red[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      color: _statusMessage.contains('✅')
                          ? Colors.green[900]
                          : Colors.red[900],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'Instructions:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '1. Make sure admin@gmail.com and attorney@gmail.com exist in Firebase Auth Console\n'
                '2. Click the setup buttons above to create their Firestore documents\n'
                '3. After setup, you can login with these credentials',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

