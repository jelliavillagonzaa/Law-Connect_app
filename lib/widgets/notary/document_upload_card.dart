import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class DocumentUploadCard extends StatelessWidget {
  final String documentName;
  final String? uploadedFileName;
  final String? uploadedFileUrl;
  final bool isUploading;
  final VoidCallback onUpload;
  final VoidCallback? onReplace;
  final VoidCallback? onView;

  const DocumentUploadCard({
    super.key,
    required this.documentName,
    this.uploadedFileName,
    this.uploadedFileUrl,
    this.isUploading = false,
    required this.onUpload,
    this.onReplace,
    this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final isUploaded = uploadedFileName != null && uploadedFileName!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUploaded ? Colors.green : Colors.grey[300]!,
          width: isUploaded ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Icon on the left
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isUploaded
                    ? Colors.green.withOpacity(0.1)
                    : Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: isUploading
                  ? const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.royalBlue),
                      ),
                    )
                  : Icon(
                      isUploaded ? Icons.check_circle : Icons.description,
                      color: isUploaded ? Colors.green : Colors.grey[600],
                      size: 24,
                    ),
            ),
            const SizedBox(width: 12),
            // Document name and uploaded file name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    documentName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isUploaded ? Colors.green[700] : Colors.black87,
                    ),
                  ),
                  if (isUploaded && uploadedFileName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      uploadedFileName!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Upload/Replace/View button
            if (isUploading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.royalBlue),
                ),
              )
            else if (isUploaded)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onView != null)
                    IconButton(
                      icon: const Icon(Icons.visibility_outlined, size: 20),
                      onPressed: onView,
                      tooltip: 'View',
                      color: AppTheme.royalBlue,
                    ),
                  ElevatedButton(
                    onPressed: onReplace ?? onUpload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[200],
                      foregroundColor: Colors.black87,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Replace',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              )
            else
              ElevatedButton.icon(
                onPressed: onUpload,
                icon: const Icon(Icons.upload, size: 18),
                label: const Text('Upload'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[200],
                  foregroundColor: Colors.black87,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

