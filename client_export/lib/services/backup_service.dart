import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BackupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Check if backup is enabled
  Future<bool> isBackupEnabled() async {
    try {
      final doc = await _firestore
          .collection('system_settings')
          .doc('backup_settings')
          .get();
      if (doc.exists) {
        return doc.data()?['enabled'] ?? false;
      }
      return false;
    } catch (e) {
      print('Error checking backup status: $e');
      return false;
    }
  }

  // Enable/disable backup
  Future<void> setBackupEnabled(bool enabled) async {
    try {
      await _firestore.collection('system_settings').doc('backup_settings').set({
        'enabled': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _auth.currentUser?.uid,
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error setting backup status: $e');
      rethrow;
    }
  }

  // Watch backup status
  Stream<bool> watchBackupEnabled() {
    return _firestore
        .collection('system_settings')
        .doc('backup_settings')
        .snapshots()
        .map((doc) => doc.data()?['enabled'] ?? false);
  }

  // Backup data before deletion
  Future<void> backupBeforeDelete({
    required String collection,
    required String documentId,
    required Map<String, dynamic> data,
    String? deletedBy,
  }) async {
    try {
      final isEnabled = await isBackupEnabled();
      if (!isEnabled) return;

      await _firestore.collection('backups').add({
        'collection': collection,
        'documentId': documentId,
        'data': data,
        'deletedAt': FieldValue.serverTimestamp(),
        'deletedBy': deletedBy ?? _auth.currentUser?.uid,
        'restored': false,
        'restoredAt': null,
        'restoredBy': null,
      });
    } catch (e) {
      print('Error backing up data: $e');
      // Don't throw - backup failure shouldn't prevent deletion
    }
  }

  // Get all backups
  Stream<List<Map<String, dynamic>>> getAllBackups() {
    return _firestore
        .collection('backups')
        .where('restored', isEqualTo: false)
        .orderBy('deletedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              return {
                'id': doc.id,
                'collection': data['collection'],
                'documentId': data['documentId'],
                'data': data['data'],
                'deletedAt': data['deletedAt'],
                'deletedBy': data['deletedBy'],
                'restored': data['restored'] ?? false,
              };
            }).toList());
  }

  // Restore a deleted item
  Future<Map<String, dynamic>> restoreBackup(String backupId) async {
    try {
      final backupDoc = await _firestore.collection('backups').doc(backupId).get();
      if (!backupDoc.exists) {
        return {'success': false, 'message': 'Backup not found'};
      }

      final backupData = backupDoc.data()!;
      if (backupData['restored'] == true) {
        return {'success': false, 'message': 'This item has already been restored'};
      }

      final collection = backupData['collection'] as String;
      final documentId = backupData['documentId'] as String;
      final data = backupData['data'] as Map<String, dynamic>;

      // Restore the document
      await _firestore.collection(collection).doc(documentId).set(data, SetOptions(merge: true));

      // Mark backup as restored
      await _firestore.collection('backups').doc(backupId).update({
        'restored': true,
        'restoredAt': FieldValue.serverTimestamp(),
        'restoredBy': _auth.currentUser?.uid,
      });

      return {'success': true, 'message': 'Item restored successfully'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to restore: $e'};
    }
  }

  // Restore all deleted items
  Future<Map<String, dynamic>> restoreAllBackups() async {
    try {
      final backupsSnapshot = await _firestore
          .collection('backups')
          .where('restored', isEqualTo: false)
          .get();

      int restoredCount = 0;
      int failedCount = 0;

      for (var backupDoc in backupsSnapshot.docs) {
        try {
          final backupData = backupDoc.data();
          final collection = backupData['collection'] as String;
          final documentId = backupData['documentId'] as String;
          final data = backupData['data'] as Map<String, dynamic>;

          // Restore the document
          await _firestore
              .collection(collection)
              .doc(documentId)
              .set(data, SetOptions(merge: true));

          // Mark backup as restored
          await _firestore.collection('backups').doc(backupDoc.id).update({
            'restored': true,
            'restoredAt': FieldValue.serverTimestamp(),
            'restoredBy': _auth.currentUser?.uid,
          });

          restoredCount++;
        } catch (e) {
          print('Error restoring backup ${backupDoc.id}: $e');
          failedCount++;
        }
      }

      return {
        'success': true,
        'message': 'Restored $restoredCount items${failedCount > 0 ? ', $failedCount failed' : ''}',
        'restoredCount': restoredCount,
        'failedCount': failedCount,
      };
    } catch (e) {
      return {'success': false, 'message': 'Failed to restore all: $e'};
    }
  }

  // Check if current user is admin
  Future<bool> _isCurrentUserAdmin() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) return false;

      final userData = userDoc.data();
      return userData?['role'] == 'admin';
    } catch (e) {
      print('Error checking admin status: $e');
      return false;
    }
  }

  // Get backup statistics
  Future<Map<String, dynamic>> getBackupStats() async {
    try {
      // Verify user is authenticated and is admin
      final user = _auth.currentUser;
      if (user == null) {
        print('Error getting backup stats: User not authenticated');
        return {
          'totalDeleted': 0,
          'totalRestored': 0,
          'pendingRestore': 0,
        };
      }

      // Check if user is admin
      final isAdmin = await _isCurrentUserAdmin();
      if (!isAdmin) {
        print('Error getting backup stats: User is not an admin');
        return {
          'totalDeleted': 0,
          'totalRestored': 0,
          'pendingRestore': 0,
        };
      }

      // Use get() queries instead of count() for better compatibility
      // Count queries require list permissions which might have timing issues
      final totalBackupsSnapshot = await _firestore
          .collection('backups')
          .where('restored', isEqualTo: false)
          .get();

      final restoredBackupsSnapshot = await _firestore
          .collection('backups')
          .where('restored', isEqualTo: true)
          .get();

      return {
        'totalDeleted': totalBackupsSnapshot.docs.length,
        'totalRestored': restoredBackupsSnapshot.docs.length,
        'pendingRestore': totalBackupsSnapshot.docs.length,
      };
    } catch (e) {
      print('Error getting backup stats: $e');
      // Return default values on error instead of throwing
      return {
        'totalDeleted': 0,
        'totalRestored': 0,
        'pendingRestore': 0,
      };
    }
  }

  // Delete old restored backups (cleanup)
  Future<void> cleanupOldBackups({int daysOld = 30}) async {
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
      final cutoffTimestamp = Timestamp.fromDate(cutoffDate);

      final oldBackups = await _firestore
          .collection('backups')
          .where('restored', isEqualTo: true)
          .where('restoredAt', isLessThan: cutoffTimestamp)
          .get();

      final batch = _firestore.batch();
      for (var doc in oldBackups.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      print('Error cleaning up old backups: $e');
    }
  }
}

