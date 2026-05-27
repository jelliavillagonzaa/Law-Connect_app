import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/case_service.dart';
import '../../models/case_model.dart';
import '../../models/user_model.dart';
import '../../screens/attorney/attorney_create_task_screen.dart';
import '../../widgets/maps/oroquieta_map_viewer.dart';
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

  @override
  void initState() {
    super.initState();
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
    }
  }

  Future<void> _updateCaseStatus(String newStatus) async {
    try {
      await _caseService.updateCaseStatus(widget.caseId, newStatus);
      Get.snackbar(
        'Success',
        'Case status updated to $newStatus',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
      setState(() {}); // Refresh
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to update status: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<String?> _getUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    return userDoc.data()?['role'] as String?;
  }

  Future<void> _editCaseDetails() async {
    final caseModel = await _caseService.getCase(widget.caseId);
    if (caseModel == null) return;

    final titleController = TextEditingController(text: caseModel.caseTitle);
    final descriptionController = TextEditingController(
      text: caseModel.caseDescription,
    );
    final typeController = TextEditingController(text: caseModel.caseType);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Case Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Case Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: typeController,
                decoration: const InputDecoration(
                  labelText: 'Case Type',
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
                maxLines: 5,
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
    );

    if (result == true) {
      try {
        await _caseService.updateCaseDetails(
          caseId: widget.caseId,
          caseTitle: titleController.text.trim(),
          caseDescription: descriptionController.text.trim(),
          caseType: typeController.text.trim(),
        );
        Get.snackbar(
          'Success',
          'Case details updated successfully',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
        setState(() {}); // Refresh the page
      } catch (e) {
        Get.snackbar(
          'Error',
          'Failed to update case: $e',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Case Details'),
        actions: [
          FutureBuilder<String?>(
            future: _getUserRole(),
            builder: (context, roleSnapshot) {
              if (roleSnapshot.hasData) {
                final role = roleSnapshot.data;
                return FutureBuilder<CaseModel?>(
                  future: _caseService.getCase(widget.caseId),
                  builder: (context, caseSnapshot) {
                    if (caseSnapshot.hasData) {
                      final caseModel = caseSnapshot.data!;
                      final isAttorney =
                          role == 'attorney' &&
                          caseModel.attorneyId ==
                              FirebaseAuth.instance.currentUser?.uid;
                      if (isAttorney || role == 'admin') {
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
        future: _caseService.getCase(widget.caseId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
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
                                caseModel.status.toUpperCase(),
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
                        Text(
                          caseModel.caseDescription,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
                if (caseModel.progress != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Progress Updates',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...caseModel.progress!.entries.map((entry) {
                            return ListTile(
                              leading: const Icon(Icons.update),
                              title: Text(entry.key),
                              subtitle: Text(entry.value.toString()),
                            );
                          }),
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
                // Attorney Additional Details (for clients to view)
                if (_attorneyUser != null && _attorneyProfileData != null)
                  _buildAttorneyAdditionalDetails(),
                // Status Update and Create Task (for attorneys only, NOT admins)
                FutureBuilder<String?>(
                  future: _getUserRole(),
                  builder: (context, roleSnapshot) {
                    if (roleSnapshot.hasData) {
                      final role = roleSnapshot.data;
                      // Only show for attorneys assigned to this case, NOT for admins
                      if (role == 'attorney' &&
                          caseModel.attorneyId ==
                              FirebaseAuth.instance.currentUser?.uid) {
                        return Column(
                          children: [
                            // Create Task Button
                            Card(
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
                                            builder: (_) =>
                                                AttorneyCreateTaskScreen(
                                                  caseId: caseModel.id,
                                                  caseTitle:
                                                      caseModel.caseTitle,
                                                ),
                                          ),
                                        );
                                        if (result == true) {
                                          // Task created successfully
                                          Get.snackbar(
                                            'Success',
                                            'Task created successfully!',
                                            backgroundColor: Colors.green,
                                            colorText: Colors.white,
                                          );
                                        }
                                      },
                                      icon: const Icon(Icons.add_task),
                                      label: const Text(
                                        'Create Task for Staff',
                                      ),
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
                            ),
                            const SizedBox(height: 16),
                            // Status Update
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Update Status',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (caseModel.status != 'accepted')
                                          ElevatedButton(
                                            onPressed: () =>
                                                _updateCaseStatus('accepted'),
                                            child: const Text(
                                              'Mark as Accepted',
                                            ),
                                          ),
                                        if (caseModel.status != 'in_progress')
                                          ElevatedButton(
                                            onPressed: () => _updateCaseStatus(
                                              'in_progress',
                                            ),
                                            child: const Text(
                                              'Mark as In Progress',
                                            ),
                                          ),
                                        if (caseModel.status != 'completed')
                                          ElevatedButton(
                                            onPressed: () =>
                                                _updateCaseStatus('completed'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                            ),
                                            child: const Text(
                                              'Mark as Completed',
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
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
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'in_progress':
        return Colors.purple;
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
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
                              'Consultation Fee: ₱${profile['consultationFee']}',
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
