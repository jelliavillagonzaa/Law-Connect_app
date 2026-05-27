import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/staff_service.dart';
import '../../services/staff_auth_service.dart';
import '../../services/storage_service.dart';
import '../../models/case_model.dart';
import '../../theme/app_theme.dart';

class StaffDocumentsScreen extends StatefulWidget {
  const StaffDocumentsScreen({super.key});

  @override
  State<StaffDocumentsScreen> createState() => _StaffDocumentsScreenState();
}

class _StaffDocumentsScreenState extends State<StaffDocumentsScreen> {
  final StaffService _staffService = StaffService();
  final StorageService _storageService = StorageService();
  final StaffAuthService _staffAuthService = StaffAuthService();
  String? _selectedCaseId;
  bool _isUploading = false;
  String? _assignedAttorneyId;
  bool _showAllCases = false;

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
        title: Text('Document Management', style: TextStyle()),
        actions: [
          if (_assignedAttorneyId != null)
            IconButton(
              icon: Icon(
                _showAllCases ? Icons.assignment_ind : Icons.assignment,
                color: AppTheme.cleanWhite,
              ),
              onPressed: () {
                setState(() {
                  _showAllCases = !_showAllCases;
                  _selectedCaseId = null; // Reset selection when switching
                });
              },
              tooltip: _showAllCases
                  ? 'Show Only Assigned Cases'
                  : 'Show All Attorney Cases',
            ),
          if (_isUploading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.upload_file),
              onPressed: () => _showUploadDialog(),
            ),
        ],
      ),
      body: Column(
        children: [
          // Case Selector
          Container(
            padding: const EdgeInsets.all(16),
            color: AppTheme.lightGray,
            child: StreamBuilder<List<CaseModel>>(
              stream: _showAllCases && _assignedAttorneyId != null
                  ? _staffService.getAttorneyCases(_assignedAttorneyId!)
                  : _staffService.getAssignedCases(user.uid),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox.shrink();
                }

                final cases = snapshot.data ?? [];
                if (cases.isEmpty) {
                  return Text(
                    'No cases assigned',
                    style: TextStyle(),
                  );
                }

                return DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: 'Select Case',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: AppTheme.cleanWhite,
                  ),
                  value: _selectedCaseId ?? cases.first.id,
                  items: cases.map((caseModel) {
                    return DropdownMenuItem(
                      value: caseModel.id,
                      child: Text(caseModel.caseTitle),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedCaseId = value);
                  },
                );
              },
            ),
          ),

          // Documents List
          Expanded(
            child: _selectedCaseId == null
                ? Center(
                    child: Text(
                      'Select a case to view documents',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  )
                : StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('cases')
                        .doc(_selectedCaseId!)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError || !snapshot.hasData) {
                        return Center(
                          child: Text(
                            'Error loading documents',
                            style: TextStyle(),
                          ),
                        );
                      }

                      final caseData =
                          snapshot.data!.data() as Map<String, dynamic>;
                      final documents =
                          caseData['documents'] as List<dynamic>? ?? [];

                      if (documents.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.folder_open,
                                size: 64,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No documents uploaded yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      // Group documents by folder
                      final Map<String, List<Map<String, dynamic>>>
                      groupedDocs = {};
                      for (var doc in documents) {
                        final folder =
                            (doc as Map<String, dynamic>)['folder']
                                as String? ??
                            'Uncategorized';
                        groupedDocs.putIfAbsent(folder, () => []).add(doc);
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: groupedDocs.length,
                        itemBuilder: (context, folderIndex) {
                          final folder = groupedDocs.keys.toList()[folderIndex];
                          final folderDocs = groupedDocs[folder]!;

                          final topPadding = folderIndex > 0 ? 16.0 : 0.0;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (groupedDocs.length > 1) ...[
                                Padding(
                                  padding: EdgeInsets.only(
                                    bottom: 8,
                                    top: topPadding,
                                  ),
                                  child: Text(
                                    folder,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.royalBlue,
                                    ),
                                  ),
                                ),
                              ],
                              ...folderDocs.map(
                                (doc) => Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: AppTheme.royalBlue,
                                      child: Icon(
                                        _getDocumentIcon(doc['type']),
                                        color: AppTheme.cleanWhite,
                                      ),
                                    ),
                                    title: Text(
                                      doc['name'] ?? 'Document',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (doc['type'] != null)
                                          Text(
                                            'Type: ${doc['type']}',
                                            style: TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        if (doc['uploadedAt'] != null)
                                          Text(
                                            'Uploaded: ${DateFormat('MMM dd, yyyy').format((doc['uploadedAt'] as Timestamp).toDate())}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.mutedText,
                                            ),
                                          ),
                                        Row(
                                          children: [
                                            if (doc['uploadedByRole'] ==
                                                'staff')
                                              Chip(
                                                label: Text(
                                                  'Staff Upload',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                  ),
                                                ),
                                                backgroundColor:
                                                    AppTheme.lightGray,
                                              ),
                                            if (doc['type'] != null)
                                              Chip(
                                                label: Text(
                                                  doc['type'],
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                  ),
                                                ),
                                                backgroundColor: AppTheme
                                                    .royalBlue
                                                    .withOpacity(0.2),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.download),
                                      onPressed: () {
                                        // Open document URL
                                        if (doc['url'] != null) {
                                          // Use url_launcher to open the document
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Opening document: ${doc['name']}',
                                              ),
                                              action: SnackBarAction(
                                                label: 'Copy URL',
                                                onPressed: () {
                                                  // Copy URL to clipboard
                                                },
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  IconData _getDocumentIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'evidence':
        return Icons.photo;
      case 'form':
        return Icons.description;
      case 'affidavit':
        return Icons.article;
      case 'contract':
        return Icons.assignment;
      default:
        return Icons.insert_drive_file;
    }
  }

  Future<void> _showUploadDialog() async {
    if (_selectedCaseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a case first')),
      );
      return;
    }

    final nameController = TextEditingController();
    String? documentType;
    String? folder;
    PlatformFile? selectedFile;

    await showDialog(
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
                      value: 'contract',
                      child: Text('Contract'),
                    ),
                    DropdownMenuItem(value: 'exhibit', child: Text('Exhibit')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => documentType = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Folder/Category (optional)',
                    hintText: 'e.g., Exhibits, Affidavits, Evidence',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setDialogState(
                    () => folder = value.isEmpty ? null : value,
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    FilePickerResult? result = await FilePicker.platform
                        .pickFiles(type: FileType.any, allowMultiple: false);

                    if (result != null && result.files.single.path != null) {
                      setDialogState(() {
                        selectedFile = result.files.single;
                        if (nameController.text.isEmpty) {
                          nameController.text = selectedFile!.name;
                        }
                      });
                    }
                  },
                  icon: const Icon(Icons.file_upload),
                  label: Text(
                    selectedFile == null ? 'Select File' : selectedFile!.name,
                  ),
                ),
                if (selectedFile != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Selected: ${selectedFile!.name}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed:
                  selectedFile == null ||
                      nameController.text.isEmpty ||
                      documentType == null
                  ? null
                  : () async {
                      Navigator.pop(context);
                      await _uploadDocument(
                        file: selectedFile!,
                        documentName: nameController.text,
                        documentType: documentType!,
                        folder: folder,
                      );
                    },
              child: const Text('Upload'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadDocument({
    required PlatformFile file,
    required String documentName,
    required String documentType,
    String? folder,
  }) async {
    if (_selectedCaseId == null) return;

    setState(() => _isUploading = true);

    try {
      // Upload to Firebase Storage
      final documentUrl = await _storageService.uploadCaseDocument(
        caseId: _selectedCaseId!,
        file: file,
        folder: folder,
      );

      // Add document reference to case
      final result = await _staffService.uploadCaseDocument(
        caseId: _selectedCaseId!,
        documentUrl: documentUrl,
        documentName: documentName,
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
        ).showSnackBar(SnackBar(content: Text('Error uploading document: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }
}
