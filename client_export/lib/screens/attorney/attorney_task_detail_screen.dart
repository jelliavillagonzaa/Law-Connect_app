import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../services/task_service.dart';
import '../../services/local_attachment_service.dart';
import '../../models/task_model.dart';
import '../../models/case_model.dart';
import '../../theme/app_theme.dart';
import '../../pages/case/case_detail_page.dart';
import '../client/chat_screen.dart';

class AttorneyTaskDetailScreen extends StatefulWidget {
  final String taskId;

  const AttorneyTaskDetailScreen({super.key, required this.taskId});

  @override
  State<AttorneyTaskDetailScreen> createState() =>
      _AttorneyTaskDetailScreenState();
}

class _AttorneyTaskDetailScreenState extends State<AttorneyTaskDetailScreen> {
  final TaskService _taskService = TaskService();
  final LocalAttachmentService _localAttachmentService =
      LocalAttachmentService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  TaskModel? _task;
  _TaskDetailContext? _context;
  bool _isLoading = true;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadTask();
  }

  Future<void> _loadTask() async {
    try {
      final task = await _taskService.getTask(widget.taskId);
      if (task != null) {
        setState(() {
          _task = task;
        });
        await _loadContext(task);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading task: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadContext(TaskModel task) async {
    String? caseTitle;
    String? caseNumber;
    String? practiceArea;
    String? clientId;
    String? clientName;
    String? staffName;

    try {
      // Load case info if available
      if (task.caseId != null && task.caseId!.isNotEmpty) {
        final caseDoc = await _firestore
            .collection('cases')
            .doc(task.caseId)
            .get();
        if (caseDoc.exists) {
          final caseModel = CaseModel.fromFirestore(caseDoc);
          caseTitle = caseModel.caseTitle;
          caseNumber = caseModel.id;
          practiceArea = caseModel.caseType;
          clientId = caseModel.clientId;
        }
      }

      // Load staff name (assignedTo)
      if (task.assignedTo.isNotEmpty) {
        final staffDoc = await _firestore
            .collection('users')
            .doc(task.assignedTo)
            .get();
        if (staffDoc.exists) {
          final data = staffDoc.data();
          staffName = data?['fullName'] ?? data?['name'] ?? data?['email'];
        }
      }
    } catch (e) {
      // Fail silently
    }

    if (mounted) {
      setState(() {
        _context = _TaskDetailContext(
          caseTitle: caseTitle,
          caseNumber: caseNumber,
          practiceArea: practiceArea,
          clientId: clientId,
          clientName: clientName,
          staffName: staffName,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Task Details'),
          backgroundColor: AppTheme.royalBlue,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_task == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Task Details'),
          backgroundColor: AppTheme.royalBlue,
        ),
        body: const Center(child: Text('Task not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Details'),
        backgroundColor: AppTheme.royalBlue,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _showEditTaskDialog,
            tooltip: 'Edit Task',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Basic Info Section
            _buildSectionTitle('Basic Info'),
            _buildBasicInfo(),
            const SizedBox(height: 24),

            // Linked Records Section
            if (_context != null && _context!.caseTitle != null) ...[
              _buildSectionTitle('Linked Case'),
              _buildLinkedCase(),
              const SizedBox(height: 24),
            ],

            // People Section
            _buildSectionTitle('People'),
            _buildPeopleSection(),
            const SizedBox(height: 24),

            // Notes Section (Staff's notes that attorney can review and edit)
            _buildSectionTitle('Notes & Comments'),
            _buildNotesSection(),
            const SizedBox(height: 24),

            // Attachments Section
            _buildSectionTitle('Attachments'),
            _buildAttachmentsSection(),
            const SizedBox(height: 24),

            // Actions Section
            _buildSectionTitle('Actions'),
            _buildActionsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppTheme.royalBlue,
        ),
      ),
    );
  }

  Widget _buildBasicInfo() {
    final dueInfo = _getDueInfo(_task!.dueDate);
    final priorityLabel = _getPriorityLabel(_task!.priority);
    final statusLabel = _getStatusLabel(_task!.status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _task!.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildPriorityChip(priorityLabel, _task!.priority),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Description:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 4),
            Text(_task!.description, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildInfoRow(
                    'Priority',
                    priorityLabel,
                    _getPriorityColor(_task!.priority),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildInfoRow(
                    'Status',
                    statusLabel,
                    _getStatusColor(_task!.status),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_task!.dueDate != null)
              _buildInfoRow(
                'Due Date',
                DateFormat('MMM dd, yyyy • hh:mm a').format(_task!.dueDate!),
                dueInfo.color,
              ),
            if (_task!.dueDate != null) ...[
              const SizedBox(height: 8),
              Chip(
                label: Text(
                  dueInfo.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: dueInfo.color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: dueInfo.color.withOpacity(0.1),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLinkedCase() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_context!.caseTitle != null) ...[
              _buildInfoRow('Case', _context!.caseTitle!),
              if (_context!.caseNumber != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Case #: ${_context!.caseNumber}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ],
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CaseDetailPage(caseId: _task!.caseId!),
                    ),
                  );
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('View Case Details'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.royalBlue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPeopleSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_context!.staffName != null)
              _buildInfoRow('Assigned Staff', _context!.staffName!),
            if (_context!.clientName != null) ...[
              if (_context!.staffName != null) const SizedBox(height: 12),
              _buildInfoRow('Client', _context!.clientName!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNotesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Staff Notes & Comments',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: _showEditNotesDialog,
                  tooltip: 'Edit Notes',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_task!.notes != null && _task!.notes!.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Text(
                  _task!.notes!,
                  style: const TextStyle(fontSize: 14),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Text(
                  'No notes added yet',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentsSection() {
    final attachments = _task!.attachments ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (attachments.isEmpty)
              const Text('No attachments', style: TextStyle(color: Colors.grey))
            else
              ...attachments.map((url) => _buildAttachmentItem(url)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isUploading ? null : _addAttachment,
              icon: _isUploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.attach_file),
              label: const Text('Attach File'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.royalBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentItem(String url) {
    // Check if it's a Firestore attachment (for sharing between staff and attorney)
    final isFirestore = TaskService.isFirestoreAttachment(url);

    // Check if it's a local storage attachment
    final isLocalStorage = LocalAttachmentService.isLocalStorage(url);

    // Get file name - from Firestore, local storage, or URL
    String fileName;
    String? fileExtension;
    bool isImage = false;
    bool isPdf = false;

    if (isFirestore) {
      // For Firestore attachments, get metadata from Firestore
      final attachmentId = TaskService.extractFirestoreAttachmentId(
        url,
        _task!.id,
      );
      if (attachmentId != null) {
        return FutureBuilder<Map<String, dynamic>?>(
          future: _taskService.getTaskAttachment(
            taskId: _task!.id,
            attachmentId: attachmentId,
          ),
          builder: (context, snapshot) {
            // Show loading state
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Loading attachment...',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
              );
            }

            // Handle error state
            if (snapshot.hasError) {
              if (kDebugMode) {
                print('Error loading attachment: ${snapshot.error}');
              }
              fileName = attachmentId.split('_').skip(1).join('_');
              return _buildAttachmentItemWidget(fileName, false, false, url);
            }

            // Handle data
            if (snapshot.hasData && snapshot.data != null) {
              fileName = snapshot.data!['fileName'] ?? attachmentId;
              fileExtension = snapshot.data!['fileExtension'] as String?;
            } else {
              // Fallback to attachment ID
              fileName = attachmentId.split('_').skip(1).join('_');
            }

            // Determine file type
            final ext = (fileExtension ?? '').toLowerCase();
            isImage = ['jpg', 'jpeg', 'png', 'gif'].contains(ext);
            isPdf = ext == 'pdf';

            return _buildAttachmentItemWidget(fileName, isImage, isPdf, url);
          },
        );
      } else {
        fileName = 'Unknown file';
      }
    } else if (isLocalStorage) {
      // For local storage, extract ID and get metadata
      final attachmentId = LocalAttachmentService.extractAttachmentId(url);
      if (attachmentId != null) {
        // Use FutureBuilder to get metadata
        return FutureBuilder<Map<String, dynamic>?>(
          future: _localAttachmentService.getAttachmentMetadata(attachmentId),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data != null) {
              fileName = snapshot.data!['fileName'] ?? attachmentId;
              fileExtension = snapshot.data!['fileExtension'] as String?;
            } else {
              // Fallback to attachment ID
              fileName = attachmentId.split('_').skip(1).join('_');
            }

            // Determine file type
            final ext = (fileExtension ?? '').toLowerCase();
            isImage = ['jpg', 'jpeg', 'png', 'gif'].contains(ext);
            isPdf = ext == 'pdf';

            return _buildAttachmentItemWidget(fileName, isImage, isPdf, url);
          },
        );
      } else {
        fileName = 'Unknown file';
      }
    } else {
      // Firebase Storage URL (legacy)
      fileName = url.split('/').last.split('?').first;
      final ext = fileName.toLowerCase().split('.').last;
      isImage = ['jpg', 'jpeg', 'png', 'gif'].contains(ext);
      isPdf = ext == 'pdf';
    }

    return _buildAttachmentItemWidget(fileName, isImage, isPdf, url);
  }

  Widget _buildAttachmentItemWidget(
    String fileName,
    bool isImage,
    bool isPdf,
    String url,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            isImage
                ? Icons.image
                : isPdf
                ? Icons.picture_as_pdf
                : Icons.insert_drive_file,
            color: AppTheme.royalBlue,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              fileName,
              style: const TextStyle(fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new, size: 20),
            onPressed: () => _openAttachment(url),
            tooltip: 'Open',
          ),
          IconButton(
            icon: const Icon(Icons.delete, size: 20, color: Colors.red),
            onPressed: () => _removeAttachment(url),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }

  Widget _buildActionsSection() {
    final List<Widget> actionButtons = [];

    // Status Actions
    if (_task!.status == 'pending') {
      actionButtons.add(
        ElevatedButton.icon(
          onPressed: () => _updateStatus('in_progress'),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start Task'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.royalBlue,
            foregroundColor: AppTheme.cleanWhite,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    if (_task!.status == 'in_progress') {
      actionButtons.add(
        ElevatedButton.icon(
          onPressed: () => _updateStatus('completed'),
          icon: const Icon(Icons.check),
          label: const Text('Mark Completed'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: AppTheme.cleanWhite,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    // Add Note / Comment button (always available if not completed)
    if (_task!.status != 'completed') {
      if (actionButtons.isNotEmpty) {
        actionButtons.add(const SizedBox(height: 12));
      }
      actionButtons.add(
        OutlinedButton.icon(
          onPressed: _showEditNotesDialog,
          icon: const Icon(Icons.note_add),
          label: const Text('Add Note / Comment'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.royalBlue,
            side: BorderSide(
              color: AppTheme.royalBlue.withOpacity(0.5),
              width: 1.5,
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    // View Case Button (if case is linked)
    if (_task!.caseId != null && _task!.caseId!.isNotEmpty) {
      if (actionButtons.isNotEmpty) {
        actionButtons.add(const SizedBox(height: 12));
      }
      actionButtons.add(
        OutlinedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CaseDetailPage(caseId: _task!.caseId!),
              ),
            );
          },
          icon: const Icon(Icons.folder_open),
          label: const Text('View Case Details'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.royalBlue,
            side: BorderSide(
              color: AppTheme.royalBlue.withOpacity(0.5),
              width: 1.5,
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    // Messaging Actions
    if (_context?.staffName != null && _task!.assignedTo.isNotEmpty) {
      if (actionButtons.isNotEmpty) {
        actionButtons.add(const SizedBox(height: 12));
      }
      actionButtons.add(
        OutlinedButton.icon(
          onPressed: () => _messageStaff(_task!.assignedTo),
          icon: const Icon(Icons.message),
          label: const Text('Message Staff'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.royalBlue,
            side: BorderSide(
              color: AppTheme.royalBlue.withOpacity(0.5),
              width: 1.5,
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    if (_context?.clientId != null) {
      if (actionButtons.isNotEmpty) {
        actionButtons.add(const SizedBox(height: 12));
      }
      actionButtons.add(
        OutlinedButton.icon(
          onPressed: () => _messageClient(_context!.clientId!),
          icon: const Icon(Icons.person),
          label: const Text('Message Client'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.royalBlue,
            side: BorderSide(
              color: AppTheme.royalBlue.withOpacity(0.5),
              width: 1.5,
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    // If no actions available, show a message
    if (actionButtons.isEmpty) {
      actionButtons.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'No actions available for this task.',
            style: TextStyle(
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: actionButtons,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: valueColor ?? Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityChip(String label, int? priority) {
    return Chip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: _getPriorityColor(priority),
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: _getPriorityColor(priority).withOpacity(0.1),
    );
  }

  String _getPriorityLabel(int? priority) {
    switch (priority) {
      case 1:
        return 'Urgent';
      case 2:
        return 'High';
      case 3:
        return 'Normal';
      case 4:
        return 'Low';
      default:
        return 'Normal';
    }
  }

  Color _getPriorityColor(int? priority) {
    switch (priority) {
      case 1:
        return Colors.red;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.blue;
      case 4:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'overdue':
        return 'Overdue';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'overdue':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  _DueInfo _getDueInfo(DateTime? dueDate) {
    if (dueDate == null) {
      return const _DueInfo(label: 'No due date', color: Colors.grey);
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diff = target.difference(today).inDays;

    if (diff < 0) {
      return _DueInfo(label: 'Overdue (${-diff} days)', color: Colors.red);
    } else if (diff == 0) {
      return const _DueInfo(label: 'Due Today', color: Colors.orange);
    } else if (diff == 1) {
      return const _DueInfo(label: 'Due Tomorrow', color: Colors.blue);
    } else if (diff <= 7) {
      return _DueInfo(label: '$diff days left', color: Colors.blue);
    } else {
      return _DueInfo(label: '$diff days left', color: Colors.green);
    }
  }

  Future<void> _updateStatus(String status) async {
    final result = await _taskService.updateTaskStatus(_task!.id, status);
    if (result['success'] == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Task marked as ${status.replaceAll('_', ' ')}'),
          ),
        );
        await _loadTask();
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Failed to update task')),
        );
      }
    }
  }

  Future<void> _showEditTaskDialog() async {
    final titleController = TextEditingController(text: _task!.title);
    final descriptionController = TextEditingController(
      text: _task!.description,
    );
    String? selectedPriority = _task!.priority?.toString();
    DateTime? selectedDueDate = _task!.dueDate;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Task'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedPriority,
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: '1', child: Text('Urgent')),
                    DropdownMenuItem(value: '2', child: Text('High')),
                    DropdownMenuItem(value: '3', child: Text('Normal')),
                    DropdownMenuItem(value: '4', child: Text('Low')),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      selectedPriority = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: Text(
                    selectedDueDate != null
                        ? 'Due Date: ${DateFormat('MMM dd, yyyy • hh:mm a').format(selectedDueDate!)}'
                        : 'No due date',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedDueDate ?? DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: selectedDueDate != null
                              ? TimeOfDay.fromDateTime(selectedDueDate!)
                              : TimeOfDay.now(),
                        );
                        if (time != null) {
                          setDialogState(() {
                            selectedDueDate = DateTime(
                              date.year,
                              date.month,
                              date.day,
                              time.hour,
                              time.minute,
                            );
                          });
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.royalBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final updateResult = await _taskService.updateTaskDetails(
        taskId: _task!.id,
        title: titleController.text.trim(),
        description: descriptionController.text.trim(),
        priority: selectedPriority != null
            ? int.parse(selectedPriority!)
            : null,
        dueDate: selectedDueDate,
      );

      if (mounted) {
        if (updateResult['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Task updated successfully')),
          );
          await _loadTask();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(updateResult['message'] ?? 'Error updating task'),
            ),
          );
        }
      }
    }
  }

  Future<void> _showEditNotesDialog() async {
    final controller = TextEditingController(text: _task!.notes ?? '');
    final notes = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Notes / Comments'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Enter notes, updates, or questions...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (notes != null) {
      await _taskService.updateTaskStatus(
        _task!.id,
        _task!.status,
        notes: notes,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Notes updated')));
        await _loadTask();
      }
    }
  }

  Future<void> _addAttachment() async {
    if (_isUploading) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;

        final isValidFile = kIsWeb ? (file.bytes != null) : (file.path != null);

        if (!isValidFile) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Invalid file. Please select a valid file.'),
              ),
            );
          }
          return;
        }

        if (!mounted) return;

        setState(() {
          _isUploading = true;
        });

        try {
          final result2 = await _taskService.addTaskAttachment(
            taskId: _task!.id,
            file: file,
          );

          if (!mounted) return;

          setState(() {
            _isUploading = false;
          });

          if (result2['success'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('File attached successfully')),
            );
            await _loadTask();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result2['message'] ?? 'Failed to attach file'),
              ),
            );
          }
        } catch (uploadError) {
          if (mounted) {
            setState(() {
              _isUploading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Upload error: ${uploadError.toString()}'),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting file: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _removeAttachment(String url) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Attachment'),
        content: const Text('Are you sure you want to remove this attachment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final result = await _taskService.removeTaskAttachment(
        taskId: _task!.id,
        attachmentUrl: url,
      );

      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Attachment removed')));
          await _loadTask();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Failed to remove attachment'),
            ),
          );
        }
      }
    }
  }

  Future<void> _openAttachment(String url) async {
    // Show loading dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading attachment...'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    try {
      if (kDebugMode) {
        print('🔍 Opening attachment: $url');
      }

      Uint8List? fileBytes;
      String fileName = 'attachment';
      String fileExtension = '';

      // Check if it's a Firestore attachment (for sharing between staff and attorney)
      if (TaskService.isFirestoreAttachment(url)) {
        if (kDebugMode) {
          print('📦 Detected Firestore attachment');
        }
        final attachmentId = TaskService.extractFirestoreAttachmentId(
          url,
          _task!.id,
        );
        if (attachmentId == null) {
          if (mounted) Navigator.of(context).pop(); // Close loading dialog
          throw Exception('Invalid Firestore attachment ID');
        }

        if (kDebugMode) {
          print('📦 Attachment ID: $attachmentId');
        }

        // Get attachment data from Firestore
        final attachmentData = await _taskService.getTaskAttachment(
          taskId: _task!.id,
          attachmentId: attachmentId,
        );

        if (attachmentData == null) {
          if (mounted) Navigator.of(context).pop(); // Close loading dialog
          throw Exception('Attachment not found in Firestore');
        }

        // Decode base64 file data
        final base64Data = attachmentData['fileData'] as String?;
        if (base64Data == null || base64Data.isEmpty) {
          if (mounted) Navigator.of(context).pop(); // Close loading dialog
          throw Exception('File data is empty');
        }

        try {
          fileBytes = base64Decode(base64Data);
        } catch (e) {
          if (mounted) Navigator.of(context).pop(); // Close loading dialog
          throw Exception('Failed to decode file data: $e');
        }

        fileName = attachmentData['fileName'] ?? 'attachment';
        fileExtension = attachmentData['fileExtension'] ?? '';

        if (kDebugMode) {
          print(
            '✅ Loaded file: $fileName (${fileExtension}) - ${fileBytes.length} bytes',
          );
        }

        // Also cache to local storage for faster access next time
        try {
          await _localAttachmentService.saveAttachment(
            attachmentId: attachmentId,
            fileBytes: fileBytes,
            fileName: fileName,
            fileExtension: fileExtension,
          );
        } catch (e) {
          // Don't fail if local storage caching fails
          if (kDebugMode) {
            print('Warning: Could not cache to local storage: $e');
          }
        }
      } else if (LocalAttachmentService.isLocalStorage(url)) {
        // Local storage attachment
        final attachmentId = LocalAttachmentService.extractAttachmentId(url);
        if (attachmentId == null) {
          if (mounted) Navigator.of(context).pop(); // Close loading dialog
          throw Exception('Invalid local storage attachment ID');
        }

        // Get file data from local storage
        fileBytes = await _localAttachmentService.getAttachment(attachmentId);
        if (fileBytes == null) {
          if (mounted) Navigator.of(context).pop(); // Close loading dialog
          throw Exception('Attachment not found in local storage');
        }

        // Get metadata for file name
        final metadata = await _localAttachmentService.getAttachmentMetadata(
          attachmentId,
        );
        fileName = metadata?['fileName'] ?? 'attachment';
        fileExtension = metadata?['fileExtension'] ?? '';
      } else {
        // Firebase Storage URL (legacy) - open normally
        if (mounted) Navigator.of(context).pop(); // Close loading dialog
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open attachment')),
            );
          }
        }
        return;
      }

      // Save to temporary file and open (for Firestore and local storage attachments)
      // fileBytes is guaranteed to be non-null at this point (already checked above)
      final nonNullFileBytes = fileBytes;

      // Close loading dialog before showing image
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Check if it's an image file - show in image viewer (works on all platforms)
      // Always check filename extension as primary method, then fileExtension field
      String ext = '';

      // First, try to get extension from filename (most reliable)
      if (fileName.contains('.')) {
        ext = fileName.split('.').last.toLowerCase().trim();
      }

      // If filename doesn't have extension, use fileExtension field
      if (ext.isEmpty && fileExtension.isNotEmpty) {
        ext = fileExtension.toLowerCase().trim();
      }

      // Remove any query parameters or extra characters
      ext = ext.split('?').first.split('#').first;

      final isImage = [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'bmp',
        'webp',
      ].contains(ext);

      if (kDebugMode) {
        print('🖼️ File: $fileName');
        print('🖼️ File extension field: $fileExtension');
        print('🖼️ Detected extension: $ext');
        print('🖼️ Is image: $isImage');
      }

      if (isImage) {
        // Show image in a dialog viewer (works on web, mobile, and desktop)
        if (mounted) {
          if (kDebugMode) {
            print('🖼️ Showing image viewer for: $fileName');
          }
          showDialog(
            context: context,
            barrierColor: Colors.black87,
            barrierDismissible: true,
            builder: (context) => Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(16),
              child: Stack(
                children: [
                  Center(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Image.memory(
                        nonNullFileBytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) {
                          if (kDebugMode) {
                            print('❌ Image error: $error');
                          }
                          return Container(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.error,
                                  color: Colors.red,
                                  size: 48,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Error loading image',
                                  style: TextStyle(color: Colors.white),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  error.toString(),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                  ),
                  // Show file name at bottom
                  Positioned(
                    bottom: 8,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        fileName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      } else {
        // For non-image files or if image detection failed, try to open with system app
        // But first, double-check if it might be an image by checking file signature
        bool mightBeImage = false;
        if (fileBytes.isNotEmpty) {
          // Check PNG signature: 89 50 4E 47
          if (fileBytes.length >= 4 &&
              fileBytes[0] == 0x89 &&
              fileBytes[1] == 0x50 &&
              fileBytes[2] == 0x4E &&
              fileBytes[3] == 0x47) {
            mightBeImage = true;
          }
          // Check JPEG signature: FF D8 FF
          else if (fileBytes.length >= 3 &&
              fileBytes[0] == 0xFF &&
              fileBytes[1] == 0xD8 &&
              fileBytes[2] == 0xFF) {
            mightBeImage = true;
          }
          // Check GIF signature: GIF
          else if (fileBytes.length >= 3 &&
              fileBytes[0] == 0x47 &&
              fileBytes[1] == 0x49 &&
              fileBytes[2] == 0x46) {
            mightBeImage = true;
          }
        }

        if (mightBeImage) {
          // It's actually an image, show it in viewer
          if (kDebugMode) {
            print('🖼️ Detected image by file signature, showing viewer');
          }
          if (mounted) {
            showDialog(
              context: context,
              barrierColor: Colors.black87,
              barrierDismissible: true,
              builder: (context) => Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(16),
                child: Stack(
                  children: [
                    Center(
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 4.0,
                        child: Image.memory(
                          nonNullFileBytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          padding: const EdgeInsets.all(8),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          fileName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return;
        }

        // Not an image, handle based on platform
        if (kIsWeb) {
          // For web non-image files, show message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'File type not supported for viewing on web: ${ext.isEmpty ? fileExtension : ext}',
                ),
                action: SnackBarAction(label: 'OK', onPressed: () {}),
              ),
            );
          }
        } else {
          // For mobile/desktop non-image files, save to temp directory and open
          final tempDir = await getTemporaryDirectory();
          final tempFile = File(path.join(tempDir.path, fileName));
          await tempFile.writeAsBytes(nonNullFileBytes);

          final uri = Uri.file(tempFile.path);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not open attachment')),
              );
            }
          }
        }
      }
    } catch (e, stackTrace) {
      // Close loading dialog if still open
      if (mounted) {
        try {
          Navigator.of(context).pop();
        } catch (_) {
          // Dialog might already be closed
        }
      }

      if (kDebugMode) {
        print('❌ Error opening attachment: $e');
        print('Stack trace: $stackTrace');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening attachment: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    }
  }

  Future<void> _messageStaff(String staffId) async {
    try {
      // Get staff name
      final staffDoc = await _firestore.collection('users').doc(staffId).get();
      String staffName = 'Staff';
      if (staffDoc.exists) {
        final data = staffDoc.data();
        staffName = data?['name'] ?? data?['fullName'] ?? 'Staff';
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            conversationId: null,
            otherUserId: staffId,
            otherUserName: staffName,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error opening chat: $e')));
      }
    }
  }

  Future<void> _messageClient(String clientId) async {
    try {
      // Get client name
      final clientDoc = await _firestore
          .collection('users')
          .doc(clientId)
          .get();
      String clientName = 'Client';
      if (clientDoc.exists) {
        final data = clientDoc.data();
        clientName = data?['name'] ?? data?['fullName'] ?? 'Client';
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            conversationId: null,
            otherUserId: clientId,
            otherUserName: clientName,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error opening chat: $e')));
      }
    }
  }
}

class _TaskDetailContext {
  final String? caseTitle;
  final String? caseNumber;
  final String? practiceArea;
  final String? clientId;
  final String? clientName;
  final String? staffName;

  _TaskDetailContext({
    this.caseTitle,
    this.caseNumber,
    this.practiceArea,
    this.clientId,
    this.clientName,
    this.staffName,
  });
}

class _DueInfo {
  final String label;
  final Color color;

  const _DueInfo({required this.label, required this.color});
}
