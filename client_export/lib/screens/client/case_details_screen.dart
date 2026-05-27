import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/mock_data.dart';

class CaseDetailsScreen extends StatelessWidget {
  final String caseId;

  const CaseDetailsScreen({super.key, required this.caseId});

  @override
  Widget build(BuildContext context) {
    final caseItem = MockDataService.getCases().firstWhere(
          (c) => c.id == caseId,
          orElse: () => MockDataService.getCases().first,
        );
    final timelineItems = MockDataService.getTimelineItems();
    final documents = MockDataService.getDocuments();
    final statusUpdates = MockDataService.getStatusUpdates();
    final attorneyNotes = MockDataService.getAttorneyNotes();

    return Scaffold(
      backgroundColor: AppTheme.lightBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.navy,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Case: ${caseItem.title.length > 20 ? caseItem.title.substring(0, 20) + '...' : caseItem.title}',
          style: const TextStyle(color: Colors.white),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Case Information Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    caseItem.title,
                    style: AppTheme.heading2.copyWith(
                      color: AppTheme.navy,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Case Type: ${caseItem.type}',
                    style: AppTheme.bodyMedium.copyWith(
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Status: ${caseItem.status}',
                    style: AppTheme.bodyMedium.copyWith(
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Case Timeline
            Text(
              'Case Timeline',
              style: AppTheme.heading3.copyWith(
                color: AppTheme.navy,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildTimelineSection(timelineItems),
            const SizedBox(height: 24),

            // Case Documents
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Case Documents',
                  style: AppTheme.heading3.copyWith(
                    color: AppTheme.navy,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    // Upload document
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Upload functionality coming soon')),
                    );
                  },
                  icon: const Icon(Icons.cloud_upload, size: 18),
                  label: const Text('Upload'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.navy,
                    foregroundColor: AppTheme.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDocumentsSection(documents),
            const SizedBox(height: 24),

            // Attorney Notes
            Text(
              'Attorney Notes',
              style: AppTheme.heading3.copyWith(
                color: AppTheme.navy,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildAttorneyNotesSection(attorneyNotes),
            const SizedBox(height: 24),

            // Status Updates
            Text(
              'Status Updates',
              style: AppTheme.heading3.copyWith(
                color: AppTheme.navy,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildStatusUpdatesSection(statusUpdates),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineSection(List<MockTimelineItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: List.generate(items.length, (index) {
            final item = items[index];
            final isLast = index == items.length - 1;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Timeline line and dot
                Column(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppTheme.navy,
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (!isLast)
                      Container(
                        width: 2,
                        height: 80,
                        color: Colors.grey[300],
                        margin: const EdgeInsets.symmetric(vertical: 4),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                // Timeline content
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('yyyy-MM-dd').format(item.date),
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.title,
                          style: AppTheme.bodyMedium.copyWith(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.description,
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildDocumentsSection(List<MockDocument> documents) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: documents.length,
        separatorBuilder: (context, index) => const Divider(),
        itemBuilder: (context, index) {
          final doc = documents[index];
          IconData docIcon;
          Color docColor;
          if (doc.name.endsWith('.pdf')) {
            docIcon = Icons.picture_as_pdf;
            docColor = Colors.red;
          } else if (doc.name.endsWith('.doc') || doc.name.endsWith('.docx')) {
            docIcon = Icons.description;
            docColor = Colors.blue;
          } else if (doc.name.endsWith('.zip')) {
            docIcon = Icons.folder_zip;
            docColor = Colors.purple;
          } else {
            docIcon = Icons.insert_drive_file;
            docColor = Colors.grey;
          }

          return ListTile(
            leading: Icon(docIcon, color: docColor, size: 32),
            title: Text(
              doc.name,
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              DateFormat('yyyy-MM-dd').format(doc.uploadedAt),
              style: AppTheme.bodySmall.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.download),
              onPressed: () {
                // Download document
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Downloading ${doc.name}...')),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildAttorneyNotesSection(String notes) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        notes,
        style: AppTheme.bodyMedium.copyWith(
          color: AppTheme.textPrimary,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildStatusUpdatesSection(List<MockStatusUpdate> updates) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: updates.length,
        separatorBuilder: (context, index) => const Divider(height: 24),
        itemBuilder: (context, index) {
          final update = updates[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('MMM dd').format(update.timestamp),
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                update.description,
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
