import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/case_service.dart';
import '../../models/case_model.dart';
import '../../models/user_model.dart';
import '../../screens/attorney/attorney_create_task_screen.dart';
import '../../widgets/maps/oroquieta_map_viewer.dart';
import '../../widgets/case/case_details_download_button.dart';
import '../../utils/case_details_export.dart';
import '../../utils/case_status_filter.dart';
import '../../utils/case_history.dart';
import '../../utils/case_result.dart';
import '../../utils/case_description_format.dart';
import '../../utils/currency.dart';
import '../../widgets/common/case_description_editor.dart';
import '../../widgets/common/case_signature_pad.dart';
import '../../widgets/case/case_billing_card.dart';
import '../../screens/billing/billing_management_screen.dart'
    show openPaymentHistoryScreen;
import '../../theme/app_theme.dart';

class CaseDetailPage extends StatefulWidget {
  final String caseId;

  const CaseDetailPage({super.key, required this.caseId});

  @override
  State<CaseDetailPage> createState() => _CaseDetailPageState();
}

class _CaseDetailPageState extends State<CaseDetailPage> {
  final CaseService _caseService = CaseService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  UserModel? _clientUser;
  UserModel? _attorneyUser;
  Map<String, dynamic>? _attorneyProfileData; // Full attorney profile data
  late Future<CaseModel?> _caseFuture;
  late final Future<String?> _roleFuture;

  @override
  void initState() {
    super.initState();
    _caseFuture = _caseService.getCase(widget.caseId);
    _roleFuture = _getUserRole();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final caseModel = await _caseService.getCase(widget.caseId);
    if (caseModel != null) {
      // Load client info
      final clientDoc = await _firestore
          .collection('users')
          .doc(caseModel.clientId)
          .get();
      if (clientDoc.exists) {
        setState(() {
          _clientUser = UserModel.fromFirestore(
            clientDoc.data()!,
            caseModel.clientId,
          );
        });
      }

      // Load attorney info if assigned
      if (caseModel.attorneyId != null) {
        final attorneyDoc = await _firestore
            .collection('users')
            .doc(caseModel.attorneyId!)
            .get();
        if (attorneyDoc.exists) {
          final attorneyData = attorneyDoc.data()!;
          setState(() {
            _attorneyUser = UserModel.fromFirestore(
              attorneyData,
              caseModel.attorneyId!,
            );
            _attorneyProfileData =
                attorneyData; // Store full profile data for additional details
          });
        }
      }

      await _syncOpenCaseFromStaffTasks(caseModel);
    }
  }

  /// If an Open case already has a staff task, treat work as started.
  Future<void> _syncOpenCaseFromStaffTasks(CaseModel caseModel) async {
    if (!CaseStatusFilter.isOpen(caseModel.status)) return;
    final existing = await _firestore
        .collection('tasks')
        .where('caseId', isEqualTo: caseModel.id)
        .limit(1)
        .get();
    if (existing.docs.isEmpty) return;
    await _caseService.updateCaseStatus(caseModel.id, 'in_progress');
    if (!mounted) return;
    setState(() {
      _caseFuture = _caseService.getCase(widget.caseId);
    });
  }

  Future<void> _updateCaseStatus(
    String newStatus, {
    String? caseResult,
  }) async {
    try {
      await _caseService.updateCaseStatus(
        widget.caseId,
        newStatus,
        caseResult: caseResult,
      );
      final movedClosed = CaseStatusFilter.isCompleted(newStatus);
      Get.snackbar(
        'Success',
        movedClosed
            ? 'Case moved to Closed cases'
            : 'Case status updated to ${CaseStatusFilter.statusLabel(newStatus)}',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
      setState(() {
        _caseFuture = _caseService.getCase(widget.caseId);
      });
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to update status: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _confirmCompleteCase() async {
    String? selected;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Mark this case completed?'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'It will leave Cases and move to Closed cases.',
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Result',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    for (final value in CaseResult.values)
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(CaseResult.label(value)),
                        value: value,
                        groupValue: selected,
                        onChanged: (v) => setLocal(() => selected = v),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: selected == null
                      ? null
                      : () => Navigator.pop(dialogContext, selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Mark completed'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null) return;
    await _updateCaseStatus('completed', caseResult: result);
  }

  Future<String?> _getUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    return userDoc.data()?['role'] as String?;
  }

  Future<void> _editCaseDetails() async {
    final caseModel = await _caseService.getCase(widget.caseId);
    if (caseModel == null || !mounted) return;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _EditCaseDetailsDialog(caseModel: caseModel),
    );

    if (result == true && mounted) {
      setState(() {
        _caseFuture = _caseService.getCase(widget.caseId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Case Details'),
        actions: [
          FutureBuilder<String?>(
            future: _roleFuture,
            builder: (context, roleSnapshot) {
              final role = roleSnapshot.data?.toLowerCase();
              if (role == null || role == 'client') {
                return const SizedBox.shrink();
              }
              return IconButton(
                tooltip: 'Payment History (All Transactions)',
                icon: const Icon(Icons.history_rounded),
                onPressed: () => openPaymentHistoryScreen(
                  context,
                  recorderRole: role,
                  recorderName: role == 'attorney' ? _attorneyUser?.name : null,
                ),
              );
            },
          ),
          FutureBuilder<CaseModel?>(
            future: _caseFuture,
            builder: (context, caseSnapshot) {
              if (!caseSnapshot.hasData || caseSnapshot.data == null) {
                return const SizedBox.shrink();
              }
              final caseModel = caseSnapshot.data!;
              return CaseDetailsDownloadButton(
                exportData: CaseDetailsExportData(
                  caseModel: caseModel,
                  clientName: _clientUser?.name,
                  clientEmail: _clientUser?.email,
                  attorneyName: _attorneyUser?.name,
                  attorneyEmail: _attorneyUser?.email,
                ),
              );
            },
          ),
          FutureBuilder<String?>(
            future: _roleFuture,
            builder: (context, roleSnapshot) {
              if (roleSnapshot.hasData) {
                final role = roleSnapshot.data;
                return FutureBuilder<CaseModel?>(
                  future: _caseFuture,
                  builder: (context, caseSnapshot) {
                    if (caseSnapshot.hasData) {
                      final caseModel = caseSnapshot.data!;
                      final isAttorney =
                          role == 'attorney' &&
                          caseModel.attorneyId ==
                              FirebaseAuth.instance.currentUser?.uid;
                      if ((isAttorney || role == 'admin') &&
                          !CaseStatusFilter.isCompleted(caseModel.status)) {
                        return IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: _editCaseDetails,
                          tooltip: 'Edit Case Details',
                        );
                      }
                    }
                    return const SizedBox.shrink();
                  },
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: FutureBuilder<CaseModel?>(
        future: _caseFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox.expand();
          }

          if (snapshot.hasError || snapshot.data == null) {
            return const Center(child: Text('Case not found'));
          }

          final caseModel = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                caseModel.caseTitle,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _getStatusColor(caseModel.status),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                CaseStatusFilter.statusLabel(
                                  caseModel.status,
                                ).toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildInfoRow('Case Type', caseModel.caseType),
                        if (caseModel.opposingParty != null &&
                            caseModel.opposingParty!.trim().isNotEmpty)
                          _buildInfoRow(
                            'Opposing Party',
                            caseModel.opposingParty!,
                          ),
                        if (CaseStatusFilter.isCompleted(caseModel.status) &&
                            CaseResult.label(caseModel.caseResult).isNotEmpty)
                          _buildInfoRow(
                            'Result',
                            CaseResult.label(caseModel.caseResult),
                          ),
                        _buildInfoRow(
                          'Created',
                          '${caseModel.createdAt.day}/${caseModel.createdAt.month}/${caseModel.createdAt.year}',
                        ),
                        _buildInfoRow(
                          'Last Updated',
                          '${caseModel.updatedAt.day}/${caseModel.updatedAt.month}/${caseModel.updatedAt.year}',
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Description',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        CaseDescriptionView(
                          plainText: caseModel.caseDescription,
                          deltaJson: caseModel.caseDescriptionDelta,
                        ),
                        if (caseModel.remarks != null &&
                            caseModel.remarks!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFFDE68A),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.notes_rounded,
                                      size: 18,
                                      color: Color(0xFFB45309),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Remarks for Review',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF92400E),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                SelectableText(
                                  caseModel.remarks!,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF78350F),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        CaseSignatureView(progress: caseModel.progress),
                      ],
                    ),
                  ),
                ),
                FutureBuilder<String?>(
                  future: _roleFuture,
                  builder: (context, roleSnapshot) {
                    final role = roleSnapshot.data?.toLowerCase();
                    final currentUid = FirebaseAuth.instance.currentUser?.uid;
                    final isClient = role == 'client' ||
                        (currentUid != null &&
                            currentUid == caseModel.clientId &&
                            role != 'attorney' &&
                            role != 'admin' &&
                            role != 'staff');
                    return CaseBillingCard(
                      caseModel: caseModel,
                      canManage: !isClient,
                      recorderRole: isClient ? 'client' : (role ?? 'staff'),
                      recorderName: role == 'attorney'
                          ? _attorneyUser?.name
                          : (isClient ? _clientUser?.name : null),
                    );
                  },
                ),
                if (_historyEvents(caseModel).isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Case History',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ..._historyEvents(caseModel).map(_buildHistoryRow),
                        ],
                      ),
                    ),
                  ),
                // User Information
                if (_clientUser != null || _attorneyUser != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Participants',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_clientUser != null)
                            ListTile(
                              leading: const Icon(Icons.person),
                              title: const Text('Client'),
                              subtitle: Text(
                                '${_clientUser!.name}\n${_clientUser!.email}',
                              ),
                            ),
                          if (_attorneyUser != null)
                            ListTile(
                              leading: const Icon(Icons.gavel),
                              title: const Text('Attorney'),
                              subtitle: Text(
                                '${_attorneyUser!.name}\n${_attorneyUser!.email}',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                // Attorney profile details — clients only
                FutureBuilder<String?>(
                  future: _roleFuture,
                  builder: (context, roleSnapshot) {
                    if (roleSnapshot.data == 'client' &&
                        _attorneyUser != null &&
                        _attorneyProfileData != null) {
                      return _buildAttorneyAdditionalDetails();
                    }
                    return const SizedBox.shrink();
                  },
                ),
                // Status Update and Create Task (for attorneys only, NOT admins)
                FutureBuilder<String?>(
                  future: _roleFuture,
                  builder: (context, roleSnapshot) {
                    if (roleSnapshot.hasData) {
                      final role = roleSnapshot.data;
                      // Only show for attorneys assigned to this case, NOT for admins
                      if (role == 'attorney' &&
                          caseModel.attorneyId ==
                              FirebaseAuth.instance.currentUser?.uid) {
                        final hasAssignedStaff = _caseHasAssignedStaff(caseModel);
                        return Column(
                          children: [
                            if (!CaseStatusFilter.isCompleted(caseModel.status) &&
                                !hasAssignedStaff)
                              _buildCreateTaskCard(caseModel),
                            ..._buildAttorneyStatusUpdate(caseModel),
                          ],
                        );
                      }
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<CaseHistoryEvent> _historyEvents(CaseModel caseModel) {
    return CaseHistory.fromCase(caseModel);
  }

  Widget _buildHistoryRow(CaseHistoryEvent event) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.circle, size: 10, color: AppTheme.royalBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (event.dateLabel.isNotEmpty)
                  Text(
                    event.dateLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.mutedText,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _caseHasAssignedStaff(CaseModel caseModel) {
    final staffId = caseModel.staffId?.trim() ?? '';
    if (staffId.isNotEmpty) return true;
    final assigned = caseModel.staffAssigned ?? const <String>[];
    return assigned.any((id) => id.trim().isNotEmpty);
  }

  Widget _buildCreateTaskCard(CaseModel caseModel) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Task Management',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AttorneyCreateTaskScreen(
                      caseId: caseModel.id,
                      caseTitle: caseModel.caseTitle,
                    ),
                  ),
                );
                if (result == true) {
                  setState(() {
                    _caseFuture = _caseService.getCase(widget.caseId);
                  });
                  Get.snackbar(
                    'Success',
                    'Task created successfully!',
                    backgroundColor: Colors.green,
                    colorText: Colors.white,
                  );
                }
              },
              icon: const Icon(Icons.add_task),
              label: const Text('New Staff Task'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.royalBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Draft → Open. Open cases move to In progress when a staff task is created.
  /// Attorney marks completed when the case is done.
  List<Widget> _buildAttorneyStatusUpdate(CaseModel caseModel) {
    final status = caseModel.status;
    if (CaseStatusFilter.isCompleted(status)) {
      return const [];
    }

    final String actionLabel;
    final String nextStatus;
    if (CaseStatusFilter.isDraft(status)) {
      actionLabel = 'Open case';
      nextStatus = CaseStatusFilter.openStoredStatus;
    } else {
      actionLabel = 'Mark completed';
      nextStatus = 'completed';
    }

    return [
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Case tracking',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Current: ${CaseStatusFilter.statusLabel(status)}',
                style: TextStyle(color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: nextStatus == 'completed'
                    ? _confirmCompleteCase
                    : () => _updateCaseStatus(nextStatus),
                style: ElevatedButton.styleFrom(
                  backgroundColor: nextStatus == 'completed'
                      ? Colors.green
                      : AppTheme.royalBlue,
                  foregroundColor: Colors.white,
                ),
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    if (CaseStatusFilter.isDraft(status)) return const Color(0xFFC9A227);
    if (CaseStatusFilter.isOpen(status)) return Colors.orange;
    if (CaseStatusFilter.isInProgress(status)) return Colors.purple;
    if (CaseStatusFilter.isCompleted(status)) return Colors.green;
    return Colors.grey;
  }

  /// Builds the Attorney Additional Details section for clients to view
  Widget _buildAttorneyAdditionalDetails() {
    final profile = _attorneyProfileData!;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 800;

    // Check if there are any additional details to show
    final hasLocation =
        (profile['officeAddress'] != null &&
            profile['officeAddress'].toString().isNotEmpty) ||
        (profile['city'] != null && profile['city'].toString().isNotEmpty) ||
        (profile['province'] != null &&
            profile['province'].toString().isNotEmpty);
    final hasBio =
        profile['bio'] != null && profile['bio'].toString().isNotEmpty;
    final hasLanguages = profile['languages'] != null;
    final hasRateInfo =
        profile['rateType'] != null || profile['consultationFee'] != null;

    if (!hasLocation && !hasBio && !hasLanguages && !hasRateInfo) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: AppTheme.cleanWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(isDesktop ? 24 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Attorney Additional Details',
              style: TextStyle(
                fontSize: isDesktop ? 22 : 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.darkText,
              ),
            ),
            const SizedBox(height: 20),
            // Location
            if (hasLocation)
              Container(
                margin: EdgeInsets.only(bottom: isDesktop ? 16 : 12),
                padding: EdgeInsets.all(isDesktop ? 18 : 16),
                decoration: BoxDecoration(
                  color: AppTheme.lightGray.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.borderGray.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: _buildLocationRow(profile, isDesktop),
              ),
            // Bio
            if (hasBio)
              Container(
                margin: EdgeInsets.only(bottom: isDesktop ? 16 : 12),
                padding: EdgeInsets.all(isDesktop ? 18 : 16),
                decoration: BoxDecoration(
                  color: AppTheme.lightGray.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.borderGray.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: _buildAdditionalInfoRow(
                  Icons.description,
                  'Bio / Introduction',
                  profile['bio'].toString(),
                  isDesktop: isDesktop,
                ),
              ),
            // Languages
            if (hasLanguages)
              Container(
                margin: EdgeInsets.only(bottom: isDesktop ? 16 : 12),
                padding: EdgeInsets.all(isDesktop ? 18 : 16),
                decoration: BoxDecoration(
                  color: AppTheme.lightGray.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.borderGray.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: _buildAdditionalInfoRow(
                  Icons.language,
                  'Languages Spoken',
                  profile['languages'] is List
                      ? (profile['languages'] as List).join(', ')
                      : profile['languages'].toString(),
                  isDesktop: isDesktop,
                ),
              ),
            // Rate Information
            if (hasRateInfo)
              Container(
                margin: EdgeInsets.only(bottom: isDesktop ? 16 : 12),
                padding: EdgeInsets.all(isDesktop ? 18 : 16),
                decoration: BoxDecoration(
                  color: AppTheme.lightGray.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.borderGray.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.royalBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.attach_money,
                        color: AppTheme.royalBlue,
                        size: isDesktop ? 24 : 20,
                      ),
                    ),
                    SizedBox(width: isDesktop ? 16 : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rate Information',
                            style: TextStyle(
                              fontSize: isDesktop ? 13 : 11,
                              color: AppTheme.mutedText,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (profile['rateType'] != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                'Rate Type: ${profile['rateType']}',
                                style: TextStyle(
                                  fontSize: isDesktop ? 16 : 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.darkText,
                                ),
                              ),
                            ),
                          if (profile['consultationFee'] != null)
                            Text(
                              'Consultation Fee: ${Currency.symbol}${profile['consultationFee']}',
                              style: TextStyle(
                                fontSize: isDesktop ? 16 : 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.darkText,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationRow(Map<String, dynamic> profile, bool isDesktop) {
    final addressParts = <String>[];
    if (profile['officeAddress'] != null &&
        profile['officeAddress'].toString().isNotEmpty) {
      addressParts.add(profile['officeAddress'].toString());
    }
    if (profile['city'] != null && profile['city'].toString().isNotEmpty) {
      addressParts.add(profile['city'].toString());
    }
    if (profile['province'] != null &&
        profile['province'].toString().isNotEmpty) {
      addressParts.add(profile['province'].toString());
    }

    final fullAddress = addressParts.join(', ');
    final hasCoordinates =
        profile['latitude'] != null && profile['longitude'] != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.location_on,
          color: AppTheme.royalBlue,
          size: isDesktop ? 28 : 24,
        ),
        SizedBox(width: isDesktop ? 20 : 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Location',
                style: TextStyle(
                  fontSize: isDesktop ? 14 : 12,
                  color: AppTheme.mutedText,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                fullAddress.isNotEmpty ? fullAddress : 'Not set',
                style: TextStyle(
                  fontSize: isDesktop ? 16 : 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.darkText,
                ),
              ),
              if (hasCoordinates || fullAddress.isNotEmpty) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OroquietaMapViewer(
                          latitude: profile['latitude'] as double?,
                          longitude: profile['longitude'] as double?,
                          locationName: fullAddress.isNotEmpty
                              ? fullAddress
                              : 'Oroquieta City, Philippines',
                          address: fullAddress.isNotEmpty
                              ? fullAddress
                              : 'Oroquieta City, Philippines',
                        ),
                      ),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.map,
                        size: isDesktop ? 18 : 16,
                        color: AppTheme.royalBlue,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'View Maps',
                        style: TextStyle(
                          fontSize: isDesktop ? 14 : 12,
                          color: AppTheme.royalBlue,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdditionalInfoRow(
    IconData icon,
    String label,
    String value, {
    required bool isDesktop,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.royalBlue, size: isDesktop ? 28 : 24),
        SizedBox(width: isDesktop ? 20 : 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: isDesktop ? 14 : 12,
                  color: AppTheme.mutedText,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: isDesktop ? 16 : 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.darkText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditCaseDetailsDialog extends StatefulWidget {
  const _EditCaseDetailsDialog({required this.caseModel});

  final CaseModel caseModel;

  @override
  State<_EditCaseDetailsDialog> createState() => _EditCaseDetailsDialogState();
}

class _EditCaseDetailsDialogState extends State<_EditCaseDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _typeController;
  late final QuillController _descriptionController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.caseModel.caseTitle);
    _typeController = TextEditingController(text: widget.caseModel.caseType);
    _descriptionController = createCaseDescriptionController(
      deltaJson: widget.caseModel.caseDescriptionDelta,
      plainFallback: widget.caseModel.caseDescription,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _typeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await CaseService().updateCaseDetails(
        caseId: widget.caseModel.id,
        caseTitle: _titleController.text.trim(),
        caseType: _typeController.text.trim(),
        caseDescription: caseDescriptionPlainText(_descriptionController),
        caseDescriptionDelta: caseDescriptionDeltaJson(_descriptionController),
      );
      if (!mounted) return;
      Get.snackbar(
        'Success',
        'Case details updated successfully',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      Get.snackbar(
        'Error',
        'Failed to update case: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Edit Case Details',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _titleController,
                          decoration: const InputDecoration(
                            labelText: 'Case Title',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                                  ? 'Please enter a title'
                                  : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _typeController,
                          decoration: const InputDecoration(
                            labelText: 'Case Type',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                                  ? 'Please enter a case type'
                                  : null,
                        ),
                        const SizedBox(height: 16),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Description *',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(height: 8),
                        CaseDescriptionEditor(
                          controller: _descriptionController,
                          minHeight: 240,
                          validator: (value) {
                            if (value.trim().isEmpty) {
                              return 'Please enter a description';
                            }
                            if (value.trim().length < 20) {
                              return 'Description must be at least 20 characters';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.royalBlue,
                        foregroundColor: Colors.white,
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
