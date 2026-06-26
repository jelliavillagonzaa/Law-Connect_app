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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray),
        boxShadow: AppTheme.elevatedShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const SizedBox(height: 16),
          _table(report.rows),
          const SizedBox(height: 20),
          Text('SUMMARY',
              style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          _summaryCards(report.summary),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.lightGray,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'NOTE: This report shows all clients and their payment status '
              'as of the report date.',
              style: AppTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(report.meta.preparedBy,
                    style: AppTheme.bodySmall
                        .copyWith(fontWeight: FontWeight.w600)),
                Text('Attorney at Law', style: AppTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BrandLogo(size: 48),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(report.meta.firmName,
                  style: AppTheme.bodyLarge
                      .copyWith(fontWeight: FontWeight.bold)),
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

  Widget _table(List<PaymentReportRow> rows) {
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

  Widget _summaryCards(PaymentReportSummary s) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 700;
        final children = [
          _summaryCard(
            'TOTAL UNPAID CASES',
            s.unpaidCount,
            Currency.peso(s.unpaidAmount),
            AppTheme.error,
          ),
          _summaryCard(
            'TOTAL PARTIALLY PAID CASES',
            s.partialCount,
            Currency.peso(s.partialAmount),
            AppTheme.warning,
          ),
          _summaryCard(
            'TOTAL FULLY PAID CASES',
            s.paidCount,
            Currency.peso(s.paidAmount),
            AppTheme.success,
          ),
        ];
        if (narrow) {
          return Column(
            children: children
                .map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: c,
                    ))
                .toList(),
          );
        }
        return Row(
          children: children
              .map((c) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: c,
                    ),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _summaryCard(
    String title,
    int count,
    String amount,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              )),
          const SizedBox(height: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            'Total Amount: $amount',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
