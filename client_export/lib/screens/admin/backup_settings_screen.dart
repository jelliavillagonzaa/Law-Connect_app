import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/backup_service.dart';
import '../../theme/app_theme.dart';

class BackupSettingsScreen extends StatefulWidget {
  const BackupSettingsScreen({super.key});

  @override
  State<BackupSettingsScreen> createState() => _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends State<BackupSettingsScreen> {
  final BackupService _backupService = BackupService();
  bool _isLoading = false;
  bool _isRestoring = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        title: const Text(
          'Backup & Restore',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Backup Enable/Disable Card
            _buildBackupToggleCard(),

            const SizedBox(height: 24),

            // Statistics Card
            _buildStatsCard(),

            const SizedBox(height: 24),

            // Restore All Button
            StreamBuilder<bool>(
              stream: _backupService.watchBackupEnabled(),
              builder: (context, snapshot) {
                final isEnabled = snapshot.data ?? false;
                if (!isEnabled) {
                  return const SizedBox.shrink();
                }

                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _backupService.getAllBackups(),
                  builder: (context, backupSnapshot) {
                    final backups = backupSnapshot.data ?? [];
                    if (backups.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Restore All Deleted Items',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1C1C1C),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Restore all ${backups.length} deleted item${backups.length > 1 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: 14,
                                color: const Color(0xFF6D6D6D),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _isRestoring
                                    ? null
                                    : () => _restoreAllBackups(),
                                icon: _isRestoring
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : const Icon(Icons.restore),
                                label: Text(
                                  _isRestoring ? 'Restoring...' : 'Restore All',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.royalBlue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 24),

            // Deleted Items List
            _buildDeletedItemsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupToggleCard() {
    return StreamBuilder<bool>(
      stream: _backupService.watchBackupEnabled(),
      builder: (context, snapshot) {
        final isEnabled = snapshot.data ?? false;

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.royalBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.backup_outlined,
                        color: AppTheme.royalBlue,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Automatic Backup',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1C1C1C),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'When enabled, all deleted items will be backed up and can be restored later.',
                            style: TextStyle(
                              fontSize: 13,
                              color: const Color(0xFF6D6D6D),
                            ),
                          ),
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
                        color: isEnabled
                            ? Colors.green.withOpacity(0.1)
                            : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isEnabled ? Colors.green : Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isEnabled ? 'Enabled' : 'Disabled',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isEnabled ? Colors.green : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: isEnabled,
                      onChanged: (value) async {
                        setState(() => _isLoading = true);
                        try {
                          await _backupService.setBackupEnabled(value);
                          if (mounted) {
                            Get.snackbar(
                              'Success',
                              'Backup ${value ? 'enabled' : 'disabled'}',
                              backgroundColor: Colors.green,
                              colorText: Colors.white,
                              duration: const Duration(seconds: 2),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            Get.snackbar(
                              'Error',
                              'Failed to update backup settings: $e',
                              backgroundColor: Colors.red,
                              colorText: Colors.white,
                            );
                          }
                        } finally {
                          if (mounted) {
                            setState(() => _isLoading = false);
                          }
                        }
                      },
                      activeColor: AppTheme.royalBlue,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatsCard() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _backupService.getBackupStats(),
      builder: (context, snapshot) {
        final stats =
            snapshot.data ??
            {'totalDeleted': 0, 'totalRestored': 0, 'pendingRestore': 0};

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  'Deleted Items',
                  stats['pendingRestore'].toString(),
                  Colors.orange,
                ),
                Container(width: 1, height: 40, color: Colors.grey[300]),
                _buildStatItem(
                  'Restored Items',
                  stats['totalRestored'].toString(),
                  Colors.green,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: const Color(0xFF6D6D6D)),
        ),
      ],
    );
  }

  Widget _buildDeletedItemsList() {
    return StreamBuilder<bool>(
      stream: _backupService.watchBackupEnabled(),
      builder: (context, snapshot) {
        final isEnabled = snapshot.data ?? false;
        if (!isEnabled) {
          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.info_outline, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'Enable backup to see deleted items',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _backupService.getAllBackups(),
          builder: (context, backupSnapshot) {
            if (backupSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final backups = backupSnapshot.data ?? [];

            if (backups.isEmpty) {
              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 48,
                          color: Colors.green[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No deleted items',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'All items are safe',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deleted Items (${backups.length})',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1C1C1C),
                  ),
                ),
                const SizedBox(height: 12),
                ...backups.map((backup) => _buildBackupItem(backup)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBackupItem(Map<String, dynamic> backup) {
    final collection = backup['collection'] as String? ?? 'Unknown';
    final deletedAt = backup['deletedAt'] as Timestamp?;
    final data = backup['data'] as Map<String, dynamic>? ?? {};

    String itemName = 'Unknown Item';
    if (collection == 'users') {
      itemName = data['name'] ?? data['fullName'] ?? data['email'] ?? 'User';
    } else if (collection == 'cases') {
      itemName = data['caseTitle'] ?? 'Case';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.delete_outline, color: Colors.orange),
        ),
        title: Text(itemName, style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Collection: $collection'),
            if (deletedAt != null)
              Text(
                'Deleted: ${DateFormat('MMM dd, yyyy HH:mm').format(deletedAt.toDate())}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
          ],
        ),
        trailing: ElevatedButton(
          onPressed: () => _restoreBackup(backup['id'] as String, itemName),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.royalBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('Restore'),
        ),
      ),
    );
  }

  Future<void> _restoreBackup(String backupId, String itemName) async {
    final confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Restore Item'),
        content: Text('Are you sure you want to restore "$itemName"?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.royalBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isRestoring = true);

    try {
      final result = await _backupService.restoreBackup(backupId);
      if (mounted) {
        Get.snackbar(
          result['success'] ? 'Success' : 'Error',
          result['message'] as String,
          backgroundColor: result['success'] ? Colors.green : Colors.red,
          colorText: Colors.white,
          duration: const Duration(seconds: 3),
        );
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          'Failed to restore: $e',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }

  Future<void> _restoreAllBackups() async {
    final confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Restore All Items'),
        content: const Text(
          'Are you sure you want to restore all deleted items? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.royalBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Restore All'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isRestoring = true);

    try {
      final result = await _backupService.restoreAllBackups();
      if (mounted) {
        Get.snackbar(
          result['success'] ? 'Success' : 'Error',
          result['message'] as String,
          backgroundColor: result['success'] ? Colors.green : Colors.red,
          colorText: Colors.white,
          duration: const Duration(seconds: 3),
        );
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          'Failed to restore all: $e',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }
}
