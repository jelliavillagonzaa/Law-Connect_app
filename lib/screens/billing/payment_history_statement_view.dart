import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';
import '../../utils/currency.dart';
import '../../utils/payment_history_statement_pdf.dart';
import '../../widgets/common/brand_logo.dart';

/// On-screen Statement of Account card matching the downloadable PDF layout.
class PaymentHistoryStatementView extends StatelessWidget {
  final PaymentStatementData data;

  const PaymentHistoryStatementView({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final nameParts = data.clientName.split(' ');
    final first = nameParts.isNotEmpty ? nameParts.first : data.clientName;
    final last = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '—';

    Color statusColor;
    switch (data.invoice.statusLabel) {
      case 'Fully Paid':
        statusColor = AppTheme.success;
        break;
      case 'Partially Paid':
        statusColor = AppTheme.warning;
        break;
      default:
        statusColor = AppTheme.royalBlue;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandLogo(size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data.firmName,
                        style: AppTheme.bodyLarge
                            .copyWith(fontWeight: FontWeight.bold)),
                    Text(data.firmAddress, style: AppTheme.bodySmall),
                    Text('${data.firmPhone}  |  ${data.firmEmail}',
                        style: AppTheme.bodySmall),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('PAYMENT HISTORY',
                      style: AppTheme.heading4
                          .copyWith(color: AppTheme.deepNavy)),
                  Text('Statement of Account', style: AppTheme.bodySmall),
                  Text('Statement Date: ${data.statementDate}',
                      style: AppTheme.bodySmall),
                  Text('Reference No.: ${data.referenceNo}',
                      style: AppTheme.bodySmall),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _infoBlock('Client Information', [
                  _pair('First Name', first),
                  _pair('Last Name', last),
                  _pair('Client ID', data.clientId),
                  _pair('Contact No.',
                      data.clientPhone.isEmpty ? '—' : data.clientPhone),
                  _pair('Email',
                      data.clientEmail.isEmpty ? '—' : data.clientEmail),
                ]),
              ),
              Expanded(
                child: _infoBlock('Case Information', [
                  _pair('Case Number', data.caseNumber),
                  _pair('Case Title', data.caseTitle),
                  _pair('Practice Area', data.practiceArea),
                  _pair('Attorney', data.attorneyName),
                  _pair('Total Legal Fee', Currency.peso(data.totalLegalFee)),
                ]),
              ),
              Expanded(child: _summaryBox(data, statusColor)),
            ],
          ),
          const SizedBox(height: 16),
          Text('Payment History',
              style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _paymentTable(data),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.lightGray,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Note: This statement reflects all payments recorded at the law '
              'office. Please keep this document for your records.',
              style: AppTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBlock(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...rows,
      ],
    );
  }

  Widget _pair(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.bodySmall.copyWith(color: AppTheme.mutedText)),
          Text(value, style: AppTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _summaryBox(PaymentStatementData data, Color statusColor) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.deepNavy),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(
              color: AppTheme.deepNavy,
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: const Text(
              'Account Summary',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                _summaryRow('Total Legal Fee', Currency.peso(data.totalLegalFee)),
                _summaryRow('Total Amount Paid', Currency.peso(data.totalPaid),
                    color: AppTheme.success),
                _summaryRow(
                    'Remaining Balance', Currency.peso(data.remainingBalance),
                    color: AppTheme.royalBlue, bold: true),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    data.statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value,
      {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTheme.bodySmall),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: color ?? AppTheme.darkText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentTable(PaymentStatementData data) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor:
            const WidgetStatePropertyAll(AppTheme.deepNavy),
        headingTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
        dataTextStyle: const TextStyle(fontSize: 11),
        columns: const [
          DataColumn(label: Text('Payment ID')),
          DataColumn(label: Text('Date & Time')),
          DataColumn(label: Text('Amount Paid')),
          DataColumn(label: Text('Payment Type')),
          DataColumn(label: Text('Payment Status')),
          DataColumn(label: Text('Recorded By')),
          DataColumn(label: Text('Remarks / OR No.')),
        ],
        rows: [
          ...data.payments.map(
            (p) => DataRow(
              cells: [
                DataCell(Text(p.displayPaymentId)),
                DataCell(Text(
                    DateFormat('MMM dd, yyyy hh:mm a').format(p.paidAt))),
                DataCell(Text(Currency.peso(p.amount))),
                DataCell(Text(p.methodLabel)),
                DataCell(_statusChip('PAID', AppTheme.success)),
                DataCell(Text(p.recordedByLabel)),
                DataCell(Text(p.referenceNo ?? p.note ?? '—')),
              ],
            ),
          ),
          if (data.remainingBalance > 0.001)
            DataRow(
              cells: [
                const DataCell(Text('—')),
                const DataCell(Text('—')),
                DataCell(Text(Currency.peso(data.remainingBalance),
                    style: const TextStyle(color: AppTheme.error))),
                const DataCell(Text('—')),
                DataCell(_statusChip('UNPAID', AppTheme.error)),
                const DataCell(Text('—')),
                const DataCell(Text('Remaining Balance')),
              ],
            ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
