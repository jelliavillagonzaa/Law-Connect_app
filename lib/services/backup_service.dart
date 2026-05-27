import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Pending backup rows + total restored count (same source as the admin Backup UI).
class BackupUiSnapshot {
  const BackupUiSnapshot({
    required this.pending,
    required this.restoredTotal,
  });

  final List<Map<String, dynamic>> pending;
  final int restoredTotal;
}

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

  /// Saves a snapshot to [backups] before the source document is removed.
  /// Always runs for admins so deleted users, staff applications, etc. can be recovered.
  Future<void> backupBeforeDelete({
    required String collection,
    required String documentId,
    required Map<String, dynamic> data,
    String? deletedBy,
  }) async {
    try {
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

  static Map<String, dynamic> _payloadMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  static int _deletedAtCompare(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ta = a['deletedAt'] as Timestamp?;
    final tb = b['deletedAt'] as Timestamp?;
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return tb.toDate().compareTo(ta.toDate());
  }

  /// Full [backups] listen for admins: pending = anything where [restored] is not
  /// strictly `true` (covers missing field, null, or legacy types). Matches stats.
  Stream<BackupUiSnapshot> watchBackupUi() {
    return _firestore.collection('backups').snapshots().map((snapshot) {
      final pending = <Map<String, dynamic>>[];
      var restoredTotal = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final r = data['restored'];
        if (r == true) {
          restoredTotal++;
          continue;
        }
        pending.add({
          'id': doc.id,
          'collection': data['collection'],
          'documentId': data['documentId'],
          'data': _payloadMap(data['data']),
          'deletedAt': data['deletedAt'],
          'deletedBy': data['deletedBy'],
          'restored': r ?? false,
        });
      }
      pending.sort(_deletedAtCompare);
      return BackupUiSnapshot(pending: pending, restoredTotal: restoredTotal);
    });
  }

  // Backup list: must use the same filter as `getBackupStats()` to avoid
  // showing a different count in the UI.
  //
  // Important: we intentionally do NOT use `orderBy('deletedAt')` because
  // documents missing `deletedAt` can be excluded by ordered queries.
  Stream<List<Map<String, dynamic>>> getAllBackups() {
    return _firestore
        .collection('backups')
        .where('restored', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs.map((doc) {
            final data = doc.data();
            return <String, dynamic>{
              'id': doc.id,
              'collection': data['collection'],
              'documentId': data['documentId'],
              'data': data['data'],
              'deletedAt': data['deletedAt'],
              'deletedBy': data['deletedBy'],
              'restored': data['restored'] ?? false,
            };
          }).toList();

          // Newest first; missing `deletedAt` goes last.
          items.sort((a, b) {
            final ta = a['deletedAt'] as Timestamp?;
            final tb = b['deletedAt'] as Timestamp?;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.toDate().compareTo(ta.toDate());
          });

          return items;
        });
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
        return {
          'success': false,
          'message': 'This item was already recovered',
        };
      }

      final collection = backupData['collection'] as String;
      final documentId = backupData['documentId'] as String;
      final data = Map<String, dynamic>.from(
        backupData['data'] as Map<String, dynamic>,
      );

      if (collection == 'cases') {
        data['isArchived'] = false;
        data.remove('archivedAt');
        data.remove('archivedBy');
        data['updatedAt'] = FieldValue.serverTimestamp();
      }

      // Restore the document
      await _firestore.collection(collection).doc(documentId).set(data, SetOptions(merge: true));

      // Mark backup as restored
      await _firestore.collection('backups').doc(backupId).update({
        'restored': true,
        'restoredAt': FieldValue.serverTimestamp(),
        'restoredBy': _auth.currentUser?.uid,
      });

      return {'success': true, 'message': 'Item recovered successfully'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to recover: $e'};
    }
  }

  /// Removes the backup snapshot document only. Does not touch the original
  /// collection (that doc should already be gone). Cannot be undone.
  Future<Map<String, dynamic>> permanentlyDeleteBackup(String backupId) async {
    try {
      final ref = _firestore.collection('backups').doc(backupId);
      final snap = await ref.get();
      if (!snap.exists) {
        return {'success': false, 'message': 'Backup not found'};
      }
      final backupData = snap.data()!;
      if (backupData['restored'] == true) {
        return {
          'success': false,
          'message': 'This backup entry was already marked restored',
        };
      }
      await ref.delete();
      return {'success': true, 'message': 'Backup permanently removed'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete backup: $e'};
    }
  }

  // Restore all deleted items
  Future<Map<String, dynamic>> restoreAllBackups() async {
    try {
      final backupsSnapshot = await _firestore.collection('backups').get();

      int restoredCount = 0;
      int failedCount = 0;

      for (var backupDoc in backupsSnapshot.docs) {
        final r = backupDoc.data()['restored'];
        if (r == true) continue;
        try {
          final backupData = backupDoc.data();
          final collection = backupData['collection'] as String;
          final documentId = backupData['documentId'] as String;
          final data = Map<String, dynamic>.from(
            backupData['data'] as Map<String, dynamic>,
          );

          if (collection == 'cases') {
            data['isArchived'] = false;
            data.remove('archivedAt');
            data.remove('archivedBy');
            data['updatedAt'] = FieldValue.serverTimestamp();
          }

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
        'message':
            'Recovered $restoredCount items${failedCount > 0 ? ', $failedCount failed' : ''}',
        'restoredCount': restoredCount,
        'failedCount': failedCount,
      };
    } catch (e) {
      return {'success': false, 'message': 'Failed to recover all: $e'};
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

