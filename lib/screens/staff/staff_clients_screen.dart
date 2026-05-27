import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/staff_service.dart';
import '../../services/enhanced_appointment_service.dart';
import '../../services/staff_auth_service.dart';
import '../../models/user_model.dart';
import '../../theme/app_theme.dart';

class StaffClientsScreen extends StatefulWidget {
  const StaffClientsScreen({super.key});

  @override
  State<StaffClientsScreen> createState() => _StaffClientsScreenState();
}

class _StaffClientsScreenState extends State<StaffClientsScreen> {
  final StaffService _staffService = StaffService();
  final EnhancedAppointmentService _appointmentService = EnhancedAppointmentService();
  final StaffAuthService _staffAuthService = StaffAuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  String? _assignedAttorneyId;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadAttorneyId();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    if (_assignedAttorneyId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Clients'),
        ),
        body: const Center(child: Text('No attorney assigned')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Client Assistance'),
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search clients by name, email, or phone...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
            ),
          ),
          // Clients List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('cases')
            .where('attorneyId', isEqualTo: _assignedAttorneyId)
            .snapshots(),
        builder: (context, casesSnapshot) {
          if (casesSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (casesSnapshot.hasError) {
            return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading clients',
                          style: TextStyle(fontSize: 18, color: Colors.red),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            '${casesSnapshot.error}',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
            );
          }

          final cases = casesSnapshot.data?.docs ?? [];

                if (cases.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_outlined, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No cases found',
                          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Attorney ID: ${_assignedAttorneyId?.substring(0, 8) ?? 'N/A'}...',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Create cases with this attorney ID to see clients',
                          style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                // Extract client IDs and count cases per client
                final clientCaseMap = <String, List<Map<String, dynamic>>>{};
                for (var doc in cases) {
                  try {
                    final data = doc.data() as Map<String, dynamic>?;
                    if (data != null) {
                      final clientId = data['clientId'];
                      if (clientId != null && clientId.toString().isNotEmpty) {
                        final clientIdStr = clientId.toString();
                        clientCaseMap.putIfAbsent(clientIdStr, () => []).add({
                          'caseId': doc.id,
                          'caseTitle': data['caseTitle'] ?? 'Untitled Case',
                          'caseStatus': data['status'] ?? 'pending',
                          'caseType': data['caseType'] ?? '',
                        });
                      }
                    }
                  } catch (e) {
                    continue;
                  }
                }

                if (clientCaseMap.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                        Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No clients found',
                          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Found ${cases.length} case(s) but no client IDs',
                          style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Make sure cases have a "clientId" field',
                          style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                ],
              ),
            );
          }

                final clientIdsList = clientCaseMap.keys.toList();

          return ListView.builder(
            padding: const EdgeInsets.all(16),
                  itemCount: clientIdsList.length,
            itemBuilder: (context, index) {
                    final clientId = clientIdsList[index];
                    final clientCases = clientCaseMap[clientId]!;
                    final caseCount = clientCases.length;

              return StreamBuilder<DocumentSnapshot>(
                stream: _firestore.collection('users').doc(clientId).snapshots(),
                builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: const CircularProgressIndicator(),
                              title: const Text('Loading client...'),
                            ),
                          );
                        }

                  if (!snapshot.hasData || !snapshot.data!.exists) {
                          // Try to get client name from cases or show placeholder
                          String displayName = 'Unknown Client';
                          
                          // Try to get name from first case if available
                          if (clientCases.isNotEmpty) {
                            // Could try to get clientName from case data if stored
                            displayName = 'Client';
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: InkWell(
                              onTap: () => _showClientDetailsPlaceholder(clientId, clientCases),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          radius: 30,
                                          backgroundColor: Colors.grey[300],
                                          child: Icon(Icons.person, color: Colors.grey[600], size: 24),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                displayName,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 18,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'ID: ${clientId.substring(0, 12)}...',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Icon(Icons.info_outline, size: 14, color: Colors.orange[700]),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'User data not found',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.orange[700],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.royalBlue.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Column(
                                            children: [
                                              Text(
                                                '$caseCount',
                                                style: TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppTheme.royalBlue,
                                                ),
                                              ),
                                              Text(
                                                caseCount == 1 ? 'Case' : 'Cases',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: AppTheme.royalBlue,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    const Divider(),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [
                                        _buildActionButton(
                                          icon: Icons.folder,
                                          label: 'View Cases',
                                          color: Colors.orange,
                                          onTap: () => _showClientCasesPlaceholder(clientId, clientCases),
                                        ),
                                        _buildActionButton(
                                          icon: Icons.info,
                                          label: 'Details',
                                          color: AppTheme.royalBlue,
                                          onTap: () => _showClientDetailsPlaceholder(clientId, clientCases),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        try {
                          final clientData = snapshot.data!.data() as Map<String, dynamic>?;
                          if (clientData == null) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(
                                  radius: 30,
                                  backgroundColor: Colors.grey[300],
                                  child: Icon(Icons.person, color: Colors.grey[600]),
                                ),
                                title: Text(
                                  'Unknown Client',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      'Invalid user data',
                                      style: TextStyle(color: Colors.grey[600]),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$caseCount ${caseCount == 1 ? 'case' : 'cases'}',
                                      style: TextStyle(
                                        color: AppTheme.royalBlue,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          final client = UserModel.fromFirestore(clientData, clientId);

                          // Filter by search query
                          if (_searchQuery.isNotEmpty) {
                            final matchesSearch = client.name.toLowerCase().contains(_searchQuery) ||
                                client.email.toLowerCase().contains(_searchQuery) ||
                                (client.phoneNumber?.toLowerCase().contains(_searchQuery) ?? false);
                            if (!matchesSearch) {
                              return const SizedBox.shrink();
                            }
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: InkWell(
                              onTap: () => _showClientDetails(client, clientCases),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Avatar
                                        CircleAvatar(
                        radius: 30,
                        backgroundColor: AppTheme.royalBlue,
                        child: Text(
                          client.name.substring(0, 1).toUpperCase(),
                          style: TextStyle(
                            color: AppTheme.cleanWhite,
                            fontWeight: FontWeight.bold,
                                              fontSize: 20,
                          ),
                        ),
                      ),
                                        const SizedBox(width: 16),
                                        // Client Info
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // Name
                                              Text(
                        client.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                                                  fontSize: 18,
                        ),
                      ),
                                              const SizedBox(height: 8),
                                              // Email
                                              if (client.email.isNotEmpty)
                                                Row(
                        children: [
                                                    Icon(Icons.email, size: 16, color: Colors.grey[600]),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                              client.email,
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          color: Colors.grey[700],
                                                        ),
                                                      ),
                            ),
                                                  ],
                                                ),
                                              // Phone
                                              if (client.phoneNumber != null && client.phoneNumber!.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Icon(Icons.phone, size: 16, color: Colors.grey[600]),
                                                    const SizedBox(width: 8),
                            Text(
                              client.phoneNumber!,
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        color: Colors.grey[700],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                              // Address
                                              if (client.address != null && client.address!.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Row(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        client.address!,
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          color: Colors.grey[700],
                                                        ),
                                                      ),
                            ),
                        ],
                      ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        // Case Count Badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.royalBlue.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(20),
                            ),
                                          child: Column(
                                            children: [
                                              Text(
                                                '$caseCount',
                                                style: TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppTheme.royalBlue,
                            ),
                          ),
                                              Text(
                                                caseCount == 1 ? 'Case' : 'Cases',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: AppTheme.royalBlue,
                            ),
                          ),
                        ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    const Divider(),
                                    const SizedBox(height: 8),
                                    // Action Buttons
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [
                                        _buildActionButton(
                                          icon: Icons.edit,
                                          label: 'Update Info',
                                          color: Colors.blue,
                                          onTap: () => _showUpdateClientDialog(client),
                                        ),
                                        _buildActionButton(
                                          icon: Icons.calendar_today,
                                          label: 'Schedule',
                                          color: Colors.green,
                                          onTap: () => _showScheduleMeetingDialog(client),
                                        ),
                                        _buildActionButton(
                                          icon: Icons.folder,
                                          label: 'View Cases',
                                          color: Colors.orange,
                                          onTap: () => _showClientCases(client, clientCases),
                                        ),
                                        _buildActionButton(
                                          icon: Icons.info,
                                          label: 'Details',
                                          color: AppTheme.royalBlue,
                                          onTap: () => _showClientDetails(client, clientCases),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        } catch (e) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                radius: 30,
                                backgroundColor: Colors.red[300],
                                child: Icon(Icons.error, color: Colors.white),
                              ),
                              title: Text(
                                'Client ID: ${clientId.substring(0, 8)}...',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'Error loading client data: $e',
                                style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  );
                        }
                },
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

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showUpdateClientDialog(UserModel client) async {
    final phoneController = TextEditingController(text: client.phoneNumber ?? '');
    final emailController = TextEditingController(text: client.email);
    final addressController = TextEditingController(text: client.address ?? '');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Client Info', style: TextStyle()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
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
              final result = await _staffService.updateClientInfo(
                clientId: client.id,
                phone: phoneController.text.isEmpty ? null : phoneController.text,
                email: emailController.text.isEmpty ? null : emailController.text,
                address: addressController.text.isEmpty ? null : addressController.text,
              );

              if (result['success'] == true) {
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Client info updated successfully')),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(result['message'] ?? 'Failed to update')),
                );
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _showScheduleMeetingDialog(UserModel client) async {
    final titleController = TextEditingController();
    final notesController = TextEditingController();
    DateTime? selectedDate;
    TimeOfDay? selectedTime;
    String? appointmentType;
    String? caseId;

    // Get cases for this client
    final casesSnapshot = await _firestore
        .collection('cases')
        .where('clientId', isEqualTo: client.id)
        .where('attorneyId', isEqualTo: _assignedAttorneyId)
        .get();

    final cases = casesSnapshot.docs.map((doc) {
      final data = doc.data();
      return {'id': doc.id, 'title': data['caseTitle'] ?? 'Untitled Case'};
    }).toList();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Schedule Meeting', style: TextStyle()),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Meeting Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Meeting Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'in_office', child: Text('In Office')),
                    DropdownMenuItem(value: 'phone_call', child: Text('Phone Call')),
                    DropdownMenuItem(value: 'online_meeting', child: Text('Online Meeting')),
                  ],
                  onChanged: (value) => setDialogState(() => appointmentType = value),
                ),
                if (cases.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Related Case (optional)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(value: null, child: Text('None')),
                      ...cases.map((c) => DropdownMenuItem(
                            value: c['id'] as String,
                            child: Text(c['title'] as String),
                          )),
                    ],
                    onChanged: (value) => setDialogState(() => caseId = value),
                  ),
                ],
                const SizedBox(height: 12),
                ListTile(
                  title: Text(
                    selectedDate == null
                        ? 'Select Date'
                        : DateFormat('MMM dd, yyyy').format(selectedDate!),
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) {
                      setDialogState(() => selectedDate = date);
                    }
                  },
                ),
                ListTile(
                  title: Text(
                    selectedTime == null
                        ? 'Select Time'
                        : selectedTime!.format(context),
                  ),
                  trailing: const Icon(Icons.access_time),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (time != null) {
                      setDialogState(() => selectedTime = time);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
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
                if (titleController.text.isEmpty ||
                    selectedDate == null ||
                    selectedTime == null ||
                    appointmentType == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all required fields')),
                  );
                  return;
                }

                final appointmentDateTime = DateTime(
                  selectedDate!.year,
                  selectedDate!.month,
                  selectedDate!.day,
                  selectedTime!.hour,
                  selectedTime!.minute,
                );

                final selectedCase = cases.firstWhere(
                  (c) => c['id'] == caseId,
                  orElse: () => {'title': null},
                );

                final result = await _appointmentService.createAppointment(
                  clientId: client.id,
                  clientName: client.name,
                  attorneyId: _assignedAttorneyId,
                  caseId: caseId,
                  caseTitle: selectedCase['title'] as String?,
                  appointmentDateTime: appointmentDateTime,
                  appointmentType: appointmentType!,
                  notes: notesController.text.isEmpty ? null : notesController.text,
                  status: 'upcoming',
                );

                if (result['success'] == true) {
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Meeting scheduled for ${client.name}')),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(result['message'] ?? 'Failed to schedule meeting')),
                  );
                }
              },
              child: const Text('Schedule'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showClientCases(UserModel client, List<Map<String, dynamic>> cases) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${client.name}\'s Cases', style: TextStyle()),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: cases.length,
            itemBuilder: (context, index) {
              final caseData = cases[index];
              return ListTile(
                leading: Icon(Icons.folder, color: AppTheme.royalBlue),
                title: Text(caseData['caseTitle'] ?? 'Untitled Case'),
                subtitle: Text(
                  'Status: ${caseData['caseStatus'] ?? 'pending'}',
                  style: TextStyle(
                    color: _getStatusColor(caseData['caseStatus'] ?? 'pending'),
                  ),
                ),
                trailing: Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  // Navigate to case details if needed
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
      case 'in_progress':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'declined':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Future<void> _showClientDetails(UserModel client, List<Map<String, dynamic>> cases) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(client.name, style: TextStyle()),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Email', client.email),
              if (client.phoneNumber != null)
                _buildDetailRow('Phone', client.phoneNumber!),
              if (client.address != null)
                _buildDetailRow('Address', client.address!),
              _buildDetailRow('Status', client.isVerified ? 'Verified' : 'Not Verified'),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Cases (${cases.length})',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              ...cases.take(5).map((caseData) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.folder, size: 16, color: AppTheme.royalBlue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            caseData['caseTitle'] ?? 'Untitled Case',
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                        Chip(
                          label: Text(
                            caseData['caseStatus'] ?? 'pending',
                            style: TextStyle(fontSize: 10),
                          ),
                          backgroundColor: _getStatusColor(caseData['caseStatus'] ?? 'pending')
                              .withOpacity(0.2),
                        ),
                      ],
                    ),
                  )),
              if (cases.length > 5)
                Text(
                  '... and ${cases.length - 5} more cases',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: AppTheme.mutedText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Future<void> _showClientDetailsPlaceholder(String clientId, List<Map<String, dynamic>> cases) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Client Information'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Client ID', clientId),
              _buildDetailRow('Status', 'User data not found in users collection'),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Cases (${cases.length})',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              ...cases.take(5).map((caseData) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.folder, size: 16, color: AppTheme.royalBlue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            caseData['caseTitle'] ?? 'Untitled Case',
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                        Chip(
                          label: Text(
                            caseData['caseStatus'] ?? 'pending',
                            style: TextStyle(fontSize: 10),
                          ),
                          backgroundColor: _getStatusColor(caseData['caseStatus'] ?? 'pending')
                              .withOpacity(0.2),
                        ),
                      ],
                    ),
                  )),
              if (cases.length > 5)
                Text(
                  '... and ${cases.length - 5} more cases',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This client\'s user data is missing. Please ensure the client account exists in the users collection.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showClientCasesPlaceholder(String clientId, List<Map<String, dynamic>> cases) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Client Cases'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: cases.length,
            itemBuilder: (context, index) {
              final caseData = cases[index];
              return ListTile(
                leading: Icon(Icons.folder, color: AppTheme.royalBlue),
                title: Text(caseData['caseTitle'] ?? 'Untitled Case'),
                subtitle: Text(
                  'Status: ${caseData['caseStatus'] ?? 'pending'}',
                  style: TextStyle(
                    color: _getStatusColor(caseData['caseStatus'] ?? 'pending'),
                  ),
                ),
                trailing: Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  // Navigate to case details if needed
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
