import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/backup_service.dart';
import '../../theme/app_theme.dart';

class BackupSettingsScreen extends StatefulWidget {
  const BackupSettingsScreen({super.key, this.inline = false});

  final bool inline;

  @override
  State<BackupSettingsScreen> createState() => _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends State<BackupSettingsScreen> {
  final BackupService _backupService = BackupService();
  bool _isRestoring = false;
  String? _deletingBackupId;

  Widget _buildMainColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInfoCard(),
        const SizedBox(height: 24),
        _buildStatsCard(),
        const SizedBox(height: 24),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _backupService.getAllBackups(),
          builder: (context, backupSnapshot) {
            if (backupSnapshot.hasError) {
              return Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Could not load backup list: ${backupSnapshot.error}',
                    style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                  ),
                ),
              );
            }
            final backups = backupSnapshot.data ?? [];
            if (backups.isEmpty) {
              return const SizedBox.shrink();
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
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
                          'Recover all',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1C1C1C),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Recover all ${backups.length} deleted item${backups.length > 1 ? 's' : ''} to their original collections.',
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
                              _isRestoring ? 'Working...' : 'Recover all',
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
                ),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
        _buildDeletedItemsList(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scroll = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _buildMainColumn(),
    );

    if (widget.inline) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Backup',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.royalBlue,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Deleted users, staff applications, and cases (removed from Archive Storage) appear here. Use Recover to restore the Firestore record, or the trash icon to remove the backup copy permanently.',
                  style: TextStyle(color: Colors.grey[700], fontSize: 14),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          Expanded(child: scroll),
        ],
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        title: const Text(
          'Backup & Recover',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: scroll,
    );
  }

  Widget _buildInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                    'Automatic backup',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1C1C1C),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'When you delete a user, staff application, or archived case, a snapshot is saved automatically. Restoring re-creates the Firestore document (Firebase Auth accounts are separate). Tap the trash icon to permanently remove a backup row.',
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
      ),
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
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _backupService.getAllBackups(),
      builder: (context, backupSnapshot) {
        if (backupSnapshot.hasError) {
          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
                  const SizedBox(height: 12),
                  Text(
                    'Could not load backups',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${backupSnapshot.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
          );
        }
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
                      'Nothing in backup',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Deleted users, staff applications, and cases (from Archive Storage) will show up here',
                      textAlign: TextAlign.center,
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
              'Deleted items (${backups.length})',
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
    } else if (collection == 'staff_applications') {
      itemName = data['name'] ?? data['email'] ?? 'Staff application';
    }

    final role = data['role'] as String?;
    final typeLine = collection == 'users' && role != null
        ? 'users · $role'
        : collection;

    final backupId = backup['id'] as String;
    final isDeletingThis = _deletingBackupId == backupId;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _deletingBackupId != null
                ? null
                : () => _confirmPermanentDelete(backupId, itemName),
            borderRadius: BorderRadius.circular(8),
            child: Tooltip(
              message: 'Permanently delete this backup',
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: isDeletingThis
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.orange.shade800,
                        ),
                      )
                    : Icon(Icons.delete_outline, color: Colors.orange.shade800),
              ),
            ),
          ),
        ),
        title: Text(itemName, style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(typeLine),
            if (deletedAt != null)
              Text(
                'Deleted: ${DateFormat('MMM dd, yyyy HH:mm').format(deletedAt.toDate())}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: _deletingBackupId != null
                  ? null
                  : () => _confirmPermanentDelete(backupId, itemName),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                side: BorderSide(color: Colors.red.shade300),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Delete permanently'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _deletingBackupId != null
                  ? null
                  : () => _restoreBackup(backupId, itemName),
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
          ],
        ),
      ),
    );
  }

  Future<void> _confirmPermanentDelete(String backupId, String itemName) async {
    final confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Delete backup forever?'),
        content: Text(
          'Remove the saved copy of "$itemName" from Backup. '
          'You will not be able to recover this item from here unless it still exists in Firestore.\n\n'
          'This does not delete live data elsewhere — only this backup snapshot.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _deletingBackupId = backupId);

    try {
      final result = await _backupService.permanentlyDeleteBackup(backupId);
      if (mounted) {
        Get.snackbar(
          result['success'] == true ? 'Deleted' : 'Error',
          result['message'] as String,
          backgroundColor:
              result['success'] == true ? Colors.green.shade700 : Colors.red,
          colorText: Colors.white,
          duration: const Duration(seconds: 3),
        );
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          'Failed to delete backup: $e',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _deletingBackupId = null);
      }
    }
  }

  Future<void> _restoreBackup(String backupId, String itemName) async {
    final confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Restore item'),
        content: Text(
          'Restore "$itemName" to its original collection? '
          'Cases return to Case Oversight.',
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
          result['success'] ? 'Recovered' : 'Error',
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
          'Failed to recover: $e',
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
          'Failed to recover all: $e',
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
