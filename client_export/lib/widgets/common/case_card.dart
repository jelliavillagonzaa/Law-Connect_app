import 'package:flutter/material.dart';
import '../../models/case_model.dart';
import '../../theme/app_theme.dart';

class CaseCard extends StatelessWidget {
  final CaseModel caseModel;
  final VoidCallback? onTap;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  const CaseCard({
    super.key,
    required this.caseModel,
    this.onTap,
    this.onAccept,
    this.onDecline,
  });

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return AppTheme.royalBlue;
      case 'in_progress':
        return Colors.purple;
      case 'completed':
        return Colors.green;
      default:
        return AppTheme.mutedText;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title and Status Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      caseModel.caseTitle,
                      style: AppTheme.cardTitleStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(caseModel.status),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      caseModel.status.toUpperCase(),
                      style: const TextStyle(
                        color: AppTheme.cleanWhite,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Category Row
              Row(
                children: [
                  const Icon(
                    Icons.category,
                    size: 16,
                    color: AppTheme.royalBlue,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      caseModel.caseType,
                      style: AppTheme.cardDetailStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Description
              Text(
                caseModel.caseDescription,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.cardDetailStyle,
              ),
              const SizedBox(height: 12),
              // Date and Action Buttons Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      'Created: ${_formatDate(caseModel.createdAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.mutedText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onAccept != null || onDecline != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onAccept != null)
                          TextButton(
                            onPressed: onAccept,
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.royalBlue,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Accept'),
                          ),
                        if (onDecline != null)
                          TextButton(
                            onPressed: onDecline,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Decline'),
                          ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

