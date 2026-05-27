import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/appointment_model.dart';
import '../../services/enhanced_appointment_service.dart';
import '../../services/case_service.dart';
import '../../models/case_model.dart';

class AdminAppointmentSchedulerForm extends StatefulWidget {
  final String? clientId;
  final String? clientName;
  final String? caseId;
  final AppointmentModel? existingAppointment;

  const AdminAppointmentSchedulerForm({
    super.key,
    this.clientId,
    this.clientName,
    this.caseId,
    this.existingAppointment,
  });

  @override
  State<AdminAppointmentSchedulerForm> createState() =>
      _AdminAppointmentSchedulerFormState();
}

class _AdminAppointmentSchedulerFormState
    extends State<AdminAppointmentSchedulerForm> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  final EnhancedAppointmentService _appointmentService =
      EnhancedAppointmentService();
  final CaseService _caseService = CaseService();

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
  List<Map<String, dynamic>> _allClients = [];
  bool _isLoadingClients = false;

  // Attorney selection (optional)
  String? _selectedAttorneyId;
  String? _selectedAttorneyName;
  List<Map<String, dynamic>> _attorneys = [];
  bool _isLoadingAttorneys = false;

  // Color constants
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
      if (_appointmentType == 'in_office') {
        _appointmentType = 'meeting_office';
      }
    } else {
      _selectedDate = DateTime.now();
      _selectedTime = TimeOfDay.now();
    }
    if (widget.clientId != null) {
      _loadClientCases();
      _selectedClientId = widget.clientId;
      _selectedClientName = widget.clientName;
    } else {
      // Load all clients and attorneys for admin
      _loadAllClients();
      _loadAttorneys();
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadAllClients() async {
    setState(() => _isLoadingClients = true);
    try {
      final clientsMap = <String, Map<String, dynamic>>{};

      // Get all clients from users collection
      final clientsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'client')
          .get();

      for (var clientDoc in clientsSnapshot.docs) {
        final clientData = clientDoc.data();
        final clientId = clientDoc.id;

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
          displayName = fullName.trim();
        } else if (name.isNotEmpty && name.trim().isNotEmpty) {
          displayName = name.trim();
        } else {
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

      // Sort clients by display name
      final clientsList = clientsMap.values.toList();
      clientsList.sort((a, b) {
        final nameA = (a['displayName'] as String? ?? '').toLowerCase();
        final nameB = (b['displayName'] as String? ?? '').toLowerCase();
        return nameA.compareTo(nameB);
      });

      if (mounted) {
        setState(() {
          _allClients = clientsList;
          _isLoadingClients = false;
        });
      }
    } catch (e) {
      print('Error loading all clients: $e');
      if (mounted) {
        setState(() => _isLoadingClients = false);
      }
    }
  }

  Future<void> _loadAttorneys() async {
    setState(() => _isLoadingAttorneys = true);
    try {
      final attorneysMap = <String, Map<String, dynamic>>{};

      // Get all attorneys from users collection
      final attorneysSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'attorney')
          .get();

      for (var attorneyDoc in attorneysSnapshot.docs) {
        final attorneyData = attorneyDoc.data();
        final attorneyId = attorneyDoc.id;

        final name = attorneyData['name'] as String? ?? 'Attorney';
        final email = attorneyData['email'] as String? ?? '';

        attorneysMap[attorneyId] = {
          'id': attorneyId,
          'name': name,
          'email': email,
        };
      }

      // Sort attorneys by name
      final attorneysList = attorneysMap.values.toList();
      attorneysList.sort((a, b) {
        final nameA = (a['name'] as String? ?? '').toLowerCase();
        final nameB = (b['name'] as String? ?? '').toLowerCase();
        return nameA.compareTo(nameB);
      });

      if (mounted) {
        setState(() {
          _attorneys = attorneysList;
          _isLoadingAttorneys = false;
        });
      }
    } catch (e) {
      print('Error loading attorneys: $e');
      if (mounted) {
        setState(() => _isLoadingAttorneys = false);
      }
    }
  }

  Future<void> _loadClientCases() async {
    if (widget.clientId == null && _selectedClientId == null) return;
    setState(() => _isLoadingCases = true);
    try {
      final clientId = widget.clientId ?? _selectedClientId;
      if (clientId == null) return;

      _caseService.getCasesForUser(clientId, 'client').listen((cases) {
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
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: primaryRed,
              onPrimary: Colors.white,
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
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: primaryRed,
              onPrimary: Colors.white,
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
    if (_selectedCaseId != null && _clientCases.isNotEmpty) {
      try {
        final caseModel = _clientCases.firstWhere(
          (c) => c.id == _selectedCaseId,
        );
        caseTitle = caseModel.caseTitle;
      } catch (e) {
        // Case not found, ignore
      }
    }

    try {
      if (widget.existingAppointment != null) {
        // Update existing appointment
        await _appointmentService.updateAppointment(
          widget.existingAppointment!.id,
          appointmentDateTime: appointmentDateTime,
          appointmentType: _appointmentType,
          notes: _notesController.text.trim(),
        );
      } else {
        // Create new appointment
        // Admin needs to specify attorney - use selected or find from case
        String? attorneyId = _selectedAttorneyId;

        // If no attorney selected but case is selected, get attorney from case
        if (attorneyId == null &&
            _selectedCaseId != null &&
            _clientCases.isNotEmpty) {
          try {
            final caseModel = _clientCases.firstWhere(
              (c) => c.id == _selectedCaseId,
            );
            if (caseModel.attorneyId != null &&
                caseModel.attorneyId!.isNotEmpty) {
              attorneyId = caseModel.attorneyId;
            }
          } catch (e) {
            // Case not found, ignore
          }
        }

        await _appointmentService.createAppointment(
          clientId: clientId,
          clientName: clientName,
          attorneyId: attorneyId,
          attorneyName: _selectedAttorneyName,
          appointmentDateTime: appointmentDateTime,
          appointmentType: _appointmentType,
          notes: _notesController.text.trim(),
          caseId: _selectedCaseId,
          caseTitle: caseTitle,
          notifyClient: _notifyClient,
          notifyStaff: _notifyStaff,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.existingAppointment != null
                  ? 'Appointment updated successfully'
                  : 'Appointment created successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
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

                  // Attorney Selection (optional)
                  _buildSectionTitle('Select Attorney (Optional)'),
                  const SizedBox(height: 8),
                  _buildAttorneySelector(),
                  const SizedBox(height: 24),

                  // Case Selection (if client is selected)
                  if ((widget.clientId != null ||
                      _selectedClientId != null)) ...[
                    _buildSectionTitle('Related Case (Optional)'),
                    const SizedBox(height: 8),
                    _buildCaseSelector(),
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
            setState(() {
              _selectedCaseId = value;
              // If case is selected, try to get attorney from case
              if (value != null) {
                final caseModel = _clientCases.firstWhere((c) => c.id == value);
                if (caseModel.attorneyId != null &&
                    caseModel.attorneyId!.isNotEmpty) {
                  _selectedAttorneyId = caseModel.attorneyId;
                }
              }
            });
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

    if (_allClients.isEmpty) {
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
                _loadAllClients();
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
          items: _allClients.map((client) {
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
                final selectedClient = _allClients.firstWhere(
                  (c) => c['id'] == value,
                );
                _selectedClientName =
                    selectedClient['displayName'] as String? ??
                    selectedClient['fullName'] as String? ??
                    selectedClient['name'] as String? ??
                    'Client';
                // Load cases for selected client
                _loadClientCases();
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildAttorneySelector() {
    if (_isLoadingAttorneys) {
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedAttorneyId,
          hint: const Text('Select an attorney (optional)'),
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: primaryRed),
          style: const TextStyle(fontSize: 16, color: Colors.black87),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('None')),
            ..._attorneys.map((attorney) {
              return DropdownMenuItem<String>(
                value: attorney['id'] as String,
                child: Text(
                  attorney['name'] as String? ?? 'Attorney',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }),
          ],
          onChanged: (value) {
            setState(() {
              _selectedAttorneyId = value;
              if (value != null) {
                final selectedAttorney = _attorneys.firstWhere(
                  (a) => a['id'] == value,
                );
                _selectedAttorneyName =
                    selectedAttorney['name'] as String? ?? 'Attorney';
              } else {
                _selectedAttorneyName = null;
              }
            });
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
          // Admin always gets notified (no checkbox, just info)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: primaryRed, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Admin (You) - Always notified',
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
              _allClients.isEmpty &&
              !_isLoadingClients) {
            _loadAllClients();
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
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _saveAppointment,
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryRed,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
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
          : Text(
              widget.existingAppointment != null
                  ? 'Update Appointment'
                  : 'Schedule Appointment',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
    );
  }
}
