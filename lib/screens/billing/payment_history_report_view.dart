import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';
import '../../utils/currency.dart';
import '../../utils/payment_history_report.dart';
import '../../widgets/common/brand_logo.dart';

/// On-screen Payment History Report matching the downloadable PDF layout.
class PaymentHistoryReportView extends StatelessWidget {
  final PaymentHistoryReport report;

  const PaymentHistoryReportView({super.key, required this.report});

  static bool _isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 720;

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(mobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, mobile),
          SizedBox(height: mobile ? 10 : 16),
          if (mobile)
            _mobileRows(report.rows)
          else
            _desktopTable(report.rows),
          SizedBox(height: mobile ? 12 : 20),
          Text(
            'SUMMARY',
            style: AppTheme.bodyMedium.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: mobile ? 12 : 14,
            ),
          ),
          SizedBox(height: mobile ? 6 : 10),
          _summaryCards(report.summary, mobile),
          SizedBox(height: mobile ? 10 : 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              report.meta.periodNote,
              style: const TextStyle(fontSize: 11, color: AppTheme.mutedText),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: mobile ? Alignment.center : Alignment.centerRight,
            child: Column(
              crossAxisAlignment:
                  mobile ? CrossAxisAlignment.center : CrossAxisAlignment.end,
              children: [
                Text(
                  report.meta.preparedBy,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.darkText,
                  ),
                ),
                Text(
                  report.meta.preparedByTitle,
                  style: const TextStyle(fontSize: 10.5, color: AppTheme.mutedText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, bool mobile) {
    if (mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const BrandLogo(size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.meta.firmName,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.darkText,
                      ),
                    ),
                    if (report.meta.firmAddress.trim().isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        report.meta.firmAddress,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.mutedText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (report.meta.firmPhone.trim().isNotEmpty ||
              report.meta.firmEmail.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 2,
              children: [
                if (report.meta.firmPhone.trim().isNotEmpty)
                  Text(
                    report.meta.firmPhone,
                    style: const TextStyle(fontSize: 10.5, color: AppTheme.mutedText),
                  ),
                if (report.meta.firmEmail.trim().isNotEmpty)
                  Text(
                    report.meta.firmEmail,
                    style: const TextStyle(fontSize: 10.5, color: AppTheme.mutedText),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 8),
          const Text(
            'PAYMENT HISTORY REPORT',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppTheme.deepNavy,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Report Date: ${report.meta.reportDate}',
            style: const TextStyle(fontSize: 11, color: AppTheme.mutedText),
          ),
          Text(
            'Prepared By: ${report.meta.preparedBy}',
            style: const TextStyle(fontSize: 11, color: AppTheme.mutedText),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BrandLogo(size: 56),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                report.meta.firmName,
                style: AppTheme.bodyLarge.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(report.meta.firmAddress, style: AppTheme.bodySmall),
              Text(
                '${report.meta.firmPhone}  |  ${report.meta.firmEmail}',
                style: AppTheme.bodySmall,
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'PAYMENT HISTORY REPORT',
              style: AppTheme.heading4.copyWith(color: AppTheme.deepNavy),
              textAlign: TextAlign.right,
            ),
            Text('Report Date: ${report.meta.reportDate}',
                style: AppTheme.bodySmall),
            Text('Prepared By: ${report.meta.preparedBy}',
                style: AppTheme.bodySmall),
          ],
        ),
      ],
    );
  }

  Widget _mobileRows(List<PaymentReportRow> rows) {
    if (rows.isEmpty) {
      return Text(
        'No records.',
        style: AppTheme.bodySmall.copyWith(color: AppTheme.mutedText),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          _mobileRowCard(i + 1, rows[i]),
          if (i < rows.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _mobileRowCard(int no, PaymentReportRow row) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.deepNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$no',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: AppTheme.deepNavy,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.clientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppTheme.darkText,
                      ),
                    ),
                    if (row.caseNumber.trim().isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        'Case: ${row.caseNumber}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.mutedText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _statusChip(row.statusLabel),
            ],
          ),
          const SizedBox(height: 8),
          // 3-Column Financial Micro-Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Fee',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.mutedText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          Currency.peso(row.totalFee),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.darkText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 22,
                  width: 1,
                  color: const Color(0xFFCBD5E1),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Paid',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.mutedText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          Currency.peso(row.totalPaid),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 22,
                  width: 1,
                  color: const Color(0xFFCBD5E1),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Remaining',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.mutedText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          Currency.peso(row.remainingBalance),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: row.remainingBalance > 0
                                ? const Color(0xFFD97706)
                                : Colors.green.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                row.lastPaymentDate != null
                    ? 'Last: ${DateFormat('MMM dd, yyyy').format(row.lastPaymentDate!)}'
                    : 'Last: —',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppTheme.mutedText,
                ),
              ),
              if (row.lastRecordedBy?.isNotEmpty == true)
                Text(
                  'By: ${row.lastRecordedBy}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.mutedText,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _desktopTable(List<PaymentReportRow> rows) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: const WidgetStatePropertyAll(AppTheme.deepNavy),
        headingTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
        dataTextStyle: const TextStyle(fontSize: 11),
        columns: const [
          DataColumn(label: Text('No.')),
          DataColumn(label: Text('Client Name')),
          DataColumn(label: Text('Case No.')),
          DataColumn(label: Text('Total Fee')),
          DataColumn(label: Text('Total Paid')),
          DataColumn(label: Text('Remaining Balance')),
          DataColumn(label: Text('Payment Status')),
          DataColumn(label: Text('Last Payment Date')),
          DataColumn(label: Text('Recorded By')),
        ],
        rows: [
          for (var i = 0; i < rows.length; i++)
            DataRow(
              cells: [
                DataCell(Text('${i + 1}')),
                DataCell(Text(rows[i].clientName)),
                DataCell(Text(rows[i].caseNumber)),
                DataCell(Text(Currency.peso(rows[i].totalFee))),
                DataCell(Text(Currency.peso(rows[i].totalPaid))),
                DataCell(Text(Currency.peso(rows[i].remainingBalance))),
                DataCell(_statusChip(rows[i].statusLabel)),
                DataCell(Text(
                  rows[i].lastPaymentDate != null
                      ? DateFormat('MMM dd, yyyy')
                          .format(rows[i].lastPaymentDate!)
                      : '—',
                )),
                DataCell(Text(rows[i].lastRecordedBy ?? '—')),
              ],
            ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    Color color;
    switch (status) {
      case 'PAID':
        color = AppTheme.success;
        break;
      case 'PARTIAL':
        color = AppTheme.warning;
        break;
      default:
        color = AppTheme.error;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _summaryCards(PaymentReportSummary s, bool mobile) {
    final cards = [
      _summaryCard(
        'UNPAID',
        s.unpaidCount,
        Currency.peso(s.unpaidAmount),
        AppTheme.error,
      ),
      _summaryCard(
        'PARTIAL',
        s.partialCount,
        Currency.peso(s.partialAmount),
        AppTheme.warning,
      ),
      _summaryCard(
        'PAID',
        s.paidCount,
        Currency.peso(s.paidAmount),
        AppTheme.success,
      ),
    ];

    return Row(
      children: [
        Expanded(child: cards[0]),
        const SizedBox(width: 6),
        Expanded(child: cards[1]),
        const SizedBox(width: 6),
        Expanded(child: cards[2]),
      ],
    );
  }

  Widget _summaryCard(
    String title,
    int count,
    String amount,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amount,
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
}
