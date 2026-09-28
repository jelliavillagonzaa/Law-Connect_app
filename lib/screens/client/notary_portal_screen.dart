import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/notary_service.dart';
import '../../services/notary_service_config.dart';
import '../../models/notary_request_model.dart';
import 'notary_service_details_screen.dart';

class NotaryPortalScreen extends StatefulWidget {
  const NotaryPortalScreen({super.key});

  @override
  State<NotaryPortalScreen> createState() => _NotaryPortalScreenState();
}

class _NotaryPortalScreenState extends State<NotaryPortalScreen> {
  final TextEditingController _searchController = TextEditingController();
  final NotaryService _notaryService = NotaryService();
  String _searchQuery = '';

  // Get notary services from config
  List<Map<String, dynamic>> get _notaryServices {
    return NotaryServiceConfig.requiredDocuments.keys.map((serviceType) {
      final requiredDocs = NotaryServiceConfig.getRequiredDocuments(serviceType);
      return {
        'title': serviceType,
        'description': NotaryServiceConfig.getDescription(serviceType),
        'requiredDocs': requiredDocs.length,
        'documents': requiredDocs,
      };
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredServices {
    if (_searchQuery.isEmpty) return _notaryServices;
    return _notaryServices
        .where((service) =>
            service['title']
                .toString()
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Notary Portal',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppTheme.royalBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
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
                hintText: 'Search notarial services...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
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
                  borderSide: const BorderSide(color: AppTheme.royalBlue, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),

          _buildMyRequests(),

          // Services List
          Expanded(
            child: _filteredServices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No services found',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredServices.length,
                    itemBuilder: (context, index) {
                      final service = _filteredServices[index];
                      return _buildServiceCard(service);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyRequests() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<List<NotaryRequestModel>>(
      stream: _notaryService.watchClientNotaryRequests(uid),
      builder: (context, snapshot) {
        final requests = snapshot.data ?? const <NotaryRequestModel>[];
        if (requests.isEmpty) return const SizedBox.shrink();
        final visible = requests.take(3).toList();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your requests',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              ...visible.map(_buildRequestStatusCard),
            ],
          ),
        );
      },
    );
  }

  String _clientOfficeVisitLine(NotaryRequestModel request) {
    final date = request.releaseDate;
    if (date == null) return 'Please go to the office.';
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

  Widget _buildRequestStatusCard(NotaryRequestModel request) {
    Color color;
    switch (request.status.toLowerCase()) {
      case 'accepted':
        color = Colors.blue;
        break;
      case 'declined':
        color = Colors.red;
        break;
      case 'completed':
        color = Colors.green;
        break;
      default:
        color = Colors.orange;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.serviceType,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (request.releaseDate != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _clientOfficeVisitLine(request),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[700],
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              request.status.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> service) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          Get.to(() => NotaryServiceDetailsScreen(
                serviceType: service['title'] as String,
              ));
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.royalBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.description,
                  color: AppTheme.royalBlue,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service['title'] as String,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${service['requiredDocs']} item(s) to bring',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              // Arrow
              Icon(
                Icons.chevron_right,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

