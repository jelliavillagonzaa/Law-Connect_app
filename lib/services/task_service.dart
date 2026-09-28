import 'dart:async';
import 'dart:io' show File;
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:file_picker/file_picker.dart';
import '../models/task_model.dart';
import '../utils/case_status_filter.dart';
import 'case_service.dart';
import 'firestore_mirror_helper.dart';
import 'local_attachment_service.dart';
import 'fcm_service.dart';
import 'staff_service.dart';

class TaskService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // Removed unused _storage field
  final LocalAttachmentService _localAttachmentService = LocalAttachmentService();
  final FCMService _fcmService = FCMService();

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

      final result = await HybridDatastore.add(collection: 'tasks', data: taskData);
      if (!result.isSuccess) {
        return {'success': false, 'message': result.failureMessage};
      }

      try {
        await _notifyStaffTaskAssigned(
          staffId: assignedTo,
          taskId: result.id!,
          title: title,
          caseId: caseId,
        );
      } catch (e) {
        if (kDebugMode) {
          print('Failed to notify staff of new task: $e');
        }
      }

      if (caseId != null && caseId.trim().isNotEmpty) {
        try {
          await _markLinkedOpenCaseInProgress(caseId);
        } catch (e) {
          if (kDebugMode) {
            print('Failed to move linked case to in progress: $e');
          }
        }
      }

      return {
        'success': true,
        'message': 'Task created successfully',
        'taskId': result.id,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to create task: ${e.toString()}',
      };
    }
  }

  Future<void> _markLinkedOpenCaseInProgress(String caseId) async {
    final caseDoc = await _firestore.collection('cases').doc(caseId).get();
    if (!caseDoc.exists) return;
    final status = caseDoc.data()?['status'] as String?;
    if (!CaseStatusFilter.isOpen(status)) return;
    await CaseService().updateCaseStatus(caseId, 'in_progress');
  }

  Future<void> _notifyStaffTaskAssigned({
    required String staffId,
    required String taskId,
    required String title,
    String? caseId,
  }) async {
    String? caseTitle;
    if (caseId != null && caseId.isNotEmpty) {
      try {
        final caseDoc = await _firestore.collection('cases').doc(caseId).get();
        caseTitle = (caseDoc.data()?['caseTitle'] as String?)?.trim();
      } catch (_) {}
    }

    final message = (caseTitle != null && caseTitle.isNotEmpty)
        ? 'New task "$title" for case "$caseTitle".'
        : 'New task "$title" was assigned to you.';

    await HybridDatastore.add(
      collection: 'notifications',
      data: {
        'userId': staffId,
        'type': 'task_assigned',
        'title': 'New Task Assigned',
        'message': message,
        'taskId': taskId,
        if (caseId != null) 'caseId': caseId,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );

    await _fcmService.sendNotificationToUser(
      userId: staffId,
      title: 'New Task Assigned',
      body: message,
      data: {
        'type': 'task_assigned',
        'taskId': taskId,
        if (caseId != null) 'caseId': caseId,
      },
    );
  }

  Stream<List<TaskModel>> getStaffTasks(String staffId) {
    return _streamSortedTasks(
      _firestore.collection('tasks').where('assignedTo', isEqualTo: staffId),
    );
  }

  Stream<List<TaskModel>> getStaffTasksByStatus(String staffId, String status) {
    return _streamSortedTasks(
      _firestore
          .collection('tasks')
          .where('assignedTo', isEqualTo: staffId)
          .where('status', isEqualTo: status),
    );
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

      final result = await HybridDatastore.update(
        collection: 'tasks',
        id: taskId,
        patch: updateData,
      );
      if (!result.isSuccess) {
        return {'success': false, 'message': result.failureMessage};
      }

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

      final result = await HybridDatastore.update(
        collection: 'tasks',
        id: taskId,
        patch: updateData,
      );
      if (!result.isSuccess) {
        return {'success': false, 'message': result.failureMessage};
      }

      try {
        final user = _auth.currentUser;
        if (user != null) {
          final userDoc =
              await _firestore.collection('users').doc(user.uid).get();
          final role =
              (userDoc.data()?['role'] as String?)?.toLowerCase().trim() ?? '';
          if (role == 'staff' ||
              role == 'paralegal' ||
              role.contains('assistant')) {
            final taskDoc =
                await _firestore.collection('tasks').doc(taskId).get();
            final title = taskDoc.data()?['title'] as String? ?? 'Task';
            await StaffService().logActivity(
              action: 'Task updated',
              details: 'Set "$title" to $status',
              resourceType: 'task',
              resourceId: taskId,
            );
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Failed to log task activity: $e');
        }
      }

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
              final notifData = <String, dynamic>{
                'userId': attorneyId,
                'type': 'task_completed',
                'title': 'Task Completed',
                'message': 'Task "$taskTitle" has been completed by staff',
                'taskId': taskId,
                'isRead': false,
                'createdAt': FieldValue.serverTimestamp(),
              };
              await HybridDatastore.add(
                collection: 'notifications',
                data: notifData,
              );
              try {
                await _fcmService.sendNotificationToUser(
                  userId: attorneyId,
                  title: 'Task Completed',
                  body: 'Task "$taskTitle" has been completed by staff',
                  data: {
                    'type': 'task_completed',
                    'taskId': taskId,
                  },
                );
              } catch (_) {}
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
      final result = await HybridDatastore.update(
        collection: 'tasks',
        id: taskId,
        patch: {
          'priority': priority,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      if (!result.isSuccess) {
        return {'success': false, 'message': result.failureMessage};
      }

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

  Stream<List<TaskModel>> getAttorneyTasks(String attorneyId) {
    return _streamSortedTasks(
      _firestore.collection('tasks').where('attorneyId', isEqualTo: attorneyId),
    );
  }

  Stream<List<TaskModel>> getAttorneyTasksByStatus(
    String attorneyId,
    String status,
  ) {
    return _streamSortedTasks(
      _firestore
          .collection('tasks')
          .where('attorneyId', isEqualTo: attorneyId)
          .where('status', isEqualTo: status),
    );
  }

  Stream<List<TaskModel>> _streamSortedTasks(Query<Map<String, dynamic>> query) {
    return query
        .snapshots()
        .asyncMap((snapshot) async {
          final tasks = snapshot.docs
              .map((doc) => TaskModel.fromFirestore(doc))
              .toList();
          tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return _excludeClosedCaseTasks(tasks);
        })
        .transform(
          StreamTransformer<List<TaskModel>, List<TaskModel>>.fromHandlers(
            handleError: (error, stack, sink) {
              sink.add(const <TaskModel>[]);
            },
          ),
        );
  }

  /// Tasks on a completed case leave Staff Tasks; they stay on the case.
  Future<List<TaskModel>> _excludeClosedCaseTasks(List<TaskModel> tasks) async {
    try {
      final ids = tasks
          .map((task) => task.caseId?.trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (ids.isEmpty) return tasks;

      final closedIds = <String>{};
      for (var i = 0; i < ids.length; i += 10) {
        final end = i + 10 > ids.length ? ids.length : i + 10;
        final chunk = ids.sublist(i, end);
        final snap = await _firestore
            .collection('cases')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          final status = doc.data()['status']?.toString();
          if (CaseStatusFilter.isCompleted(status)) {
            closedIds.add(doc.id);
          }
        }
      }

      return tasks.where((task) {
        final caseId = task.caseId?.trim() ?? '';
        if (caseId.isEmpty) return true;
        return !closedIds.contains(caseId);
      }).toList();
    } catch (e) {
      if (kDebugMode) {
        print('Failed to hide closed-case tasks: $e');
      }
      return tasks;
    }
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
      final attachResult = await HybridDatastore.update(
        collection: 'tasks',
        id: taskId,
        patch: {
          'attachments': currentAttachments,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      if (!attachResult.isSuccess) {
        return {'success': false, 'message': attachResult.failureMessage};
      }

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
      final result = await HybridDatastore.update(
        collection: 'tasks',
        id: taskId,
        patch: {
          'attachments': currentAttachments,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      if (!result.isSuccess) {
        return {'success': false, 'message': result.failureMessage};
      }

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
