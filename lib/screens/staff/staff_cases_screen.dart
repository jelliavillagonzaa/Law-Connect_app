import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/staff_service.dart';
import '../../services/staff_auth_service.dart';
import '../../services/storage_service.dart';
import '../../models/case_model.dart';
import '../../models/user_model.dart';
import '../../theme/app_theme.dart';

class StaffCasesScreen extends StatefulWidget {
  const StaffCasesScreen({super.key});

  @override
  State<StaffCasesScreen> createState() => _StaffCasesScreenState();
}

class _StaffCasesScreenState extends State<StaffCasesScreen> {
  final StaffService _staffService = StaffService();
  final StaffAuthService _staffAuthService = StaffAuthService();
  String _selectedFilter = 'all';
  String? _assignedAttorneyId;
  bool _showAllCases = false; // Toggle between assigned and all attorney cases

  @override
  void initState() {
    super.initState();
    _loadAttorneyId();
  }

  Future<void> _loadAttorneyId() async {
    final staff = await _staffAuthService.getCurrentStaff();
    if (staff != null) {
      setState(() {
        _assignedAttorneyId = staff.assignedAttorneyId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Not logged in'));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _showAllCases ? 'All Attorney Cases' : 'Assigned Cases',
          style: TextStyle(),
        ),
        actions: [
          if (_assignedAttorneyId != null)
            IconButton(
              icon: Icon(
                _showAllCases ? Icons.assignment_ind : Icons.assignment,
                color: AppTheme.cleanWhite,
              ),
              onPressed: () {
                setState(() => _showAllCases = !_showAllCases);
              },
              tooltip: _showAllCases
                  ? 'Show Only Assigned Cases'
                  : 'Show All Attorney Cases',
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() => _selectedFilter = value);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('All Cases')),
              const PopupMenuItem(value: 'active', child: Text('Active')),
              const PopupMenuItem(value: 'pending', child: Text('Pending')),
              const PopupMenuItem(value: 'completed', child: Text('Completed')),
            ],
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Icon(Icons.filter_list, color: AppTheme.cleanWhite),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<CaseModel>>(
        stream: _showAllCases && _assignedAttorneyId != null
            ? _staffService.getAttorneyCases(_assignedAttorneyId!)
            : _staffService.getAssignedCases(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Error: ${snapshot.error}',
                    style: TextStyle(),
                  ),
                ],
              ),
            );
          }

          final allCases = snapshot.data ?? [];
          final filteredCases = _filterCases(allCases, _selectedFilter);

          if (filteredCases.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No cases assigned yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredCases.length,
            itemBuilder: (context, index) {
              final caseModel = filteredCases[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: _getStatusColor(caseModel.status),
                    child: Icon(
                      _getStatusIcon(caseModel.status),
                      color: AppTheme.cleanWhite,
                    ),
                  ),
                  title: Text(
                    caseModel.caseTitle,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        'Type: ${caseModel.caseType}',
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Status: ${caseModel.status.toUpperCase()}',
                        style: TextStyle(
                          fontSize: 12,
                          color: _getStatusColor(caseModel.status),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Updated: ${DateFormat('MMM dd, yyyy').format(caseModel.updatedAt)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.mutedText,
                        ),
                      ),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Get.to(() => StaffCaseDetailPage(caseModel: caseModel));
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  List<CaseModel> _filterCases(List<CaseModel> cases, String filter) {
    switch (filter) {
      case 'active':
        return cases
            .where((c) => c.status == 'in_progress' || c.status == 'accepted')
            .toList();
      case 'pending':
        return cases.where((c) => c.status == 'pending').toList();
      case 'completed':
        return cases.where((c) => c.status == 'completed').toList();
      default:
        return cases;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
      case 'in_progress':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.pending;
      case 'accepted':
      case 'in_progress':
        return Icons.work;
      case 'completed':
        return Icons.check_circle;
      default:
        return Icons.folder;
    }
  }
}

// Staff-specific case detail page with restricted actions
class StaffCaseDetailPage extends StatefulWidget {
  final CaseModel caseModel;

  const StaffCaseDetailPage({super.key, required this.caseModel});

  @override
  State<StaffCaseDetailPage> createState() => _StaffCaseDetailPageState();
}

class _StaffCaseDetailPageState extends State<StaffCaseDetailPage> {
  final StaffService _staffService = StaffService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _noteController = TextEditingController();
  bool _isUploading = false;
  UserModel? _client;

  @override
  void initState() {
    super.initState();
    _loadClientInfo();
  }

  Future<void> _loadClientInfo() async {
    final clientId = widget.caseModel.clientId;
    if (clientId.isNotEmpty) {
      final clientDoc = await _firestore
          .collection('users')
          .doc(clientId)
          .get();
      if (clientDoc.exists && mounted) {
        setState(() {
          _client = UserModel.fromFirestore(clientDoc.data()!, clientId);
        });
      }
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Widget _buildClientInfo() {
    if (_client == null) return const SizedBox.shrink();

    final clientEmail = _client!.email;
    final clientPhone = _client!.phoneNumber;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        Text(
          'Client Information',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.person, size: 20, color: AppTheme.royalBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _client!.name,
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        if (clientEmail.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.email, size: 20, color: AppTheme.royalBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  clientEmail,
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ],
        if (clientPhone != null && clientPhone.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.phone, size: 20, color: AppTheme.royalBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  clientPhone,
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Case Details', style: TextStyle()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Case Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.caseModel.caseTitle,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.royalBlue,
                            ),
                          ),
                        ),
                        Chip(
                          label: Text(
                            widget.caseModel.status.toUpperCase(),
                            style: TextStyle(
                              color: AppTheme.cleanWhite,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                          backgroundColor: _getStatusColor(
                            widget.caseModel.status,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Type: ${widget.caseModel.caseType}',
                      style: TextStyle(fontSize: 16),
                    ),
                    // Client Information
                    _buildClientInfo(),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.blue,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Staff Access: You can view, add notes, and upload documents. You cannot delete or close cases.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Description',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.caseModel.caseDescription,
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Add Note Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add Note for Attorney Review',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _noteController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Enter your note or remark...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _addNote,
                      icon: const Icon(Icons.note_add),
                      label: const Text('Add Note'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.royalBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Upload Document Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upload Document',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Upload secondary documents (scanned evidence, forms, affidavits)',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.mutedText,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_isUploading)
                      const Center(child: CircularProgressIndicator())
                    else
                      ElevatedButton.icon(
                        onPressed: _uploadDocument,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Upload Document'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.royalBlue,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Upload secondary documents (scanned evidence, forms, affidavits)',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.mutedText,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addNote() async {
    if (_noteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a note')));
      return;
    }

    final result = await _staffService.addCaseNote(
      caseId: widget.caseModel.id,
      note: _noteController.text.trim(),
    );

    if (result['success'] == true) {
      _noteController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Note added successfully')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Failed to add note')),
      );
    }
  }

  Future<void> _uploadDocument() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.single.path == null) {
        return;
      }

      final file = result.files.single;
      final nameController = TextEditingController(text: file.name);
      String? documentType;
      String? folder;

      final shouldUpload = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Upload Document', style: TextStyle()),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Document Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Document Type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'evidence',
                        child: Text('Evidence'),
                      ),
                      DropdownMenuItem(value: 'form', child: Text('Form')),
                      DropdownMenuItem(
                        value: 'affidavit',
                        child: Text('Affidavit'),
                      ),
                      DropdownMenuItem(
                        value: 'exhibit',
                        child: Text('Exhibit'),
                      ),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => documentType = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Folder/Category (optional)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setDialogState(
                      () => folder = value.isEmpty ? null : value,
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
                onPressed: nameController.text.isEmpty || documentType == null
                    ? null
                    : () => Navigator.pop(context, true),
                child: const Text('Upload'),
              ),
            ],
          ),
        ),
      );

      if (shouldUpload != true || documentType == null) return;

      setState(() => _isUploading = true);

      try {
        // Import storage service
        final storageService = StorageService();
        final documentUrl = await storageService.uploadCaseDocument(
          caseId: widget.caseModel.id,
          file: file,
          folder: folder,
        );

        final result = await _staffService.uploadCaseDocument(
          caseId: widget.caseModel.id,
          documentUrl: documentUrl,
          documentName: nameController.text,
          documentType: documentType,
          folder: folder,
        );

        if (result['success'] == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Document uploaded successfully')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result['message'] ?? 'Failed to upload document'),
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      } finally {
        if (mounted) {
          setState(() => _isUploading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error selecting file: $e')));
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
      case 'in_progress':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
