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
import '../../widgets/case/case_details_download_button.dart';
import '../../utils/case_details_export.dart';
import '../../utils/case_result.dart';
import '../../utils/case_status_filter.dart';
import '../../widgets/case/case_status_filter_button.dart';
import '../../widgets/common/case_description_editor.dart';
import '../../widgets/common/case_signature_pad.dart';
import '../../widgets/case/case_billing_card.dart';
import '../billing/billing_management_screen.dart'
    show openPaymentHistoryScreen;

class StaffCasesScreen extends StatefulWidget {
  const StaffCasesScreen({super.key, this.closedFolder = false});

  final bool closedFolder;

  @override
  State<StaffCasesScreen> createState() => _StaffCasesScreenState();
}

class _StaffCasesScreenState extends State<StaffCasesScreen> {
  final StaffService _staffService = StaffService();
  final StaffAuthService _staffAuthService = StaffAuthService();
  String _selectedFilter = CaseStatusFilter.active;
  String? _assignedAttorneyId;
  bool _showAllCases = false;
  late bool _viewClosed;

  @override
  void initState() {
    super.initState();
    _viewClosed = widget.closedFolder;
    _loadAttorneyId();
  }

  @override
  void didUpdateWidget(StaffCasesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.closedFolder != widget.closedFolder) {
      _viewClosed = widget.closedFolder;
    }
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
          _viewClosed
              ? 'Closed Cases'
              : (_showAllCases ? 'All Attorney Cases' : 'Assigned Cases'),
          style: TextStyle(),
        ),
        actions: [
          if (MediaQuery.of(context).size.width < 800)
            TextButton(
              onPressed: () {
                setState(() {
                  _viewClosed = !_viewClosed;
                  _selectedFilter = _viewClosed
                      ? CaseStatusFilter.completed
                      : CaseStatusFilter.active;
                });
              },
              child: Text(
                _viewClosed ? 'Assigned' : 'Closed',
                style: const TextStyle(color: AppTheme.cleanWhite),
              ),
            ),
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
          if (!_viewClosed)
            CaseStatusFilterButton(
              selected: _selectedFilter == CaseStatusFilter.all
                  ? CaseStatusFilter.active
                  : _selectedFilter,
              iconColor: AppTheme.cleanWhite,
              values: CaseStatusFilter.attorneyMyCaseValues,
              onSelected: (value) {
                setState(() => _selectedFilter = value);
              },
            ),
        ],
      ),
      body: StreamBuilder<List<CaseModel>>(
        stream: _showAllCases && _assignedAttorneyId != null
            ? _staffService.getAttorneyCases(_assignedAttorneyId!)
            : _staffService.getAssignedCases(user.uid, staffEmail: user.email),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const SizedBox.shrink();
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
          final filter = _viewClosed
              ? CaseStatusFilter.completed
              : (_selectedFilter == CaseStatusFilter.all
                  ? CaseStatusFilter.active
                  : _selectedFilter);
          final filteredCases = CaseStatusFilter.apply(allCases, filter);

          if (filteredCases.isEmpty) {
            final empty = _viewClosed
                ? 'No closed cases'
                : (_selectedFilter == CaseStatusFilter.active ||
                        _selectedFilter == CaseStatusFilter.all
                    ? 'No cases assigned yet'
                    : 'No ${CaseStatusFilter.label(_selectedFilter).toLowerCase()} cases');
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    empty,
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: filteredCases.length,
            itemBuilder: (context, index) {
              final caseModel = filteredCases[index];
              final statusColor = _getStatusColor(caseModel.status);
              final statusLabel = CaseStatusFilter.statusLabel(caseModel.status);
              final hasResult = CaseStatusFilter.isCompleted(caseModel.status) &&
                  CaseResult.label(caseModel.caseResult).isNotEmpty;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Get.to(() => StaffCaseDetailPage(caseModel: caseModel));
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Compact leading status avatar
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            _getStatusIcon(caseModel.status),
                            color: statusColor,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Case Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                caseModel.caseTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  color: AppTheme.darkText,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  // Status pill
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      statusLabel,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: statusColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (hasResult)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        CaseResult.label(caseModel.caseResult),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.darkText,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  Text(
                                    '•',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                  Text(
                                    caseModel.caseType,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.mutedText,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    '•',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                  Text(
                                    DateFormat('MMM dd, yyyy').format(caseModel.updatedAt),
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppTheme.mutedText,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF94A3B8),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _getStatusColor(String status) {
    if (CaseStatusFilter.isDraft(status)) return const Color(0xFFC9A227);
    if (CaseStatusFilter.isOpen(status)) return Colors.orange;
    if (CaseStatusFilter.isInProgress(status)) return Colors.blue;
    if (CaseStatusFilter.isCompleted(status)) return Colors.green;
    return Colors.grey;
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.pending;
      case 'under_review':
        return Icons.drafts_outlined;
      case 'accepted':
        return Icons.how_to_reg;
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
    final isClosed = CaseStatusFilter.isCompleted(widget.caseModel.status);
    final resultLabel = CaseResult.label(widget.caseModel.caseResult);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Case Details'),
        actions: [
          IconButton(
            tooltip: 'Payment History (All Transactions)',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => openPaymentHistoryScreen(
              context,
              recorderRole: 'staff',
            ),
          ),
          CaseDetailsDownloadButton(
            exportData: CaseDetailsExportData(
              caseModel: widget.caseModel,
              clientName: _client?.name ?? widget.caseModel.clientName,
              clientEmail: _client?.email ?? widget.caseModel.clientEmail,
              clientPhone: _client?.phone ?? _client?.phoneNumber ?? widget.caseModel.clientPhone,
              clientAddress: _client?.address ?? widget.caseModel.clientAddress,
            ),
          ),
        ],
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
                            CaseStatusFilter.statusLabel(
                              widget.caseModel.status,
                            ).toUpperCase(),
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
                    if (isClosed && resultLabel.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Result: $resultLabel',
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
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
                              isClosed
                                  ? 'This case is closed. You can view details only.'
                                  : 'Staff Access: You can view, add notes, and upload documents. You cannot delete or close cases.',
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
                    CaseDescriptionView(
                      plainText: widget.caseModel.caseDescription,
                      deltaJson: widget.caseModel.caseDescriptionDelta,
                    ),
                    CaseSignatureView(progress: widget.caseModel.progress),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            CaseBillingCard(
              caseModel: widget.caseModel,
              canManage: true,
              recorderRole: 'staff',
            ),

            if (!isClosed) ...[
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
    if (CaseStatusFilter.isDraft(status)) return const Color(0xFFC9A227);
    if (CaseStatusFilter.isOpen(status)) return Colors.orange;
    if (CaseStatusFilter.isInProgress(status)) return Colors.blue;
    if (CaseStatusFilter.isCompleted(status)) return Colors.green;
    return Colors.grey;
  }
}
