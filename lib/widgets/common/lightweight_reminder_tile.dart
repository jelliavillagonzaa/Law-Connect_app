import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/lightweight_reminder_item.dart';
import '../../services/hearing_calendar_fields.dart';
import '../../theme/app_theme.dart';
import '../../utils/hearing_order_detail.dart';
import 'hearing_notification_detail_panel.dart';

/// Fast reminder card — list shows title/subtitle only; full body loads on expand.
class LightweightReminderTile extends StatefulWidget {
  const LightweightReminderTile({
    super.key,
    required this.item,
    required this.onMarkRead,
  });

  final LightweightReminderItem item;
  final VoidCallback onMarkRead;

  @override
  State<LightweightReminderTile> createState() => _LightweightReminderTileState();
}

class _LightweightReminderTileState extends State<LightweightReminderTile> {
  bool _expanded = false;
  bool _detailReady = false;
  bool _loadingDetail = false;
  Map<String, dynamic>? _detailData;

  static IconData _iconForType(String type) {
    final t = type.toLowerCase();
    if (t.contains('hearing')) return Icons.gavel;
    if (t == 'case_request') return Icons.mark_email_unread;
    if (t.contains('task')) return Icons.task_alt;
    if (t.contains('appointment')) return Icons.event;
    return Icons.notifications_active;
  }

  static Color _colorForType(String type) {
    final t = type.toLowerCase();
    if (t.contains('hearing')) return AppTheme.royalBlue;
    if (t == 'case_request') return Colors.deepOrange;
    if (t.contains('task')) return Colors.indigo;
    if (t.contains('appointment')) return Colors.teal;
    return Colors.orange;
  }

  Future<void> _ensureDetailLoaded() async {
    if (_detailData != null || _loadingDetail) return;
    setState(() => _loadingDetail = true);
    try {
      _detailData = await loadHearingOrderDetail(
        hearingDocId: widget.item.hearingDocId,
        notificationDocId: widget.item.notificationDocId,
      );
    } catch (_) {}
    if (mounted) setState(() => _loadingDetail = false);
  }

  Future<void> _onHeaderTap() async {
    final willExpand = !_expanded;
    if (willExpand) {
      setState(() {
        _expanded = true;
        _detailReady = false;
      });
      if (!widget.item.isRead) widget.onMarkRead();
      await _ensureDetailLoaded();
      if (mounted) setState(() => _detailReady = true);
      return;
    }
    setState(() {
      _expanded = false;
      _detailReady = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isRead = item.isRead;
    final color = _colorForType(item.type);
    final isHearing = item.isHearing;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _onHeaderTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_iconForType(item.type), color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                item.title,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight:
                                      isRead ? FontWeight.w600 : FontWeight.bold,
                                  color: isRead ? Colors.grey[700] : Colors.black87,
                                  height: 1.3,
                                ),
                              ),
                            ),
                            if (!isRead)
                              Padding(
                                padding: const EdgeInsets.only(left: 8, top: 4),
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            Icon(
                              _expanded ? Icons.expand_less : Icons.expand_more,
                              color: AppTheme.mutedText,
                              size: 22,
                            ),
                          ],
                        ),
                        if (!_expanded && item.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            item.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.access_time,
                                size: 14, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(
                              DateFormat('MMM d, yyyy · hh:mm a')
                                  .format(item.sortTime),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: !_detailReady || _loadingDetail
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : isHearing
                      ? HearingNotificationDetailPanel(
                          data: _detailData ?? const {},
                          hearingDocId: item.hearingDocId,
                        )
                      : SelectableText(
                          HearingCalendarFields.asDisplayString(
                                _detailData?['message'],
                              )
                              .isNotEmpty
                          ? HearingCalendarFields.asDisplayString(
                              _detailData?['message'],
                            )
                          : item.subtitle,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: Colors.grey[800],
                          ),
                        ),
            ),
          ],
        ],
      ),
    );
  }
}
