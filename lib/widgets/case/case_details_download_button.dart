import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../theme/app_theme.dart';
import '../../utils/case_details_export.dart';
import '../../utils/report_exporter/report_exporter.dart';

/// Download menu for case details — Word (RTF) or PDF.
class CaseDetailsDownloadButton extends StatelessWidget {
  const CaseDetailsDownloadButton({
    super.key,
    required this.exportData,
  });

  final CaseDetailsExportData exportData;

  Future<void> _downloadWord() async {
    try {
      final bytes = await buildCaseDetailsWordBytes(exportData);
      await saveBytes(
        bytes: bytes,
        filename: '${exportData.safeFilenameStem()}.rtf',
        mimeType: 'application/rtf',
      );
      Get.snackbar(
        'Downloaded',
        'Word file saved and opened.',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to download Word file: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _downloadPdf() async {
    try {
      final bytes = await buildCaseDetailsPdfBytes(exportData);
      await saveBytes(
        bytes: bytes,
        filename: '${exportData.safeFilenameStem()}.pdf',
        mimeType: 'application/pdf',
      );
      Get.snackbar(
        'Downloaded',
        'PDF saved and opened.',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to download PDF: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  void _showChoices(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Download Case Details',
                style: AppTheme.heading4.copyWith(fontSize: 18),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                exportData.caseTitle,
                style: AppTheme.bodySmall.copyWith(color: AppTheme.mutedText),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.description_outlined,
                    color: AppTheme.royalBlue),
                title: const Text('Word File'),
                subtitle: const Text('Opens in Microsoft Word or Google Docs'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _downloadWord();
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined,
                    color: AppTheme.royalBlue),
                title: const Text('PDF File'),
                subtitle: const Text('Portable document format'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _downloadPdf();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.download_outlined),
      tooltip: 'Download Case Details',
      onPressed: () => _showChoices(context),
    );
  }
}
