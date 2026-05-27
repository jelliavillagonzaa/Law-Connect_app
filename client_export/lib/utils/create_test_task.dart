import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/task_service.dart';

/// Utility function to create a test task for the current logged-in staff
/// Call this once to create a test task
Future<void> createTestTask() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('[ERROR] No user logged in. Please log in as staff first.');
      return;
    }

    // Get user role
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!userDoc.exists) {
      print('[ERROR] User document not found');
      return;
    }

    final userData = userDoc.data()!;
    final userRole = userData['role'] as String?;

    if (userRole != 'staff') {
      print(
        '[ERROR] Current user is not a staff member. Please log in as staff.',
      );
      return;
    }

    // Get assigned attorney
    final assignedAttorneyId = userData['assignedAttorneyId'] as String?;
    if (assignedAttorneyId == null || assignedAttorneyId.isEmpty) {
      print(
        '[WARNING] Staff is not assigned to an attorney. Creating task without attorney...',
      );
    }

    final taskService = TaskService();

    // Create test task
    final result = await taskService.createTask(
      title: 'Draft Motion for Case 123',
      description:
          'Prepare and draft a motion document for Case 123. Include all necessary legal arguments and supporting evidence.',
      assignedTo: user.uid, // Assign to current staff
      dueDate: DateTime.now().add(const Duration(days: 3)), // Due in 3 days
      priority: 2, // High priority
    );

    if (result['success'] == true) {
      print('[SUCCESS] Test task created successfully!');
      print('Task ID: ${result['taskId']}');
      print('Title: Draft Motion for Case 123');
      print('Due Date: ${DateTime.now().add(const Duration(days: 3))}');
      print('Priority: High');
      print('');
      print('Tip: Refresh your tasks screen to see the new task!');
    } else {
      print('[ERROR] Failed to create task: ${result['message']}');
    }
  } catch (e) {
    print('[ERROR] Error creating test task: $e');
  }
}

/// Create multiple test tasks with different statuses and priorities
Future<void> createMultipleTestTasks() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('[ERROR] No user logged in. Please log in as staff first.');
      return;
    }

    // Get user role
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!userDoc.exists) {
      print('[ERROR] User document not found');
      return;
    }

    final userData = userDoc.data()!;
    final userRole = userData['role'] as String?;

    if (userRole != 'staff') {
      print(
        '[ERROR] Current user is not a staff member. Please log in as staff.',
      );
      return;
    }

    final taskService = TaskService();

    // Create multiple test tasks
    final tasks = [
      {
        'title': 'Draft Motion for Case 123',
        'description':
            'Prepare and draft a motion document for Case 123. Include all necessary legal arguments.',
        'dueDate': DateTime.now().add(const Duration(days: 3)),
        'priority': 2, // High
        'status': 'pending',
      },
      {
        'title': 'Review Contract Documents',
        'description':
            'Review and analyze contract documents for client meeting. Highlight key terms and potential issues.',
        'dueDate': DateTime.now().add(const Duration(days: 1)),
        'priority': 1, // Urgent
        'status': 'pending',
      },
      {
        'title': 'Prepare Case Summary',
        'description':
            'Create a comprehensive case summary including timeline, key events, and relevant documents.',
        'dueDate': DateTime.now().subtract(const Duration(days: 1)), // Overdue
        'priority': 2, // High
        'status': 'pending',
      },
      {
        'title': 'File Court Documents',
        'description':
            'File the prepared court documents with the clerk\'s office. Ensure all signatures are present.',
        'dueDate': DateTime.now().add(const Duration(days: 7)),
        'priority': 3, // Normal
        'status': 'in_progress',
      },
      {
        'title': 'Schedule Client Meeting',
        'description':
            'Coordinate with client to schedule a meeting to discuss case progress and next steps.',
        'dueDate': DateTime.now().add(const Duration(days: 5)),
        'priority': 4, // Low
        'status': 'pending',
      },
    ];

    int successCount = 0;
    for (var taskData in tasks) {
      final result = await taskService.createTask(
        title: taskData['title'] as String,
        description: taskData['description'] as String,
        assignedTo: user.uid,
        dueDate: taskData['dueDate'] as DateTime,
        priority: taskData['priority'] as int,
      );

      if (result['success'] == true) {
        successCount++;
        // Update status if needed (since createTask always creates as 'pending')
        if (taskData['status'] == 'in_progress') {
          await taskService.updateTaskStatus(
            result['taskId'] as String,
            'in_progress',
          );
        }
      }
    }

    print('[SUCCESS] Created $successCount out of ${tasks.length} test tasks!');
    print('Tip: Refresh your tasks screen to see the new tasks!');
  } catch (e) {
    print('[ERROR] Error creating test tasks: $e');
  }
}
