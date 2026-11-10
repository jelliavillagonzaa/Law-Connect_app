import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';
import '../../services/enhanced_appointment_service.dart';
import '../../services/auth_service.dart';
import '../../utils/currency.dart';
import '../../widgets/maps/oroquieta_map_viewer.dart';
import '../../widgets/client/attorney_slot_picker.dart';
import '../../widgets/common/schedule_full_dialog.dart';
import '../../models/user_model.dart';

/// Step 2 of the client appointment flow:
/// After selecting an attorney, the client fills in preferred date/time/type.
class RequestAppointmentScreen extends StatefulWidget {
  final String attorneyId;
  final String attorneyName;

  const RequestAppointmentScreen({
    super.key,
    required this.attorneyId,
    required this.attorneyName,
  });

  @override
  State<RequestAppointmentScreen> createState() =>
      _RequestAppointmentScreenState();
}

class _RequestAppointmentScreenState extends State<RequestAppointmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _appointmentService = EnhancedAppointmentService();
  final _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DateTime? _selectedSlot;
  String _selectedType = 'Online Meeting';
  final TextEditingController _notesController = TextEditingController();
  bool _isSubmitting = false;
  Map<String, dynamic>? _attorneyProfileData;
  bool _isLoadingProfile = false;

  @override
  void initState() {
    super.initState();
    _loadAttorneyProfile();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadAttorneyProfile() async {
    try {
      DocumentSnapshot<Map<String, dynamic>> attorneyDoc;
      final ref = _firestore.collection('users').doc(widget.attorneyId);
      try {
        attorneyDoc = await ref
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 1));
        if (!attorneyDoc.exists) {
          attorneyDoc = await ref.get().timeout(const Duration(seconds: 1));
        }
      } catch (_) {
        attorneyDoc = await ref.get().timeout(const Duration(seconds: 1));
      }
      if (attorneyDoc.exists && mounted) {
        setState(() {
          _attorneyProfileData = attorneyDoc.data();
          _isLoadingProfile = false;
        });
      } else {
        setState(() {
          _isLoadingProfile = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingProfile = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final user = _authService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in to request an appointment.'),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an open date and time.')),
      );
      return;
    }

    final dateTime = _selectedSlot!;

    setState(() {
      _isSubmitting = true;
    });

    try {
      var clientName = '';
      try {
        final profileDoc = await _firestore
            .collection('users')
            .doc(user.uid)
            .get();
        if (profileDoc.exists && profileDoc.data() != null) {
          final data = profileDoc.data()!;
          final resolved = UserModel.resolveDisplayName(data).trim();
          if (resolved.isNotEmpty &&
              !resolved.contains('@') &&
              resolved.toLowerCase() != 'user' &&
              resolved.toLowerCase() != 'client' &&
              (resolved.contains(' ') || !RegExp(r'\d{3,}').hasMatch(resolved))) {
            clientName = resolved;
          }
        }
      } catch (_) {}

      // If clientName not found or looks like an email/username, check pending_signups
      if (clientName.isEmpty ||
          clientName.contains('@') ||
          (!clientName.contains(' ') && RegExp(r'\d{3,}').hasMatch(clientName))) {
        try {
          Map<String, dynamic>? psData;
          final userEmail = user.email?.trim().toLowerCase() ?? '';
          if (userEmail.isNotEmpty) {
            final psDoc = await _firestore
                .collection('pending_signups')
                .doc(userEmail)
                .get();
            if (psDoc.exists && psDoc.data() != null) {
              psData = psDoc.data();
            }
          }
          if (psData == null) {
            final psSnap = await _firestore
                .collection('pending_signups')
                .where('userId', isEqualTo: user.uid)
                .limit(1)
                .get();
            if (psSnap.docs.isNotEmpty) {
              psData = psSnap.docs.first.data();
            }
          }
          if (psData != null) {
            final first = (psData['firstName'] ?? '').toString().trim();
            final middle = (psData['middleName'] ?? '').toString().trim();
            final last = (psData['lastName'] ?? '').toString().trim();
            final composed = [first, middle, last].where((s) => s.isNotEmpty).join(' ');
            if (composed.isNotEmpty) {
              clientName = composed;
              // Also heal the users document for the future
              unawaited(_firestore.collection('users').doc(user.uid).set({
                'firstName': first,
                if (middle.isNotEmpty) 'middleName': middle,
                'lastName': last,
                'name': composed,
                'fullName': composed,
              }, SetOptions(merge: true)));
            }
          }
        } catch (_) {}
      }

      // If still empty, check user.displayName
      if (clientName.isEmpty && user.displayName != null && user.displayName!.trim().isNotEmpty) {
        final dn = user.displayName!.trim();
        if (!dn.contains('@') && (dn.contains(' ') || !RegExp(r'\d{3,}').hasMatch(dn))) {
          clientName = dn;
        }
      }

      // If still empty, format cleanly without numbers or @domain - NEVER save raw email
      if (clientName.isEmpty || clientName.contains('@')) {
        final emailPrefix = (user.email ?? 'Client').split('@').first.replaceAll(RegExp(r'\d+$'), '');
        final clean = emailPrefix
            .split(RegExp(r'[._\s]+'))
            .where((w) => w.isNotEmpty)
            .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
            .join(' ')
            .trim();
        clientName = clean.isNotEmpty ? clean : 'Client';
      }

      final result = await _appointmentService.createAppointment(
        clientId: user.uid,
        clientName: clientName,
        attorneyId: widget.attorneyId,
        attorneyName: widget.attorneyName,
        appointmentDateTime: dateTime,
        // Map human-readable labels to internal codes used elsewhere.
        appointmentType: _selectedType == 'In-office Meeting'
            ? 'in_office'
            : _selectedType == 'Phone Call'
            ? 'phone_call'
            : 'online_meeting',
        notes: _notesController.text.trim().isEmpty
            ? 'Client requested an appointment via app.'
            : _notesController.text.trim(),
        status: 'pending',
      );

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Appointment request submitted successfully.'),
          ),
        );
        // Pop back to previous screen (usually dashboard or appointments)
        Get.back(result: true);
      } else if (EnhancedAppointmentService.isScheduleFull(result)) {
        await showScheduleFullDialog(context, date: dateTime);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message'] ?? 'Failed to submit appointment request.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: AppTheme.lightBackground,
      appBar: AppBar(title: const Text('Request Appointment')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isWeb ? 600 : double.infinity),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'New Appointment Request',
                        style: AppTheme.heading3.copyWith(
                          color: AppTheme.royalBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This is a consultation with ${widget.attorneyName}, '
                        'not a notary visit. Choose when and how you want to meet. '
                        'The attorney confirms it. To notarize a document, use '
                        'Notary Portal on the Dashboard.',
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildAttorneyHeader(),
                      if (_attorneyProfileData != null && !_isLoadingProfile) ...[
                        const SizedBox(height: 12),
                        _buildAttorneyAdditionalDetails(),
                      ],
                      const SizedBox(height: 24),
                      AttorneySlotPicker(
                        attorneyId: widget.attorneyId,
                        selectedSlot: _selectedSlot,
                        onSlotChanged: (slot) {
                          setState(() => _selectedSlot = slot);
                        },
                      ),
                      const SizedBox(height: 16),

                      // Type dropdown
                      Text(
                        'Appointment Type',
                        style: AppTheme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _selectedType,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Online Meeting',
                            child: Text('Online Meeting'),
                          ),
                          DropdownMenuItem(
                            value: 'Phone Call',
                            child: Text('Phone Call'),
                          ),
                          DropdownMenuItem(
                            value: 'In-Office Meeting',
                            child: Text('In-Office Meeting'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedType = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      // Notes
                      Text(
                        'What do you want to discuss?',
                        style: AppTheme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _notesController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText:
                              'Example: a contract question, a case update, or a family matter.',
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.royalBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Submit Request',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttorneyHeader() {
    final name = widget.attorneyName.trim().isEmpty
        ? 'Attorney'
        : widget.attorneyName.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppTheme.royalBlue.withOpacity(0.1),
            child: Text(
              name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: AppTheme.royalBlue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTheme.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your request goes to this attorney.',
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the Attorney Additional Details section
  Widget _buildAttorneyAdditionalDetails() {
    final profile = _attorneyProfileData!;
    final isWeb = MediaQuery.of(context).size.width > 600;

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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.lightGray.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.borderGray.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attorney Information',
            style: TextStyle(
              fontSize: isWeb ? 18 : 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.darkText,
            ),
          ),
          const SizedBox(height: 12),
          // Location
          if (hasLocation) _buildLocationInfo(profile, isWeb),
          if (hasLocation && (hasBio || hasLanguages || hasRateInfo))
            const SizedBox(height: 12),
          // Bio
          if (hasBio)
            _buildInfoItem(
              Icons.description,
              'Bio',
              profile['bio'].toString(),
              isWeb,
            ),
          if (hasBio && (hasLanguages || hasRateInfo))
            const SizedBox(height: 12),
          // Languages
          if (hasLanguages)
            _buildInfoItem(
              Icons.language,
              'Languages',
              profile['languages'] is List
                  ? (profile['languages'] as List).join(', ')
                  : profile['languages'].toString(),
              isWeb,
            ),
          if (hasLanguages && hasRateInfo) const SizedBox(height: 12),
          // Rate Information
          if (hasRateInfo) _buildRateInfo(profile, isWeb),
        ],
      ),
    );
  }

  Widget _buildLocationInfo(Map<String, dynamic> profile, bool isWeb) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.location_on, color: AppTheme.royalBlue, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                fullAddress.isNotEmpty ? fullAddress : 'Not set',
                style: TextStyle(
                  fontSize: isWeb ? 14 : 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.darkText,
                ),
              ),
            ),
          ],
        ),
        if (hasCoordinates || fullAddress.isNotEmpty) ...[
          const SizedBox(height: 6),
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
                Icon(Icons.map, size: 16, color: AppTheme.royalBlue),
                const SizedBox(width: 4),
                Text(
                  'View Maps',
                  style: TextStyle(
                    fontSize: isWeb ? 13 : 12,
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
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value, bool isWeb) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.royalBlue, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: isWeb ? 12 : 11,
                  color: AppTheme.mutedText,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: isWeb ? 14 : 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.darkText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRateInfo(Map<String, dynamic> profile, bool isWeb) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.attach_money, color: AppTheme.royalBlue, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rate Information',
                style: TextStyle(
                  fontSize: isWeb ? 12 : 11,
                  color: AppTheme.mutedText,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              if (profile['rateType'] != null)
                Text(
                  'Rate Type: ${profile['rateType']}',
                  style: TextStyle(
                    fontSize: isWeb ? 14 : 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.darkText,
                  ),
                ),
              if (profile['consultationFee'] != null)
                Text(
                  'Consultation Fee: ${Currency.symbol}${profile['consultationFee']}',
                  style: TextStyle(
                    fontSize: isWeb ? 14 : 13,
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
