import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/notary_request_model.dart';
import '../../services/notary_service.dart';
import 'attorney_notary_request_detail_screen.dart';

class AttorneyNotaryRequestsScreen extends StatefulWidget {
  const AttorneyNotaryRequestsScreen({
    super.key,
    this.embedded = false,
    this.staffAssignedAttorneyId,
  });

  final bool embedded;
  /// When set, this screen is the staff queue for that attorney.
  final String? staffAssignedAttorneyId;

  @override
  State<AttorneyNotaryRequestsScreen> createState() =>
      _AttorneyNotaryRequestsScreenState();
}

class _AttorneyNotaryRequestsScreenState
    extends State<AttorneyNotaryRequestsScreen> {
  final NotaryService _notaryService = NotaryService();
  String _selectedStatus = 'pending';
  late final Stream<List<NotaryRequestModel>> _queue;

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'declined':
        return Colors.red;
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.pending;
      case 'accepted':
        return Icons.check_circle_outline;
      case 'declined':
        return Icons.cancel_outlined;
      case 'completed':
        return Icons.check_circle;
      default:
        return Icons.info_outline;
    }
  }

  bool get _isStaffQueue => widget.staffAssignedAttorneyId != null;

  String get _queueAttorneyId {
    final staffAid = widget.staffAssignedAttorneyId?.trim() ?? '';
    if (_isStaffQueue) return staffAid;
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  @override
  void initState() {
    super.initState();
    _queue = _notaryService.watchStaffNotaryQueue(_queueAttorneyId);
  }

  Widget _statusTabs({required bool onBlue}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(child: _buildStatusTab('pending', 'Pending', onBlue: onBlue)),
          const SizedBox(width: 8),
          Expanded(child: _buildStatusTab('accepted', 'Accepted', onBlue: onBlue)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _isStaffQueue && _queueAttorneyId.isEmpty
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No assigned attorney. Ask admin to link your account before handling notary requests.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        : StreamBuilder<List<NotaryRequestModel>>(
            stream: _queue,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading requests',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() {}),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final requests = snapshot.data ?? [];
          final filteredRequests = requests
              .where((r) => r.status.toLowerCase() == _selectedStatus)
              .toList();

          if (filteredRequests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No $_selectedStatus requests',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredRequests.length,
            itemBuilder: (context, index) {
              final request = filteredRequests[index];
              return _buildRequestCard(request);
            },
          );
        },
      );

    final body = list;

    if (widget.embedded) {
      return ColoredBox(
        color: Colors.grey[50]!,
        child: Column(
          children: [
            Container(
              color: AppTheme.royalBlue,
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
              child: _statusTabs(onBlue: true),
            ),
            if (!_isStaffQueue) _attorneyReadOnlyBanner(),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Notary',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppTheme.royalBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: _statusTabs(onBlue: true),
        ),
      ),
      body: !_isStaffQueue
          ? Column(
              children: [
                _attorneyReadOnlyBanner(),
                Expanded(child: body),
              ],
            )
          : body,
    );
  }

  Widget _attorneyReadOnlyBanner() {
    return Material(
      color: const Color(0xFFE8F1FB),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Text(
          'Staff accepts or declines notary requests. You will get an SMS with the decision and schedule.',
          style: TextStyle(fontSize: 13, color: Colors.blueGrey[800], height: 1.35),
        ),
      ),
    );
  }

  Widget _buildStatusTab(String status, String label, {required bool onBlue}) {
    final isSelected = _selectedStatus == status;
    return InkWell(
      onTap: () {
        setState(() => _selectedStatus = status);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white
              : (onBlue ? Colors.transparent : Colors.grey.shade200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected
                  ? AppTheme.royalBlue
                  : (onBlue ? Colors.white70 : Colors.black54),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRequestCard(NotaryRequestModel request) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          Get.to(
            () => AttorneyNotaryRequestDetailScreen(
              requestId: request.id,
              actingAsStaff: _isStaffQueue,
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(request.status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getStatusIcon(request.status),
                          size: 16,
                          color: _getStatusColor(request.status),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          request.status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _getStatusColor(request.status),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat('MMM dd, yyyy').format(request.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                request.serviceType,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              FutureBuilder<String>(
                future: _notaryService.getClientName(request.clientId),
                builder: (context, snapshot) {
                  return Text(
                    'Client: ${snapshot.data ?? 'Loading...'}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Icon(
                  Icons.chevron_right,
                  color: Colors.grey[400],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

