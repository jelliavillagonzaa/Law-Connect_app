import 'dart:io' show File;
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:file_picker/file_picker.dart';
import '../models/task_model.dart';
import 'local_attachment_service.dart';

class TaskService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // Removed unused _storage field
  final LocalAttachmentService _localAttachmentService = LocalAttachmentService();

  // Create task (attorney only)
  Future<Map<String, dynamic>> createTask({
    required String title,
    required String description,
    required String assignedTo, // staffId
    String? caseId,
    DateTime? dueDate,
    int? priority,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }

      // Get user role
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userRole = userDoc.data()?['role'] ?? 'attorney';

      final taskData = {
        'title': title,
        'description': description,
        'assignedTo': assignedTo,
        'attorneyId': user.uid,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': user.uid,
        'createdByRole': userRole,
      };

      if (caseId != null) taskData['caseId'] = caseId;
      if (dueDate != null) taskData['dueDate'] = Timestamp.fromDate(dueDate);
      if (priority != null) taskData['priority'] = priority;

      final docRef = await _firestore.collection('tasks').add(taskData);

      return {
        'success': true,
        'message': 'Task created successfully',
        'taskId': docRef.id,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to create task: ${e.toString()}',
      };
    }
  }

  // Get tasks assigned to a staff member
  Stream<List<TaskModel>> getStaffTasks(String staffId) {
    return _firestore
        .collection('tasks')
        .where('assignedTo', isEqualTo: staffId)
        .snapshots()
        .map((snapshot) {
          final tasks = snapshot.docs
              .map((doc) => TaskModel.fromFirestore(doc))
              .toList();
          // Sort by createdAt descending in memory
          tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return tasks;
        });
  }

  // Get tasks by status
  Stream<List<TaskModel>> getStaffTasksByStatus(String staffId, String status) {
    return _firestore
        .collection('tasks')
        .where('assignedTo', isEqualTo: staffId)
        .where('status', isEqualTo: status)
        .snapshots()
        .map((snapshot) {
          final tasks = snapshot.docs
              .map((doc) => TaskModel.fromFirestore(doc))
              .toList();
          // Sort by createdAt descending in memory
          tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return tasks;
        });
  }

  // Update task details (for attorneys to edit task information)
  Future<Map<String, dynamic>> updateTaskDetails({
    required String taskId,
    String? title,
    String? description,
    int? priority,
    DateTime? dueDate,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (title != null && title.isNotEmpty) {
        updateData['title'] = title;
      }
      if (description != null && description.isNotEmpty) {
        updateData['description'] = description;
      }
      if (priority != null) {
        updateData['priority'] = priority;
      }
      if (dueDate != null) {
        updateData['dueDate'] = Timestamp.fromDate(dueDate);
      } else if (dueDate == null && title == null && description == null && priority == null) {
        // Allow clearing due date
        updateData['dueDate'] = null;
      }

      await _firestore.collection('tasks').doc(taskId).update(updateData);

      return {
        'success': true,
        'message': 'Task details updated successfully',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to update task details: ${e.toString()}',
      };
    }
  }

  // Update task status
  Future<Map<String, dynamic>> updateTaskStatus(
    String taskId,
    String status, {
    String? notes,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (status == 'completed') {
        updateData['completedAt'] = FieldValue.serverTimestamp();
      }

      if (notes != null && notes.isNotEmpty) {
        updateData['notes'] = notes;
      }

      await _firestore.collection('tasks').doc(taskId).update(updateData);

      // If task is completed, create a notification for the attorney
      if (status == 'completed') {
        try {
          final taskDoc = await _firestore
              .collection('tasks')
              .doc(taskId)
              .get();
          if (taskDoc.exists) {
            final taskData = taskDoc.data()!;
            final attorneyId = taskData['attorneyId'] as String?;
            final taskTitle = taskData['title'] as String? ?? 'Task';

            if (attorneyId != null) {
              // Create notification for attorney
              await _firestore.collection('notifications').add({
                'userId': attorneyId,
                'type': 'task_completed',
                'title': 'Task Completed',
                'message': 'Task "$taskTitle" has been completed by staff',
                'taskId': taskId,
                'read': false,
                'createdAt': FieldValue.serverTimestamp(),
              });
            }
          }
        } catch (e) {
          // Don't fail the task update if notification fails
          if (kDebugMode) {
            print('Failed to create notification: $e');
          }
        }
      }

      return {'success': true, 'message': 'Task updated successfully'};
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to update task: ${e.toString()}',
      };
    }
  }

  // Update task priority
  Future<Map<String, dynamic>> updateTaskPriority(
    String taskId,
    int priority,
  ) async {
    try {
      await _firestore.collection('tasks').doc(taskId).update({
        'priority': priority,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return {'success': true, 'message': 'Task priority updated'};
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to update priority: ${e.toString()}',
      };
    }
  }

  // Get single task
  Future<TaskModel?> getTask(String taskId) async {
    try {
      final doc = await _firestore.collection('tasks').doc(taskId).get();
      if (!doc.exists) return null;
      return TaskModel.fromFirestore(doc);
    } catch (e) {
      return null;
    }
  }

  // Get tasks for attorney (to see all tasks they assigned)
  Stream<List<TaskModel>> getAttorneyTasks(String attorneyId) {
    return _firestore
        .collection('tasks')
        .where('attorneyId', isEqualTo: attorneyId)
        .snapshots()
        .map((snapshot) {
          final tasks = snapshot.docs
              .map((doc) => TaskModel.fromFirestore(doc))
              .toList();
          // Sort by createdAt descending in memory
          tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return tasks;
        });
  }

  // Get tasks for attorney filtered by status
  Stream<List<TaskModel>> getAttorneyTasksByStatus(
      String attorneyId, String status) {
    return _firestore
        .collection('tasks')
        .where('attorneyId', isEqualTo: attorneyId)
        .where('status', isEqualTo: status)
        .snapshots()
        .map((snapshot) {
          final tasks = snapshot.docs
              .map((doc) => TaskModel.fromFirestore(doc))
              .toList();
          // Sort by createdAt descending in memory
          tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return tasks;
        });
  }

  // Add attachment to task (stored in Firestore for sharing between staff and attorney)
  Future<Map<String, dynamic>> addTaskAttachment({
    required String taskId,
    required PlatformFile file,
  }) async {
    try {
      // Get file bytes
      Uint8List fileBytes;
      if (kIsWeb) {
        if (file.bytes == null) {
          return {'success': false, 'message': 'File bytes are null'};
        }
        if (file.bytes!.isEmpty) {
          return {'success': false, 'message': 'File is empty'};
        }
        fileBytes = file.bytes!;
      } else {
        if (file.path == null || file.path!.isEmpty) {
          return {'success': false, 'message': 'File path is null or empty'};
        }
        final fileObj = File(file.path!);
        if (!await fileObj.exists()) {
          return {'success': false, 'message': 'File does not exist at path: ${file.path}'};
        }
        fileBytes = await fileObj.readAsBytes();
        if (fileBytes.isEmpty) {
          return {'success': false, 'message': 'File is empty'};
        }
      }

      // Check file size (limit to 5MB for Firestore storage)
      const maxFileSize = 5 * 1024 * 1024; // 5MB
      if (fileBytes.length > maxFileSize) {
        return {
          'success': false,
          'message': 'File too large. Maximum size is 5MB for attachments. Please use a smaller file.',
        };
      }

      // Generate unique attachment ID
      final fileName = file.name.isNotEmpty ? file.name : 'attachment';
      final attachmentId = LocalAttachmentService.generateAttachmentId(fileName);

      // Convert to base64 for Firestore storage
      final base64File = base64Encode(fileBytes);

      // Get current user
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }

      // Verify task exists
      final taskDoc = await _firestore.collection('tasks').doc(taskId).get();
      if (!taskDoc.exists) {
        return {'success': false, 'message': 'Task not found'};
      }

      // Store attachment in Firestore subcollection (accessible by both staff and attorney)
      final attachmentData = {
        'taskId': taskId,
        'fileName': fileName,
        'fileExtension': file.extension ?? '',
        'fileSize': fileBytes.length,
        'fileData': base64File, // Base64 encoded file
        'uploadedBy': user.uid,
        'uploadedAt': FieldValue.serverTimestamp(),
        'attachmentId': attachmentId,
      };

      await _firestore
          .collection('tasks')
          .doc(taskId)
          .collection('attachments')
          .doc(attachmentId)
          .set(attachmentData);

      // Also save to local storage as cache for fast access
      try {
        await _localAttachmentService.saveAttachment(
          attachmentId: attachmentId,
          fileBytes: fileBytes,
          fileName: fileName,
          fileExtension: file.extension,
        );
      } catch (e) {
        // Don't fail if local storage fails, Firestore is the source of truth
        if (kDebugMode) {
          print('Warning: Could not save to local storage: $e');
        }
      }

      // Update task attachments list with Firestore reference
      final taskData = taskDoc.data();
      final currentAttachments = List<String>.from(taskData?['attachments'] ?? []);
      
      // Use Firestore reference format: firestore_{taskId}_{attachmentId}
      final firestoreRef = 'firestore_${taskId}_$attachmentId';
      currentAttachments.add(firestoreRef);

      // Update task with new attachment reference
      await _firestore.collection('tasks').doc(taskId).update({
        'attachments': currentAttachments,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        print('✅ File saved to Firestore: $firestoreRef');
      }

      return {
        'success': true,
        'message': 'Attachment added successfully',
        'url': firestoreRef,
      };
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('Error adding attachment: $e');
        print('Stack trace: $stackTrace');
      }
      return {
        'success': false,
        'message': 'Failed to add attachment: ${e.toString()}',
      };
    }
  }

  // Remove attachment from task
  Future<Map<String, dynamic>> removeTaskAttachment({
    required String taskId,
    required String attachmentUrl,
  }) async {
    try {
      final taskDoc = await _firestore.collection('tasks').doc(taskId).get();
      if (!taskDoc.exists) {
        return {'success': false, 'message': 'Task not found'};
      }

      final taskData = taskDoc.data()!;
      final currentAttachments = List<String>.from(taskData['attachments'] ?? []);

      // Remove attachment URL/identifier
      currentAttachments.remove(attachmentUrl);

      // Extract attachment ID based on format
      String? attachmentId;
      if (attachmentUrl.startsWith('firestore_')) {
        // Format: firestore_{taskId}_{attachmentId}
        final parts = attachmentUrl.split('_');
        if (parts.length >= 3) {
          attachmentId = parts.sublist(2).join('_');
          // Delete from Firestore subcollection
          await _firestore
              .collection('tasks')
              .doc(taskId)
              .collection('attachments')
              .doc(attachmentId)
              .delete();
        }
      } else if (LocalAttachmentService.isLocalStorage(attachmentUrl)) {
        // Legacy local storage attachment
        attachmentId = LocalAttachmentService.extractAttachmentId(attachmentUrl);
        if (attachmentId != null) {
          await _localAttachmentService.deleteAttachment(attachmentId);
        }
      }

      // Update task
      await _firestore.collection('tasks').doc(taskId).update({
        'attachments': currentAttachments,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return {'success': true, 'message': 'Attachment removed successfully'};
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to remove attachment: ${e.toString()}',
      };
    }
  }

      // Get attachment data from Firestore (for sharing between staff and attorney)
  Future<Map<String, dynamic>?> getTaskAttachment({
    required String taskId,
    required String attachmentId,
  }) async {
    try {
      if (kDebugMode) {
        print('🔍 Getting attachment from Firestore: taskId=$taskId, attachmentId=$attachmentId');
      }

      final attachmentDoc = await _firestore
          .collection('tasks')
          .doc(taskId)
          .collection('attachments')
          .doc(attachmentId)
          .get();

      if (!attachmentDoc.exists) {
        if (kDebugMode) {
          print('❌ Attachment document does not exist: $attachmentId');
        }
        return null;
      }

      final data = attachmentDoc.data();
      if (data == null) {
        if (kDebugMode) {
          print('❌ Attachment data is null');
        }
        return null;
      }

      if (kDebugMode) {
        print('✅ Attachment found: ${data['fileName']}');
      }

      return {
        'fileName': data['fileName'] ?? 'attachment',
        'fileExtension': data['fileExtension'] ?? '',
        'fileSize': data['fileSize'] ?? 0,
        'fileData': data['fileData'], // Base64 encoded
        'uploadedBy': data['uploadedBy'],
        'uploadedAt': data['uploadedAt'],
        'attachmentId': data['attachmentId'] ?? attachmentId,
      };
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting attachment from Firestore: $e');
      }
      return null;
    }
  }

  // Check if attachment URL is a Firestore reference
  static bool isFirestoreAttachment(String url) {
    return url.startsWith('firestore_');
  }

  // Extract attachment ID from Firestore reference
  // Format: firestore_{taskId}_{attachmentId}
  static String? extractFirestoreAttachmentId(String url, String taskId) {
    if (!url.startsWith('firestore_')) {
      return null;
    }
    final prefix = 'firestore_${taskId}_';
    if (!url.startsWith(prefix)) {
      return null;
    }
    return url.substring(prefix.length);
  }
}
