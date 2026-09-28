import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../models/notary_request_model.dart';
import '../../services/notary_service.dart';
import '../../services/notary_service_config.dart';

class AttorneyNotaryRequestDetailScreen extends StatefulWidget {
  final String requestId;
  final bool actingAsStaff;

  const AttorneyNotaryRequestDetailScreen({
    super.key,
    required this.requestId,
    this.actingAsStaff = false,
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
    if (!widget.actingAsStaff) return;
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Accept Request'),
        content: Text(
          widget.actingAsStaff
              ? 'Accept this notary request on behalf of your assigned attorney? The attorney stays the notary; you will be recorded as the handler.'
              : 'Are you sure you want to accept this notary request?',
        ),
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
    if (!widget.actingAsStaff) return;
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
        content: Text(
          widget.actingAsStaff
              ? 'Decline this notary request on behalf of your assigned attorney?'
              : 'Are you sure you want to decline this notary request?',
        ),
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
    final existing = _request;
    final isMove = existing?.releaseDate != null;
    if (existing?.releaseDate != null) {
      final d = existing!.releaseDate!;
      _selectedReleaseDate = DateTime(d.year, d.month, d.day);
    } else {
      _selectedReleaseDate = null;
    }
    if (existing?.releaseTime != null) {
      final t = existing!.releaseTime!;
      _selectedReleaseTime = TimeOfDay(hour: t.hour, minute: t.minute);
    } else {
      _selectedReleaseTime = null;
    }

    final purposeController = TextEditingController(
      text: existing?.scheduleMoveReason ?? '',
    );

    try {
      await Get.dialog(
        StatefulBuilder(
          builder: (context, setDialogState) {
            final canSave = _selectedReleaseDate != null &&
                _selectedReleaseTime != null &&
                (!isMove || purposeController.text.trim().isNotEmpty);
            return AlertDialog(
              title: Text(isMove ? 'Reschedule office visit' : 'Schedule office visit'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _selectedReleaseDate == null
                            ? 'Select Date'
                            : DateFormat('MMM dd, yyyy')
                                .format(_selectedReleaseDate!),
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final now = DateTime.now();
                        final first = DateTime(now.year, now.month, now.day);
                        var initial = _selectedReleaseDate ?? now;
                        if (initial.isBefore(first)) initial = first;
                        final date = await showDatePicker(
                          context: context,
                          initialDate: initial,
                          firstDate: first,
                          lastDate: now.add(const Duration(days: 365)),
                        );
                        if (date != null) {
                          setDialogState(() => _selectedReleaseDate = date);
                        }
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _selectedReleaseTime == null
                            ? 'Select Time'
                            : _selectedReleaseTime!.format(context),
                      ),
                      trailing: const Icon(Icons.access_time),
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime:
                              _selectedReleaseTime ?? TimeOfDay.now(),
                        );
                        if (time != null) {
                          setDialogState(() => _selectedReleaseTime = time);
                        }
                      },
                    ),
                    if (isMove) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: purposeController,
                        maxLines: 3,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Why are you moving this?',
                          hintText: 'Purpose / reason',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Get.back(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: !canSave
                      ? null
                      : () async {
                          final purpose = purposeController.text.trim();
                          Get.back();
                          await _scheduleRelease(moveReason: purpose);
                        },
                  child: Text(isMove ? 'Save' : 'Schedule'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      purposeController.dispose();
    }
  }

  Future<void> _scheduleRelease({String? moveReason}) async {
    if (!widget.actingAsStaff) return;
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
        moveReason: moveReason,
      );
      setState(() => _isProcessing = false);

      if (result['success'] == true) {
        final whenText = (result['whenText'] as String?)?.trim() ?? '';
        final moved = result['moved'] == true;
        await Get.dialog<void>(
          AlertDialog(
            title: Text(moved ? 'Visit moved' : 'Go to the office'),
            content: Text(
              whenText.isEmpty
                  ? (result['message'] as String? ??
                      'Please go to the office for this notary request.')
                  : moved
                      ? 'Visit moved. Please go to the office on $whenText.'
                      : 'Please go to the office on $whenText.',
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        _loadRequest();
      } else {
        Get.snackbar(
          'Error',
          result['message'] ?? 'Failed to schedule visit',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      Get.snackbar(
        'Error',
        'Failed to schedule visit: ${e.toString()}',
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
                    if (_request!.preferredDateTime != null)
                      _buildInfoRow(
                        'Preferred visit',
                        DateFormat('MMM dd, yyyy • hh:mm a')
                            .format(_request!.preferredDateTime!),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Documents to bring (no confidential uploads)
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
                      'Bring to the office',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Client will bring originals. No confidential files are stored in the app.',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 12),
                    ..._bringList().map((name) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.inventory_2_outlined,
                              size: 18,
                              color: AppTheme.royalBlue,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(name)),
                          ],
                        ),
                      );
                    }),
                    if (_hasLegacyUploads()) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Older uploaded files',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      ...(_request!.documentsWithNames != null &&
                              _request!.documentsWithNames!.isNotEmpty
                          ? _request!.documentsWithNames!.map((doc) {
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: const Icon(Icons.description),
                                  title: Text(doc['name'] ?? 'Document'),
                                  trailing: doc['url'] != null
                                      ? IconButton(
                                          icon: const Icon(Icons.open_in_new),
                                          onPressed: () =>
                                              _openDocument(doc['url']!),
                                        )
                                      : null,
                                ),
                              );
                            })
                          : _request!.documents.asMap().entries.map((entry) {
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: const Icon(Icons.description),
                                  title: Text('Document ${entry.key + 1}'),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.open_in_new),
                                    onPressed: () =>
                                        _openDocument(entry.value),
                                  ),
                                ),
                              );
                            })),
                    ],
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
                        'Go to the office',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _officeVisitInstruction(_request!),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.green,
                          height: 1.4,
                        ),
                      ),
                      if ((_request!.scheduleMoveReason ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Moved: ${_request!.scheduleMoveReason!.trim()}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.green[800],
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            if (!widget.actingAsStaff && _request!.status == 'pending') ...[
              const SizedBox(height: 24),
              Card(
                color: Colors.blue[50],
                elevation: 0,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Staff will accept or decline this request. You will receive an SMS when they decide.',
                    style: TextStyle(fontSize: 14, height: 1.4),
                  ),
                ),
              ),
            ],

            // Web keeps action buttons in the scroll body. Mobile pins them.
            if (kIsWeb) ...[
              const SizedBox(height: 24),
              ..._staffActionButtonChildren(),
              if (_isProcessing) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ],
        ),
      ),
      bottomNavigationBar: _mobileStaffBottomBar(),
    );
  }

  bool get _pinStaffActionsOnMobile {
    if (kIsWeb || !widget.actingAsStaff) return false;
    final status = _request?.status;
    return status == 'pending' || status == 'accepted';
  }

  Widget? _mobileStaffBottomBar() {
    if (!_pinStaffActionsOnMobile) return null;
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ..._staffActionButtonChildren(),
              if (_isProcessing) ...[
                const SizedBox(height: 12),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _staffActionButtonChildren() {
    if (!widget.actingAsStaff || _request == null) return const [];
    if (_request!.status == 'pending') {
      return [
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
      ];
    }
    if (_request!.status == 'accepted') {
      return [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isProcessing ? null : _showScheduleReleaseDialog,
            icon: Icon(
              _request!.releaseDate == null
                  ? Icons.calendar_today
                  : Icons.edit_calendar,
            ),
            label: Text(
              _request!.releaseDate == null
                  ? 'Schedule office visit'
                  : 'Reschedule',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.royalBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ];
    }
    return const [];
  }

  String _officeVisitInstruction(NotaryRequestModel request) {
    final date = request.releaseDate;
    if (date == null) return 'Please go to the office for this notary request.';
    final time = request.releaseTime;
    final when = time == null
        ? DateFormat('MMM dd, yyyy').format(date)
        : DateFormat('MMM dd, yyyy • hh:mm a').format(
            DateTime(
              date.year,
              date.month,
              date.day,
              time.hour,
              time.minute,
            ),
          );
    return 'Please go to the office on $when.';
  }

  bool _hasLegacyUploads() {
    final request = _request;
    if (request == null) return false;
    if (request.documentsWithNames != null &&
        request.documentsWithNames!.isNotEmpty) {
      return true;
    }
    return request.documents.isNotEmpty;
  }

  List<String> _bringList() {
    final request = _request;
    if (request == null) return const [];
    if (request.bringDocuments.isNotEmpty) return request.bringDocuments;
    return NotaryServiceConfig.getRequiredDocuments(request.serviceType);
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

