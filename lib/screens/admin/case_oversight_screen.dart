import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/case_model.dart';
import '../../services/admin_service.dart';
import '../../services/case_service.dart';
import '../../pages/case/case_detail_page.dart';
import '../../theme/app_theme.dart';

class CaseOversightScreen extends StatefulWidget {
  final bool inline;
  /// When set (e.g. from admin dashboard stat cards), pre-selects the status filter.
  final String? initialStatusFilter;
  /// Opens Archive Storage in the admin shell after a case is archived.
  final VoidCallback? onOpenArchiveStorage;

  const CaseOversightScreen({
    super.key,
    this.inline = false,
    this.initialStatusFilter,
    this.onOpenArchiveStorage,
  });

  @override
  State<CaseOversightScreen> createState() => _CaseOversightScreenState();
}

class _CaseOversightScreenState extends State<CaseOversightScreen> {
  final AdminService _adminService = AdminService();
  final CaseService _caseService = CaseService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late String _selectedStatus;
  String _selectedFilter = 'all'; // all, assigned, unassigned, locked

  static const _statuses = {
    'all',
    'pending',
    'accepted',
    'in_progress',
    'active',
    'completed',
  };

  String _statusFromWidget() {
    final s = widget.initialStatusFilter?.trim().toLowerCase();
    if (s != null && s.isNotEmpty && _statuses.contains(s)) return s;
    return 'all';
  }

  @override
  void initState() {
    super.initState();
    _selectedStatus = _statusFromWidget();
  }

  @override
  void didUpdateWidget(CaseOversightScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialStatusFilter != oldWidget.initialStatusFilter) {
      final next = _statusFromWidget();
      if (next != _selectedStatus) {
        setState(() => _selectedStatus = next);
      }
    }
  }

  Widget _buildCaseListForSelectedStatus() {
    if (_selectedStatus == 'all') {
      return StreamBuilder<List<CaseModel>>(
        stream: _caseService.getCasesForUser('', 'admin'),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final cases = snapshot.data ?? [];
          return _buildCasesList(_filterCases(cases));
        },
      );
    }
    if (_selectedStatus == 'active') {
      return StreamBuilder<List<CaseModel>>(
        stream: _caseService.getCasesForUser('', 'admin'),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final raw = snapshot.data ?? [];
          final cases = raw
              .where(
                (c) => c.status == 'in_progress' || c.status == 'active',
              )
              .toList();
          return _buildCasesList(_filterCases(cases));
        },
      );
    }
    return StreamBuilder<List<CaseModel>>(
      stream: _caseService.getCasesByStatus(_selectedStatus),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final cases = snapshot.data ?? [];
        return _buildCasesList(_filterCases(cases));
      },
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        // Filters
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: AppTheme.borderGray,
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Status',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium!
                                .copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.mutedText,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.borderGray,
                                width: 1,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedStatus,
                                isExpanded: true,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'all',
                                    child: Text('All Status'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'pending',
                                    child: Text('Pending'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'accepted',
                                    child: Text('Accepted'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'in_progress',
                                    child: Text('In Progress'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'active',
                                    child: Text('Active (in progress or active)'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'completed',
                                    child: Text('Completed'),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() => _selectedStatus = value!);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Assignment',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium!
                                .copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.mutedText,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.borderGray,
                                width: 1,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedFilter,
                                isExpanded: true,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'all',
                                    child: Text('All Cases'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'assigned',
                                    child: Text('Assigned to Attorney'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'unassigned',
                                    child: Text('Unassigned Cases'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'locked',
                                    child: Text('Locked (Read‑only)'),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() => _selectedFilter = value!);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Case List
        Expanded(child: _buildCaseListForSelectedStatus()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();

    if (widget.inline) {
      return Column(
        children: [
          // Custom header bar for inline mode
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Row(
              children: [
                Text(
                  'Case Oversight',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Case Oversight')),
      body: body,
    );
  }

  List<CaseModel> _filterCases(List<CaseModel> cases) {
    final active = cases.where((c) => !c.isArchived).toList();
    if (_selectedFilter == 'all') return active;

    return active.where((caseModel) {
      if (_selectedFilter == 'assigned') {
        return caseModel.attorneyId != null && caseModel.attorneyId!.isNotEmpty;
      } else if (_selectedFilter == 'unassigned') {
        return caseModel.attorneyId == null || caseModel.attorneyId!.isEmpty;
      } else if (_selectedFilter == 'locked') {
        // TODO: Check if case is locked (need to add isLocked field to CaseModel)
        return false;
      }
      return true;
    }).toList();
  }

  Widget _buildCasesList(List<CaseModel> cases) {
    if (cases.isEmpty) {
      return const Center(child: Text('No cases found'));
    }

    return ListView.builder(
      itemCount: cases.length,
      itemBuilder: (context, index) {
        final caseModel = cases[index];
        return Card(
          color: Colors.white,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 1,
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _getStatusColor(caseModel.status).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getStatusIcon(caseModel.status),
                color: _getStatusColor(caseModel.status),
              ),
            ),
            title: Text(
              caseModel.caseTitle,
              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  'Type: ${caseModel.caseType}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall!
                      .copyWith(color: AppTheme.mutedText),
                ),
                Text(
                  'Status: ${caseModel.status}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall!
                      .copyWith(color: AppTheme.mutedText),
                ),
                if (caseModel.attorneyId != null)
                  FutureBuilder<DocumentSnapshot>(
                    future: _firestore
                        .collection('users')
                        .doc(caseModel.attorneyId)
                        .get(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        final data =
                            snapshot.data?.data() as Map<String, dynamic>?;
                        final attorneyName = data?['name'] ?? 'Unknown';
                        return Text(
                          'Attorney: $attorneyName',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall!
                              .copyWith(color: AppTheme.mutedText),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (action) => _handleCaseMenuAction(action, caseModel),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'view',
                  child: Row(
                    children: [
                      Icon(Icons.visibility, size: 20),
                      SizedBox(width: 8),
                      Text('View Details'),
                    ],
                  ),
                ),
                if (caseModel.attorneyId != null)
                  const PopupMenuItem(
                    value: 'reassign',
                    child: Row(
                      children: [
                        Icon(Icons.swap_horiz, size: 20),
                        SizedBox(width: 8),
                        Text('Reassign Case'),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'lock',
                  child: Row(
                    children: [
                      Icon(Icons.lock, size: 20),
                      SizedBox(width: 8),
                      Text('Lock Case'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'archive',
                  child: Row(
                    children: [
                      Icon(Icons.archive_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('Archive'),
                    ],
                  ),
                ),
              ],
            ),
            onTap: () {
              Get.to(() => CaseDetailPage(caseId: caseModel.id));
            },
          ),
        );
      },
    );
  }

  void _handleCaseMenuAction(String action, CaseModel caseModel) {
    switch (action) {
      case 'view':
        Get.to(() => CaseDetailPage(caseId: caseModel.id));
        break;
      case 'reassign':
        _showReassignDialog(caseModel);
        break;
      case 'lock':
        _showLockCaseDialog(caseModel);
        break;
      case 'archive':
        _showArchiveCaseDialog(caseModel);
        break;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.pending;
      case 'accepted':
        return Icons.check_circle_outline;
      case 'in_progress':
      case 'active':
        return Icons.work_outline;
      case 'completed':
        return Icons.check_circle;
      default:
        return Icons.folder;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'in_progress':
        return Colors.purple;
      case 'active':
        return const Color(0xFF2E5C8A);
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  void _showReassignDialog(CaseModel caseModel) async {
    // Load attorneys
    Get.dialog(
      const Center(child: CircularProgressIndicator()),
      barrierDismissible: false,
    );

    final attorneys = await _adminService.getAllAttorneys();
    Get.back(); // Close loading

    if (attorneys.isEmpty) {
      Get.snackbar(
        'Error',
        'No available attorneys found',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    String? selectedAttorneyId = caseModel.attorneyId;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Reassign Case'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Select a new attorney:'),
                const SizedBox(height: 16),
                DropdownButton<String>(
                  value: selectedAttorneyId,
                  isExpanded: true,
                  hint: const Text('Select Attorney'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Unassign (No Attorney)'),
                    ),
                    ...attorneys.map((attorney) => DropdownMenuItem<String>(
                          value: attorney['id'] as String,
                          child: Text(
                            '${attorney['name']} (${attorney['email']})',
                          ),
                        )),
                  ],
                  onChanged: (value) {
                    setState(() => selectedAttorneyId = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedAttorneyId == caseModel.attorneyId) {
                  Navigator.pop(context);
                  return;
                }

                Navigator.pop(context);

                Get.dialog(
                  const Center(child: CircularProgressIndicator()),
                  barrierDismissible: false,
                );

                try {
                  if (selectedAttorneyId == null) {
                    // Unassign case
                    await _firestore.collection('cases').doc(caseModel.id).update({
                      'attorneyId': FieldValue.delete(),
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                    await _adminService.logAction(
                      action: 'case_unassigned',
                      resourceType: 'case',
                      resourceId: caseModel.id,
                    );
                  } else {
                    await _adminService.reassignCase(
                      caseModel.id,
                      selectedAttorneyId!, // Non-null assertion safe here due to null check above
                    );
                  }

                  Get.back(); // Close loading

                  Get.snackbar(
                    'Success',
                    'Case reassigned successfully',
                    backgroundColor: Colors.green,
                    colorText: Colors.white,
                  );
                } catch (e) {
                  Get.back(); // Close loading
                  Get.snackbar(
                    'Error',
                    'Failed to reassign case: $e',
                    backgroundColor: Colors.red,
                    colorText: Colors.white,
                  );
                }
              },
              child: const Text('Reassign'),
            ),
          ],
        ),
      ),
    );
  }

  void _showArchiveCaseDialog(CaseModel caseModel) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive Case'),
        content: Text(
          'Move "${caseModel.caseTitle}" to Archive Storage? It will be hidden from Case Oversight until restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _adminService.archiveCase(caseModel.id);
                widget.onOpenArchiveStorage?.call();
                Get.snackbar(
                  'Archived',
                  'Case moved to Archive Storage',
                  backgroundColor: Colors.green,
                  colorText: Colors.white,
                );
              } catch (e) {
                Get.snackbar(
                  'Error',
                  'Failed to archive case: $e',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
              }
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }

  void _showLockCaseDialog(CaseModel caseModel) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lock Case'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter reason for locking this case:'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (reasonController.text.trim().isNotEmpty) {
                try {
                  await _adminService.lockCase(
                    caseModel.id,
                    reasonController.text.trim(),
                  );
                  Get.snackbar(
                    'Success',
                    'Case locked successfully',
                    backgroundColor: Colors.green,
                    colorText: Colors.white,
                  );
                  Navigator.pop(context);
                } catch (e) {
                  Get.snackbar(
                    'Error',
                    'Failed to lock case: $e',
                    backgroundColor: Colors.red,
                    colorText: Colors.white,
                  );
                }
              }
            },
            child: const Text('Lock'),
          ),
        ],
      ),
    );
  }
}
