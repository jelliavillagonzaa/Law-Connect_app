import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../services/admin_service.dart';
import '../../theme/app_theme.dart';
import 'platform_policies_screen.dart';
import 'notification_settings_screen.dart';
import 'email_templates_screen.dart';
import 'security_settings_screen.dart';
import 'backup_settings_screen.dart';
import 'archive_storage_screen.dart';

class SystemSettingsScreen extends StatefulWidget {
  final bool inline;
  const SystemSettingsScreen({super.key, this.inline = false});

  @override
  State<SystemSettingsScreen> createState() => _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends State<SystemSettingsScreen> {
  final AdminService _adminService = AdminService();
  bool _maintenanceMode = false;

  @override
  void initState() {
    super.initState();
    _loadMaintenanceMode();
  }

  Future<void> _loadMaintenanceMode() async {
    try {
      final mode = await _adminService.getMaintenanceMode();
      if (mounted) {
        setState(() => _maintenanceMode = mode);
      }
    } catch (e) {
      // Handle error silently
    }
  }

  Widget _buildBody() {
    return StreamBuilder<bool>(
      stream: _adminService.watchMaintenanceMode(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _maintenanceMode = snapshot.data!;
        }
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.of(context).size.width > 600 ? 24 : 16,
            vertical: 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Maintenance Mode Card
              _buildMaintenanceModeCard(),

              const SizedBox(height: 24),

              // Settings Tiles
              _buildSettingTile(
                icon: Icons.policy_outlined,
                iconColor: AppTheme.royalBlue,
                title: 'Platform Policies',
                subtitle: 'Manage terms & conditions and platform rules',
                onTap: () {
                  Get.to(() => const PlatformPoliciesScreen());
                },
              ),

              const SizedBox(height: 12),

              _buildSettingTile(
                icon: Icons.notifications_outlined,
                iconColor: const Color(0xFF2D7A4F),
                title: 'Notification Settings',
                subtitle: 'Configure system notifications and alerts',
                onTap: () {
                  Get.to(() => const NotificationSettingsScreen());
                },
              ),

              const SizedBox(height: 12),

              _buildSettingTile(
                icon: Icons.email_outlined,
                iconColor: const Color(0xFFB8860B),
                title: 'Email Templates',
                subtitle: 'Manage and customize email templates',
                onTap: () {
                  Get.to(() => const EmailTemplatesScreen());
                },
              ),

              const SizedBox(height: 12),

              _buildSettingTile(
                icon: Icons.security_outlined,
                iconColor: AppTheme.deepNavy,
                title: 'Security Settings',
                subtitle: 'Password policies and backup settings',
                onTap: () {
                  Get.to(() => const SecuritySettingsScreen());
                },
              ),

              const SizedBox(height: 12),

              _buildSettingTile(
                icon: Icons.archive_outlined,
                iconColor: const Color(0xFF5C6BC0),
                title: 'Archive Storage',
                subtitle:
                    'View archived cases — restore to Case Oversight or move to Backup',
                onTap: () {
                  Get.to(
                    () => ArchiveStorageScreen(
                      onOpenBackup: () =>
                          Get.to(() => const BackupSettingsScreen()),
                    ),
                  );
                },
              ),

              const SizedBox(height: 12),

              _buildSettingTile(
                icon: Icons.backup_outlined,
                iconColor: const Color(0xFF9C27B0),
                title: 'Backup & Restore',
                subtitle: 'Manage backups and restore deleted items',
                onTap: () {
                  Get.to(() => const BackupSettingsScreen());
                },
              ),

              const SizedBox(height: 32),

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();

    if (widget.inline) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              'System Settings',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        title: Text(
          'System Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: body,
    );
  }

  Widget _buildMaintenanceModeCard() {
    return Container(
      padding: const EdgeInsets.all(24),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFB8860B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.build_outlined,
                  color: Color(0xFFB8860B),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Maintenance Mode',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1C1C1C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'When enabled, only admins can login. All other users will be blocked.',
                      style: TextStyle(
                        fontSize: 13,
                        color: const Color(0xFF6D6D6D),
                      ),
                    ),
                    if (_maintenanceMode) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Maintenance mode is active. Only admins can login.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _maintenanceMode
                      ? Colors.orange.withOpacity(0.1)
                      : Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _maintenanceMode ? Colors.orange : Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _maintenanceMode ? 'Enabled' : 'Disabled',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _maintenanceMode ? Colors.orange : Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _maintenanceMode,
                onChanged: (value) async {
                  try {
                    await _adminService.setMaintenanceMode(value);
                    if (mounted) {
                      Get.snackbar(
                        'Success',
                        'Maintenance mode ${value ? 'enabled' : 'disabled'}',
                        backgroundColor: Colors.green,
                        colorText: Colors.white,
                        duration: const Duration(seconds: 2),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      Get.snackbar(
                        'Error',
                        'Failed to update maintenance mode: $e',
                        backgroundColor: Colors.red,
                        colorText: Colors.white,
                      );
                    }
                  }
                },
                activeColor: Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
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
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1C1C1C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: const Color(0xFF6D6D6D),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: const Color(0xFF6D6D6D).withOpacity(0.5),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
