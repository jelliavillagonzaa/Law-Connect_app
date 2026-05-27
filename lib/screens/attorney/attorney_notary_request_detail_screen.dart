import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../models/notary_request_model.dart';
import '../../services/notary_service.dart';

class AttorneyNotaryRequestDetailScreen extends StatefulWidget {
  final String requestId;

  const AttorneyNotaryRequestDetailScreen({
    super.key,
    required this.requestId,
  });

  @override
  State<AttorneyNotaryRequestDetailScreen> createState() =>
      _AttorneyNotaryRequestDetailScreenState();
}

class _AttorneyNotaryRequestDetailScreenState
    extends State<AttorneyNotaryRequestDetailScreen> {
  final NotaryService _notaryService = NotaryService();
  NotaryRequestModel? _request;
  String? _clientName;
  bool _isLoading = true;
  bool _isProcessing = false;
  final TextEditingController _declineReasonController = TextEditingController();
  DateTime? _selectedReleaseDate;
  TimeOfDay? _selectedReleaseTime;

  @override
  void initState() {
    super.initState();
    _loadRequest();
  }

  @override
  void dispose() {
    _declineReasonController.dispose();
    super.dispose();
  }

  Future<void> _loadRequest() async {
    setState(() => _isLoading = true);
    try {
      final request = await _notaryService.getNotaryRequest(widget.requestId);
      if (request != null) {
        final clientName = await _notaryService.getClientName(request.clientId);
        setState(() {
          _request = request;
          _clientName = clientName;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        Get.snackbar(
          'Error',
          'Request not found',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        Get.back();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      Get.snackbar(
        'Error',
        'Failed to load request: ${e.toString()}',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _acceptRequest() async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Accept Request'),
        content: const Text('Are you sure you want to accept this notary request?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('Accept'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);

    try {
      final result = await _notaryService.acceptNotaryRequest(widget.requestId);
      setState(() => _isProcessing = false);

      if (result['success'] == true) {
        Get.snackbar(
          'Success',
          result['message'] ?? 'Request accepted successfully',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
        _loadRequest(); // Reload to update status
      } else {
        Get.snackbar(
          'Error',
          result['message'] ?? 'Failed to accept request',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      Get.snackbar(
        'Error',
        'Failed to accept request: ${e.toString()}',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _declineRequest() async {
    if (_declineReasonController.text.trim().isEmpty) {
      Get.snackbar(
        'Validation Error',
        'Please provide a reason for declining',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Decline Request'),
        content: const Text('Are you sure you want to decline this notary request?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Decline'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);

    try {
      final result = await _notaryService.declineNotaryRequest(
        widget.requestId,
        _declineReasonController.text.trim(),
      );
      setState(() => _isProcessing = false);

      if (result['success'] == true) {
        Get.snackbar(
          'Success',
          result['message'] ?? 'Request declined',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
        _loadRequest(); // Reload to update status
      } else {
        Get.snackbar(
          'Error',
          result['message'] ?? 'Failed to decline request',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      Get.snackbar(
        'Error',
        'Failed to decline request: ${e.toString()}',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _showDeclineDialog() async {
    _declineReasonController.clear();
    await Get.dialog(
      AlertDialog(
        title: const Text('Decline Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Please provide a reason for declining this request:'),
            const SizedBox(height: 16),
            TextField(
              controller: _declineReasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Enter reason...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Get.back();
              _declineRequest();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
  }

  Future<void> _showScheduleReleaseDialog() async {
    _selectedReleaseDate = null;
    _selectedReleaseTime = null;

    await Get.dialog(
      StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Schedule Release'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  _selectedReleaseDate == null
                      ? 'Select Date'
                      : DateFormat('MMM dd, yyyy').format(_selectedReleaseDate!),
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
                    setState(() => _selectedReleaseDate = date);
                  }
                },
              ),
              ListTile(
                title: Text(
                  _selectedReleaseTime == null
                      ? 'Select Time'
                      : _selectedReleaseTime!.format(context),
                ),
                trailing: const Icon(Icons.access_time),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  if (time != null) {
                    setState(() => _selectedReleaseTime = time);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: (_selectedReleaseDate == null ||
                      _selectedReleaseTime == null)
                  ? null
                  : () async {
                      Get.back();
                      await _scheduleRelease();
                    },
              child: const Text('Schedule'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scheduleRelease() async {
    if (_selectedReleaseDate == null || _selectedReleaseTime == null) return;

    final releaseDateTime = DateTime(
      _selectedReleaseDate!.year,
      _selectedReleaseDate!.month,
      _selectedReleaseDate!.day,
      _selectedReleaseTime!.hour,
      _selectedReleaseTime!.minute,
    );

    setState(() => _isProcessing = true);

    try {
      final result = await _notaryService.scheduleRelease(
        requestId: widget.requestId,
        releaseDate: _selectedReleaseDate!,
        releaseTime: releaseDateTime,
      );
      setState(() => _isProcessing = false);

      if (result['success'] == true) {
        Get.snackbar(
          'Success',
          result['message'] ?? 'Release scheduled successfully',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
        _loadRequest(); // Reload to update
      } else {
        Get.snackbar(
          'Error',
          result['message'] ?? 'Failed to schedule release',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      Get.snackbar(
        'Error',
        'Failed to schedule release: ${e.toString()}',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _openDocument(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        Get.snackbar(
          'Error',
          'Could not open document',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to open document: ${e.toString()}',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: const Text(
            'Notary Request Details',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: AppTheme.royalBlue,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_request == null) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: const Text('Notary Request Details'),
          backgroundColor: AppTheme.royalBlue,
        ),
        body: const Center(child: Text('Request not found')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Notary Request Details',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppTheme.royalBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      _request!.status == 'pending'
                          ? Icons.pending
                          : _request!.status == 'accepted'
                              ? Icons.check_circle
                              : Icons.cancel,
                      color: _request!.status == 'pending'
                          ? Colors.orange
                          : _request!.status == 'accepted'
                              ? Colors.green
                              : Colors.red,
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _request!.status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _request!.status == 'pending'
                                  ? Colors.orange
                                  : _request!.status == 'accepted'
                                      ? Colors.green
                                      : Colors.red,
                            ),
                          ),
                          Text(
                            'Submitted: ${DateFormat('MMM dd, yyyy HH:mm').format(_request!.createdAt)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Service Info
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Service Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow('Service Type', _request!.serviceType),
                    _buildInfoRow('Client', _clientName ?? 'Loading...'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Documents
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Uploaded Documents',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...(_request!.documentsWithNames != null &&
                            _request!.documentsWithNames!.isNotEmpty
                        ? _request!.documentsWithNames!.map((doc) {
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.description),
                                title: Text(doc['name'] ?? 'Document'),
                                subtitle: doc['url'] != null
                                    ? Text(
                                        'Click to view',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      )
                                    : null,
                                trailing: doc['url'] != null
                                    ? IconButton(
                                        icon: const Icon(Icons.open_in_new),
                                        onPressed: () => _openDocument(doc['url']!),
                                      )
                                    : null,
                              ),
                            );
                          })
                        : _request!.documents.asMap().entries.map((entry) {
                            final index = entry.key;
                            final url = entry.value;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.description),
                                title: Text('Document ${index + 1}'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.open_in_new),
                                  onPressed: () => _openDocument(url),
                                ),
                              ),
                            );
                          })),
                  ],
                ),
              ),
            ),

            if (_request!.notes != null && _request!.notes!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Notes',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _request!.notes!,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (_request!.declineReason != null &&
                _request!.declineReason!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                color: Colors.red[50],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Decline Reason',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _request!.declineReason!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (_request!.releaseDate != null) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                color: Colors.green[50],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Scheduled Release',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Date: ${DateFormat('MMM dd, yyyy').format(_request!.releaseDate!)}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.green,
                        ),
                      ),
                      if (_request!.releaseTime != null)
                        Text(
                          'Time: ${DateFormat('HH:mm').format(_request!.releaseTime!)}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.green,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Action Buttons
            if (_request!.status == 'pending') ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _acceptRequest,
                      icon: const Icon(Icons.check),
                      label: const Text('Accept'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _showDeclineDialog,
                      icon: const Icon(Icons.close),
                      label: const Text('Decline'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            if (_request!.status == 'accepted') ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _showScheduleReleaseDialog,
                  icon: const Icon(Icons.calendar_today),
                  label: const Text('Schedule Release'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.royalBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],

            if (_isProcessing) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

