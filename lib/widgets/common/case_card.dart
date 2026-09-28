import 'package:flutter/material.dart';
import '../../models/case_model.dart';
import '../../theme/app_theme.dart';
import '../../utils/case_result.dart';
import '../../utils/case_status_filter.dart';

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
    if (CaseStatusFilter.isDraft(status)) return const Color(0xFFC9A227);
    if (CaseStatusFilter.isOpen(status)) return Colors.orange;
    if (CaseStatusFilter.isInProgress(status)) return Colors.purple;
    if (CaseStatusFilter.isCompleted(status)) return Colors.green;
    return AppTheme.mutedText;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bounded = constraints.maxHeight.isFinite;
              final description = Text(
                caseModel.caseDescription,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.cardDetailStyle,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          caseModel.caseTitle,
                          style: AppTheme.cardTitleStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(caseModel.status),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _statusBadgeLabel(caseModel),
                          style: const TextStyle(
                            color: AppTheme.cleanWhite,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.category,
                        size: 14,
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
                  const SizedBox(height: 6),
                  if (bounded) Expanded(child: description) else description,
                  const SizedBox(height: 6),
                  Text(
                    'Created: ${_formatDate(caseModel.createdAt)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.mutedText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (onAccept != null || onDecline != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
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
              );
            },
          ),
        ),
      ),
    );
  }

  String _statusBadgeLabel(CaseModel caseModel) {
    if (CaseStatusFilter.isCompleted(caseModel.status)) {
      final result = CaseResult.shortLabel(caseModel.caseResult);
      if (result.isNotEmpty) return result.toUpperCase();
    }
    return CaseStatusFilter.statusLabel(caseModel.status).toUpperCase();
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

