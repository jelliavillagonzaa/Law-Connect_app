import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _minPasswordLengthController =
      TextEditingController(text: '8');
  final TextEditingController _maxLoginAttemptsController =
      TextEditingController(text: '5');
  bool _isLoading = false;
  bool _isSaving = false;
  bool _requireUppercase = true;
  bool _requireLowercase = true;
  bool _requireNumbers = true;
  bool _requireSpecialChars = false;
  bool _enableTwoFactor = false;
  bool _autoBackup = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _minPasswordLengthController.dispose();
    _maxLoginAttemptsController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final doc = await _firestore
          .collection('system_settings')
          .doc('security')
          .get();
      if (doc.exists && mounted) {
        final data = doc.data();
        setState(() {
          _minPasswordLengthController.text = (data?['minPasswordLength'] ?? 8)
              .toString();
          _maxLoginAttemptsController.text = (data?['maxLoginAttempts'] ?? 5)
              .toString();
          _requireUppercase = data?['requireUppercase'] ?? true;
          _requireLowercase = data?['requireLowercase'] ?? true;
          _requireNumbers = data?['requireNumbers'] ?? true;
          _requireSpecialChars = data?['requireSpecialChars'] ?? false;
          _enableTwoFactor = data?['enableTwoFactor'] ?? false;
          _autoBackup = data?['autoBackup'] ?? true;
        });
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          'Failed to load settings: $e',
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

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final minLength = int.tryParse(_minPasswordLengthController.text) ?? 8;
      final maxAttempts = int.tryParse(_maxLoginAttemptsController.text) ?? 5;

      await _firestore.collection('system_settings').doc('security').set({
        'minPasswordLength': minLength,
        'maxLoginAttempts': maxAttempts,
        'requireUppercase': _requireUppercase,
        'requireLowercase': _requireLowercase,
        'requireNumbers': _requireNumbers,
        'requireSpecialChars': _requireSpecialChars,
        'enableTwoFactor': _enableTwoFactor,
        'autoBackup': _autoBackup,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        Get.snackbar(
          'Success',
          'Security settings saved successfully',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          'Failed to save settings: $e',
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
          'Security Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
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
                  // Password Policy Section
                  _buildSectionCard(
                    title: 'Password Policy',
                    children: [
                      _buildTextFieldCard(
                        label: 'Minimum Password Length',
                        controller: _minPasswordLengthController,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      _buildToggleCard(
                        title: 'Require Uppercase',
                        subtitle: 'Password must contain uppercase letters',
                        value: _requireUppercase,
                        onChanged: (value) =>
                            setState(() => _requireUppercase = value),
                      ),
                      const SizedBox(height: 12),
                      _buildToggleCard(
                        title: 'Require Lowercase',
                        subtitle: 'Password must contain lowercase letters',
                        value: _requireLowercase,
                        onChanged: (value) =>
                            setState(() => _requireLowercase = value),
                      ),
                      const SizedBox(height: 12),
                      _buildToggleCard(
                        title: 'Require Numbers',
                        subtitle: 'Password must contain numbers',
                        value: _requireNumbers,
                        onChanged: (value) =>
                            setState(() => _requireNumbers = value),
                      ),
                      const SizedBox(height: 12),
                      _buildToggleCard(
                        title: 'Require Special Characters',
                        subtitle: 'Password must contain special characters',
                        value: _requireSpecialChars,
                        onChanged: (value) =>
                            setState(() => _requireSpecialChars = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Login Security Section
                  _buildSectionCard(
                    title: 'Login Security',
                    children: [
                      _buildTextFieldCard(
                        label: 'Max Login Attempts',
                        controller: _maxLoginAttemptsController,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      _buildToggleCard(
                        title: 'Enable Two-Factor Authentication',
                        subtitle: 'Require 2FA for admin accounts',
                        value: _enableTwoFactor,
                        onChanged: (value) =>
                            setState(() => _enableTwoFactor = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Backup Section
                  _buildSectionCard(
                    title: 'Backup Settings',
                    children: [
                      _buildToggleCard(
                        title: 'Automatic Backup',
                        subtitle: 'Automatically backup system data',
                        value: _autoBackup,
                        onChanged: (value) =>
                            setState(() => _autoBackup = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.deepNavy,
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
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
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

  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
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
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextFieldCard({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF1C1C1C),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: AppTheme.deepNavy,
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            style: TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleCard({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1C1C1C),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: const Color(0xFF6D6D6D),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppTheme.deepNavy,
          ),
        ],
      ),
    );
  }
}
