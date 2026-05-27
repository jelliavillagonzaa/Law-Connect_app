import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/appointment_model.dart';
import '../../services/enhanced_appointment_service.dart';
import '../../services/auth_service.dart';
import '../../services/case_service.dart';
import '../../models/case_model.dart';

class AppointmentSchedulerForm extends StatefulWidget {
  final String? clientId;
  final String? clientName;
  final String? caseId;
  final AppointmentModel? existingAppointment;
  final DateTime? initialDate;
  final TimeOfDay? initialTime;

  /// When true, [Navigator.pop] returns the new appointment id (calendar day dialog).
  final bool returnCreatedId;

  const AppointmentSchedulerForm({
    super.key,
    this.clientId,
    this.clientName,
    this.caseId,
    this.existingAppointment,
    this.initialDate,
    this.initialTime,
    this.returnCreatedId = false,
  });

  @override
  State<AppointmentSchedulerForm> createState() =>
      _AppointmentSchedulerFormState();
}

class _AppointmentSchedulerFormState extends State<AppointmentSchedulerForm> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  final EnhancedAppointmentService _appointmentService =
      EnhancedAppointmentService();
  final CaseService _caseService = CaseService();
  final AuthService _authService = AuthService();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String _appointmentType = 'meeting_office';
  String? _selectedCaseId;
  List<CaseModel> _clientCases = [];
  bool _isLoading = false;
  bool _isLoadingCases = false;

  // Reminder preferences
  bool _notifyClient = true;
  bool _notifyStaff = true;

  // Client selection for hearing in court
  String? _selectedClientId;
  String? _selectedClientName;
  List<Map<String, dynamic>> _attorneyClients = [];
  bool _isLoadingClients = false;

  // Color constants – match global attorney UI (royal blue header, light grey bg)
  static const Color primaryRed = Color(0xFF1A4D8F); // Royal Blue

  @override
  void initState() {
    super.initState();
    if (widget.existingAppointment != null) {
      final apt = widget.existingAppointment!;
      _selectedDate = apt.appointmentDateTime;
      _selectedTime = TimeOfDay.fromDateTime(apt.appointmentDateTime);
      _appointmentType = apt.appointmentType;
      _notesController.text = apt.notes ?? '';
      _selectedCaseId = apt.caseId;
      // Handle old appointment type values
      if (_appointmentType == 'in_office') {
        _appointmentType = 'meeting_office';
      }
    } else if (widget.initialDate != null) {
      final d = widget.initialDate!;
      _selectedDate = DateTime(d.year, d.month, d.day);
      _selectedTime = widget.initialTime ?? const TimeOfDay(hour: 9, minute: 0);
    } else {
      _selectedDate = DateTime.now();
      _selectedTime = TimeOfDay.now();
    }
    if (widget.clientId != null) {
      _loadClientCases();
      _selectedClientId = widget.clientId;
      _selectedClientName = widget.clientName;
    } else {
      // Load all clients for attorney (for hearing in court selection)
      _loadAttorneyClients();
    }
  }

  Future<void> _loadAttorneyClients() async {
    final currentUser = _authService.currentUser;
    if (currentUser == null) return;

    setState(() => _isLoadingClients = true);
    try {
      final clientIds = <String>{};
      final clientsMap = <String, Map<String, dynamic>>{};

      // 1. Get clients from cases
      final casesSnapshot = await FirebaseFirestore.instance
          .collection('cases')
          .where('attorneyId', isEqualTo: currentUser.uid)
          .get();

      for (var caseDoc in casesSnapshot.docs) {
        final caseData = caseDoc.data();
        final clientId = caseData['clientId'] as String?;
        if (clientId != null &&
            clientId.trim().isNotEmpty &&
            !clientIds.contains(clientId)) {
          clientIds.add(clientId);
        }
      }

      // 2. Get clients from appointments (in case there are appointments without cases)
      final appointmentsSnapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('attorneyId', isEqualTo: currentUser.uid)
          .get();

      for (var aptDoc in appointmentsSnapshot.docs) {
        final aptData = aptDoc.data();
        final clientId = aptData['clientId'] as String?;
        if (clientId != null && !clientIds.contains(clientId)) {
          clientIds.add(clientId);
        }
      }

      // 3. Get client details for all unique client IDs
      for (final clientId in clientIds) {
        if (clientId.trim().isEmpty) continue;
        try {
          final clientDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(clientId)
              .get();
          if (clientDoc.exists) {
            final clientData = clientDoc.data()!;
            final role = clientData['role'] as String?;
            // Only include users with role 'client'
            if (role == 'client') {
              // Try multiple possible field names for full name
              final name = clientData['name'] as String? ?? '';
              final fullName =
                  clientData['fullName'] as String? ??
                  clientData['full_name'] as String? ??
                  '';

              // For verified clients, prioritize fullName
              final isVerified = clientData['isVerified'] as bool? ?? false;

              // Build display name: prefer fullName, especially for verified clients
              String displayName;
              if (fullName.isNotEmpty && fullName.trim().isNotEmpty) {
                // If fullName exists, use it
                displayName = fullName.trim();
              } else if (name.isNotEmpty && name.trim().isNotEmpty) {
                // If no fullName, use name
                displayName = name.trim();
              } else {
                // Fallback
                displayName = 'Client';
              }

              // Store all information
              clientsMap[clientId] = {
                'id': clientId,
                'name': name,
                'fullName': fullName,
                'displayName': displayName,
                'email': clientData['email'] ?? '',
                'isVerified': isVerified,
              };
            }
          }
        } catch (e) {
          print('Error loading client $clientId: $e');
        }
      }

      // Sort clients by display name
      final clientsList = clientsMap.values.toList();
      clientsList.sort((a, b) {
        final nameA = (a['displayName'] as String? ?? '').toLowerCase();
        final nameB = (b['displayName'] as String? ?? '').toLowerCase();
        return nameA.compareTo(nameB);
      });

      if (mounted) {
        setState(() {
          _attorneyClients = clientsList;
          _isLoadingClients = false;
        });
      }
    } catch (e) {
      print('Error loading attorney clients: $e');
      if (mounted) {
        setState(() => _isLoadingClients = false);
      }
    }
  }

  Future<void> _loadClientCases() async {
    if (widget.clientId == null) return;
    setState(() => _isLoadingCases = true);
    try {
      _caseService.getCasesForUser(widget.clientId!, 'client').listen((cases) {
        if (mounted) {
          setState(() {
            _clientCases = cases;
            _isLoadingCases = false;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingCases = false);
      }
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        // Match schedule-appointment UI colors for the calendar popup
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            colorScheme: const ColorScheme.light(
              primary: primaryRed, // header & selected day
              onPrimary: Colors.white, // header text
              surface: Colors.white, // calendar background
              onSurface: Colors.black87,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: primaryRed, // "CANCEL" / "OK" buttons
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
      builder: (context, child) {
        // Match schedule-appointment UI colors for the time picker popup
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            colorScheme: const ColorScheme.light(
              primary: primaryRed,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: primaryRed),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _saveAppointment() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select date and time')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final appointmentDateTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      setState(() => _isLoading = false);
      return;
    }

    // Get client info
    String clientId = widget.clientId ?? _selectedClientId ?? '';
    String clientName = widget.clientName ?? _selectedClientName ?? 'Client';

    // Validate client selection for hearing in court
    if (_appointmentType == 'hearing_court' && clientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a client for court hearing'),
        ),
      );
      setState(() => _isLoading = false);
      return;
    }

    // Get case title if case is selected
    String? caseTitle;
    if (_selectedCaseId != null) {
      final caseModel = _clientCases.firstWhere(
        (c) => c.id == _selectedCaseId,
        orElse: () => _clientCases.isNotEmpty
            ? _clientCases.first
            : CaseModel(
                id: '',
                clientId: '',
                caseTitle: '',
                caseType: '',
                caseDescription: '',
                status: '',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
      );
      caseTitle = caseModel.caseTitle;
    }

    if (widget.existingAppointment != null) {
      // Update existing appointment
      final result = await _appointmentService.updateAppointment(
        widget.existingAppointment!.id,
        appointmentDateTime: appointmentDateTime,
        appointmentType: _appointmentType,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      if (mounted) {
        setState(() => _isLoading = false);
        if (result['success'] == true) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Appointment updated successfully')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['message'] ?? 'Failed to update appointment',
              ),
            ),
          );
        }
      }
    } else {
      // Create new appointment with reminder preferences
      final result = await _appointmentService.createAppointment(
        clientId: clientId,
        clientName: clientName,
        attorneyId: currentUser.uid,
        caseId: _selectedCaseId,
        caseTitle: caseTitle,
        appointmentDateTime: appointmentDateTime,
        appointmentType: _appointmentType,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        notifyClient: _notifyClient,
        notifyStaff: _notifyStaff,
      );

      if (mounted) {
        setState(() => _isLoading = false);
        if (result['success'] == true) {
          final id = (result['appointmentId'] as String?)?.trim() ?? '';
          if (widget.returnCreatedId) {
            final apt = AppointmentModel(
              id: id,
              clientId: clientId,
              clientName: clientName,
              attorneyId: currentUser.uid,
              caseId: _selectedCaseId,
              caseTitle: caseTitle,
              appointmentDateTime: appointmentDateTime,
              appointmentType: _appointmentType,
              notes: _notesController.text.trim().isEmpty
                  ? null
                  : _notesController.text.trim(),
              status: 'upcoming',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );
            Navigator.pop(context, apt);
          } else {
            Navigator.pop(context, true);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Appointment created successfully')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['message'] ?? 'Failed to create appointment',
              ),
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: primaryRed,
        title: Text(
          widget.existingAppointment != null
              ? 'Edit Appointment'
              : 'Schedule Appointment',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isWeb ? 32 : 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Date Picker
                  _buildSectionTitle('Select Date'),
                  const SizedBox(height: 8),
                  _buildDatePicker(),
                  const SizedBox(height: 24),

                  // Time Picker
                  _buildSectionTitle('Select Time'),
                  const SizedBox(height: 8),
                  _buildTimePicker(),
                  const SizedBox(height: 24),

                  // Case Selection (if client is provided)
                  if (widget.clientId != null) ...[
                    _buildSectionTitle('Related Case (Optional)'),
                    const SizedBox(height: 8),
                    _buildCaseSelector(),
                    const SizedBox(height: 24),
                  ],

                  // Appointment Type
                  _buildSectionTitle('Appointment Type'),
                  const SizedBox(height: 8),
                  _buildAppointmentTypeSelector(),
                  const SizedBox(height: 24),

                  // Client Selection (for all appointment types when no client is pre-selected)
                  if (widget.clientId == null) ...[
                    _buildSectionTitle(
                      _appointmentType == 'hearing_court'
                          ? 'Select Client *'
                          : 'Select Client (Optional)',
                    ),
                    const SizedBox(height: 8),
                    _buildClientSelector(),
                    const SizedBox(height: 24),
                  ],

                  // Reminder Preferences
                  _buildSectionTitle('Send Reminders To'),
                  const SizedBox(height: 8),
                  _buildReminderCheckboxes(),
                  const SizedBox(height: 24),

                  // Notes
                  _buildSectionTitle('Notes (Optional)'),
                  const SizedBox(height: 8),
                  _buildNotesField(),
                  const SizedBox(height: 32),

                  // Save Button
                  _buildSaveButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildDatePicker() {
    return InkWell(
      onTap: _selectDate,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: primaryRed),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _selectedDate != null
                    ? DateFormat('EEEE, MMMM dd, yyyy').format(_selectedDate!)
                    : 'Select date',
                style: TextStyle(
                  fontSize: 16,
                  color: _selectedDate != null
                      ? Colors.black87
                      : Colors.grey[600],
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[600]),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePicker() {
    return InkWell(
      onTap: _selectTime,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, color: primaryRed),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _selectedTime != null
                    ? _selectedTime!.format(context)
                    : 'Select time',
                style: TextStyle(
                  fontSize: 16,
                  color: _selectedTime != null
                      ? Colors.black87
                      : Colors.grey[600],
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[600]),
          ],
        ),
      ),
    );
  }

  Widget _buildCaseSelector() {
    if (_isLoadingCases) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_clientCases.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'No cases available for this client',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCaseId,
          hint: const Text('Select a case (optional)'),
          isExpanded: true,
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('None')),
            ..._clientCases.map(
              (caseModel) => DropdownMenuItem<String>(
                value: caseModel.id,
                child: Text(
                  caseModel.caseTitle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: (value) {
            setState(() => _selectedCaseId = value);
          },
        ),
      ),
    );
  }

  Widget _buildAppointmentTypeSelector() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTypeOption(
                'Meeting in Office',
                Icons.business,
                'meeting_office',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTypeOption(
                'Hearing in Court',
                Icons.gavel,
                'hearing_court',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildTypeOption('Phone Call', Icons.phone, 'phone_call'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTypeOption(
                'Online Meeting',
                Icons.video_call,
                'online_meeting',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildClientSelector() {
    if (_isLoadingClients) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_attorneyClients.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          children: [
            const Text(
              'No clients available',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                _loadAttorneyClients();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
              style: TextButton.styleFrom(foregroundColor: primaryRed),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _selectedClientId != null ? primaryRed : Colors.grey[300]!,
          width: _selectedClientId != null ? 2 : 1,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedClientId,
          hint: Text(
            'Select a client *',
            style: TextStyle(color: Colors.grey[600]),
          ),
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: primaryRed),
          style: const TextStyle(fontSize: 16, color: Colors.black87),
          items: _attorneyClients.map((client) {
            // Always use displayName which prioritizes fullName from Firestore
            final displayName =
                client['displayName'] as String? ??
                client['fullName'] as String? ??
                client['name'] as String? ??
                'Client';
            final isVerified = client['isVerified'] as bool? ?? false;

            return DropdownMenuItem<String>(
              value: client['id'] as String,
              child: Row(
                children: [
                  if (isVerified)
                    Icon(Icons.verified, size: 16, color: primaryRed),
                  if (isVerified) const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedClientId = value;
                final selectedClient = _attorneyClients.firstWhere(
                  (c) => c['id'] == value,
                );
                // Always use displayName which prioritizes fullName from Firestore
                _selectedClientName =
                    selectedClient['displayName'] as String? ??
                    selectedClient['fullName'] as String? ??
                    selectedClient['name'] as String? ??
                    'Client';
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildReminderCheckboxes() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Attorney always gets notified (no checkbox, just info)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: primaryRed, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Attorney (You) - Always notified',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          // Client checkbox
          CheckboxListTile(
            title: const Text('Client'),
            value: _notifyClient,
            onChanged: (value) {
              setState(() => _notifyClient = value ?? true);
            },
            activeColor: primaryRed,
            contentPadding: EdgeInsets.zero,
          ),
          // Staff checkbox
          CheckboxListTile(
            title: const Text('Staff'),
            value: _notifyStaff,
            onChanged: (value) {
              setState(() => _notifyStaff = value ?? true);
            },
            activeColor: primaryRed,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildTypeOption(String label, IconData icon, String value) {
    final isSelected = _appointmentType == value;
    return InkWell(
      onTap: () {
        setState(() {
          _appointmentType = value;
          // Reload clients if no clients loaded yet and no client is pre-selected
          if (widget.clientId == null &&
              _attorneyClients.isEmpty &&
              !_isLoadingClients) {
            _loadAttorneyClients();
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? primaryRed.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? primaryRed : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? primaryRed : Colors.grey[600],
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? primaryRed : Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesField() {
    return TextFormField(
      controller: _notesController,
      maxLines: 4,
      decoration: InputDecoration(
        hintText: 'Add any additional notes...',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryRed, width: 2),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _saveAppointment,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryRed,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Save Appointment',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}
