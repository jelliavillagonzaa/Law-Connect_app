import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';

class PlatformPoliciesScreen extends StatefulWidget {
  const PlatformPoliciesScreen({super.key});

  @override
  State<PlatformPoliciesScreen> createState() => _PlatformPoliciesScreenState();
}

class _PlatformPoliciesScreenState extends State<PlatformPoliciesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _termsController = TextEditingController();
  final TextEditingController _privacyController = TextEditingController();
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadPolicies();
  }

  @override
  void dispose() {
    _termsController.dispose();
    _privacyController.dispose();
    super.dispose();
  }

  Future<void> _loadPolicies() async {
    setState(() => _isLoading = true);
    try {
      final doc = await _firestore.collection('system_settings').doc('platform_policies').get();
      if (doc.exists && mounted) {
        final data = doc.data();
        _termsController.text = data?['termsAndConditions'] ?? '';
        _privacyController.text = data?['privacyPolicy'] ?? '';
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          'Failed to load policies: $e',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _savePolicies() async {
    setState(() => _isSaving = true);
    try {
      await _firestore.collection('system_settings').doc('platform_policies').set({
        'termsAndConditions': _termsController.text,
        'privacyPolicy': _privacyController.text,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        Get.snackbar(
          'Success',
          'Policies saved successfully',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          'Failed to save policies: $e',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        title: Text(
          'Platform Policies',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width > 600 ? 24 : 16,
                vertical: 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Terms and Conditions Card
                  _buildPolicyCard(
                    title: 'Terms & Conditions',
                    controller: _termsController,
                    hint: 'Enter terms and conditions...',
                  ),
                  const SizedBox(height: 16),
                  // Privacy Policy Card
                  _buildPolicyCard(
                    title: 'Privacy Policy',
                    controller: _privacyController,
                    hint: 'Enter privacy policy...',
                  ),
                  const SizedBox(height: 24),
                  // Save Button
                  ElevatedButton(
                    onPressed: _isSaving ? null : _savePolicies,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.royalBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            'Save Changes',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildPolicyCard({
    required String title,
    required TextEditingController controller,
    required String hint,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1C1C1C),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            maxLines: 15,
            decoration: InputDecoration(
              hintText: hint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.royalBlue, width: 2),
              ),
              filled: true,
              fillColor: const Color(0xFFF9F9F9),
            ),
            style: TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }
}

