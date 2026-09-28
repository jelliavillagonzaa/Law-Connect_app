import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';
import '../../models/invoice_model.dart';
import '../../models/payment_model.dart';
import '../../models/case_model.dart';
import '../../services/billing_service.dart';
import '../../services/case_service.dart';
import '../../utils/currency.dart';
import '../../utils/report_exporter/report_exporter.dart';
import '../../utils/payment_history_report.dart';
import '../../utils/payment_history_report_pdf.dart';
import 'payment_history_report_view.dart';
import '../../widgets/empty_state.dart';
import '../client/billing_screen.dart' show PaymentHistoryTile, StatusBadge;

/// Firm-side billing (attorney or staff). Shows each client's case history,
/// total legal fees, total amount paid, remaining balance, and payment status.
/// Attorneys/staff can issue invoices and record payments received at the office.
class BillingManagementScreen extends StatelessWidget {
  /// The attorney whose invoices/payments are shown. For an attorney this is
  /// their own uid; for staff this is their assigned attorney's id.
  final String attorneyId;

  /// Whether the current user may issue invoices and record payments.
  final bool canManage;

  /// Role of the person recording payments ('attorney' | 'staff' | 'admin').
  final String recorderRole;

  /// Display name of the person recording payments.
  final String? recorderName;

  final String title;

  const BillingManagementScreen({
    super.key,
    required this.attorneyId,
    this.canManage = true,
    this.recorderRole = 'staff',
    this.recorderName,
    this.title = 'Billing & Payments',
  });

  @override
  Widget build(BuildContext context) {
    final billing = BillingService();

    return Scaffold(
      backgroundColor: AppTheme.lightGray,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppTheme.royalBlue,
        actions: [
          IconButton(
            tooltip: 'Payment History',
            icon: const Icon(Icons.history),
            onPressed: () => _openPaymentHistory(context, billing),
          ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _openCreateInvoice(context, billing),
              backgroundColor: AppTheme.royalBlue,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('New Invoice'),
            )
          : null,
      body: StreamBuilder<List<InvoiceModel>>(
        stream: billing.streamInvoicesForAttorney(attorneyId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'Could not load billing',
              message: '${snapshot.error}',
            );
          }
          final invoices = snapshot.data ?? [];
          final active = invoices.where((i) => !i.isCancelled).toList();
          final totalFees =
              active.fold<double>(0, (s, i) => s + i.totalLegalFee);
          final totalPaid =
              active.fold<double>(0, (s, i) => s + i.amountPaid);
          final remaining =
              active.fold<double>(0, (s, i) => s + i.remainingBalance);
          final unpaidCount =
              active.where((i) => i.amountPaid <= 0).length;
          final partialCount = active.where((i) => i.isPartiallyPaid).length;
          final paidCount = active.where((i) => i.isPaid).length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _SummaryGrid(
                totalFees: totalFees,
                totalPaid: totalPaid,
                remaining: remaining,
                invoiceCount: active.length,
                unpaidCount: unpaidCount,
                partialCount: partialCount,
                paidCount: paidCount,
              ),
              const SizedBox(height: 24),
              Text('Case History', style: AppTheme.heading4),
              const SizedBox(height: 12),
              _CaseHistorySection(
                invoices: invoices,
                billing: billing,
                canManage: canManage,
                onRecordPayment: (inv) =>
                    _openRecordPayment(context, billing, inv),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openPaymentHistory(BuildContext context, BillingService billing) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PaymentHistoryScreen(
          attorneyId: attorneyId,
          billing: billing,
          canManage: canManage,
        ),
      ),
    );
  }

  Future<void> _openCreateInvoice(
    BuildContext context,
    BillingService billing,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CreateInvoiceSheet(
        attorneyId: attorneyId,
        billing: billing,
      ),
    );
  }

  Future<void> _openRecordPayment(
    BuildContext context,
    BillingService billing,
    InvoiceModel invoice,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _RecordPaymentSheet(
        invoice: invoice,
        billing: billing,
        recorderRole: recorderRole,
        recorderName: recorderName,
      ),
    );
  }
}

bool _invoiceMatchesCaseSearch(InvoiceModel invoice, String rawQuery) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return true;

  String normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(' vs. ', ' vs ')
      .replaceAll(' v. ', ' vs ')
      .trim();

  final haystack = normalize([
    invoice.caseTitle ?? '',
    invoice.caseNumber ?? '',
    invoice.displayCaseNumber,
    invoice.clientName ?? '',
    invoice.description ?? '',
  ].join(' '));
  final normalizedQuery = normalize(query);
  if (haystack.contains(normalizedQuery)) return true;

  final words = normalizedQuery.split(' ').where((w) => w.length >= 2);
  if (words.isEmpty) return haystack.contains(normalizedQuery);
  return words.every(haystack.contains);
}

class _CaseHistorySection extends StatefulWidget {
  const _CaseHistorySection({
    required this.invoices,
    required this.billing,
    required this.canManage,
    required this.onRecordPayment,
  });

  final List<InvoiceModel> invoices;
  final BillingService billing;
  final bool canManage;
  final void Function(InvoiceModel invoice) onRecordPayment;

  @override
  State<_CaseHistorySection> createState() => _CaseHistorySectionState();
}

class _CaseHistorySectionState extends State<_CaseHistorySection> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text;
    final filtered = widget.invoices
        .where((inv) => _invoiceMatchesCaseSearch(inv, query))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search case name, case no, or client...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: query.trim().isNotEmpty
                ? IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                  )
                : null,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (widget.invoices.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.cardDecoration,
            child: Text(
              'No invoices issued yet.',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.mutedText),
            ),
          )
        else if (filtered.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.cardDecoration,
            child: Text(
              'No cases match your search.',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.mutedText),
            ),
          )
        else
          ...filtered.map(
            (inv) => _FirmInvoiceCard(
              invoice: inv,
              billing: widget.billing,
              canManage: widget.canManage,
              onRecordPayment: () => widget.onRecordPayment(inv),
            ),
          ),
      ],
    );
  }
}

class _PaymentHistoryScreen extends StatefulWidget {
  final String attorneyId;
  final BillingService billing;
  final bool canManage;
  final List<InvoiceModel>? invoices;

  const _PaymentHistoryScreen({
    required this.attorneyId,
    required this.billing,
    required this.canManage,
    this.invoices,
  });

  @override
  State<_PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<_PaymentHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';

  Future<void> _downloadReportPdf(PaymentHistoryReport report) async {
    if (report.rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No report data to download.')),
      );
      return;
    }

    final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'payment_history_report_$now.pdf';

    try {
      final bytes = await buildPaymentHistoryReportPdf(report);
      await saveBytes(
        bytes: bytes,
        filename: fileName,
        mimeType: 'application/pdf',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Payment History Report downloaded. Check your Downloads folder.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _downloadReportCsv(PaymentHistoryReport report) async {
    if (report.rows.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln([
      'No.',
      'Client Name',
      'Case No.',
      'Total Fee',
      'Total Paid',
      'Remaining Balance',
      'Payment Status',
      'Last Payment Date',
      'Recorded By',
    ].join(','));

    for (var i = 0; i < report.rows.length; i++) {
      final r = report.rows[i];
      buffer.writeln([
        '${i + 1}',
        _csvCell(r.clientName),
        _csvCell(r.caseNumber),
        r.totalFee.toStringAsFixed(2),
        r.totalPaid.toStringAsFixed(2),
        r.remainingBalance.toStringAsFixed(2),
        r.statusLabel,
        _csvCell(
          r.lastPaymentDate != null
              ? DateFormat('yyyy-MM-dd').format(r.lastPaymentDate!)
              : '',
        ),
        _csvCell(r.lastRecordedBy ?? ''),
      ].join(','));
    }

    final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    try {
      await saveBytes(
        bytes: Uint8List.fromList(utf8.encode(buffer.toString())),
        filename: 'payment_history_report_$now.csv',
        mimeType: 'text/csv',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CSV report downloaded.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightGray,
      appBar: AppBar(
        title: const Text('Payment History'),
        backgroundColor: AppTheme.royalBlue,
      ),
      body: StreamBuilder<List<InvoiceModel>>(
        stream: widget.billing.streamInvoicesForAttorney(widget.attorneyId),
        builder: (context, invoiceSnap) {
          final invoices =
              invoiceSnap.data ?? widget.invoices ?? const <InvoiceModel>[];

          return StreamBuilder<List<PaymentModel>>(
            stream: widget.billing.streamPaymentsForAttorney(widget.attorneyId),
            builder: (context, snap) {
              final payments = snap.data ?? [];
              final reportKey =
                  '${invoices.map((i) => i.id).join('|')}|${payments.map((p) => p.id).join('|')}';

              return FutureBuilder<PaymentHistoryReport>(
                key: ValueKey('$reportKey|${_searchController.text}'),
                future: buildPaymentHistoryReport(
                  invoices: invoices,
                  payments: payments,
                  attorneyId: widget.attorneyId,
                ),
                builder: (context, reportSnap) {
                  if ((invoiceSnap.connectionState == ConnectionState.waiting &&
                          invoices.isEmpty) ||
                      (reportSnap.connectionState == ConnectionState.waiting &&
                          reportSnap.data == null)) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final baseReport = reportSnap.data;
                  if (baseReport == null) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final filteredRows = filterReportRows(
                    baseReport.rows,
                    _searchController.text,
                  );
                  final report = PaymentHistoryReport(
                    meta: baseReport.meta,
                    rows: filteredRows,
                    summary: buildPaymentReportSummary(filteredRows),
                  );

                  final isMobile = MediaQuery.sizeOf(context).width < 720;

                  return ListView(
                    padding: EdgeInsets.all(isMobile ? 12 : 16),
                    children: [
                      if (isMobile) ...[
                        TextField(
                          controller: _searchController,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText:
                                'Search client, case no, payment status...',
                            prefixIcon: Icon(Icons.search),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: PopupMenuButton<String>(
                            icon: const Icon(Icons.download_outlined,
                                color: AppTheme.royalBlue),
                            tooltip: 'Download report',
                            onSelected: (value) {
                              if (value == 'pdf') {
                                _downloadReportPdf(report);
                              } else {
                                _downloadReportCsv(report);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'pdf',
                                child: Text('Download PDF Report'),
                              ),
                              PopupMenuItem(
                                value: 'csv',
                                child: Text('Download CSV'),
                              ),
                            ],
                          ),
                        ),
                      ] else
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  hintText:
                                      'Search client, case no, payment status...',
                                  prefixIcon: Icon(Icons.search),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.download_outlined,
                                  color: AppTheme.royalBlue),
                              onSelected: (value) {
                                if (value == 'pdf') {
                                  _downloadReportPdf(report);
                                } else {
                                  _downloadReportCsv(report);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'pdf',
                                  child: Text('Download PDF Report'),
                                ),
                                PopupMenuItem(
                                  value: 'csv',
                                  child: Text('Download CSV'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      const SizedBox(height: 16),
                      if (baseReport.rows.isEmpty)
                        Text(
                          'No billing cases yet.',
                          style: AppTheme.bodyMedium
                              .copyWith(color: AppTheme.mutedText),
                        )
                      else if (filteredRows.isEmpty)
                        Text(
                          'No matching records found.',
                          style: AppTheme.bodyMedium
                              .copyWith(color: AppTheme.mutedText),
                        )
                      else
                        PaymentHistoryReportView(report: report),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Confirms and deletes an invoice together with all of its payment receipts.
Future<void> _confirmDeleteInvoice(
  BuildContext context,
  BillingService billing,
  InvoiceModel invoice,
) async {
  final title = invoice.caseTitle?.isNotEmpty == true
      ? invoice.caseTitle!
      : 'this legal fee';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete invoice?'),
      content: Text(
        'This permanently deletes the invoice for "$title" '
        '(${Currency.peso(invoice.totalLegalFee)}) and every payment recorded '
        'against it. Its fees and payments will be removed from all totals. '
        'This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  final result = await billing.deleteInvoice(invoice);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(result.success
          ? 'Invoice deleted and totals updated.'
          : (result.message ?? 'Failed to delete invoice.')),
      backgroundColor: result.success ? Colors.green : Colors.redAccent,
    ),
  );
}

/// Confirms and deletes/voids a recorded payment, reversing the invoice balance.
Future<void> _confirmDeletePayment(
  BuildContext context,
  BillingService billing,
  PaymentModel payment,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete payment?'),
      content: Text(
        'This will remove the ${Currency.peso(payment.amount)} payment '
        '(${payment.displayPaymentId}) and add it back to the remaining '
        'balance. This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  final result = await billing.deletePayment(payment);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(result.success
          ? 'Payment deleted and balance updated.'
          : (result.message ?? 'Failed to delete payment.')),
      backgroundColor: result.success ? Colors.green : Colors.redAccent,
    ),
  );
}

class _SummaryGrid extends StatelessWidget {
  final double totalFees;
  final double totalPaid;
  final double remaining;
  final int invoiceCount;
  final int unpaidCount;
  final int partialCount;
  final int paidCount;

  const _SummaryGrid({
    required this.totalFees,
    required this.totalPaid,
    required this.remaining,
    required this.invoiceCount,
    required this.unpaidCount,
    required this.partialCount,
    required this.paidCount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.royalBlue, AppTheme.deepNavy],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppTheme.elevatedShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total Remaining Balance',
                  style: AppTheme.bodyMedium.copyWith(color: Colors.white70)),
              const SizedBox(height: 6),
              CurrencyText(
                amount: remaining,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$invoiceCount active invoice${invoiceCount == 1 ? '' : 's'}',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _statCard(
                'Total Legal Fees',
                totalFees,
                Icons.receipt_long_outlined,
                AppTheme.royalBlue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                'Total Paid',
                totalPaid,
                Icons.check_circle_outline,
                AppTheme.success,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _statusCard(
                  'Unpaid', unpaidCount, AppTheme.royalBlue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statusCard(
                  'Partially Paid', partialCount, AppTheme.warning),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statusCard('Fully Paid', paidCount, AppTheme.success),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statusCard(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, num amount, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 10),
          CurrencyText(
            amount: amount,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppTheme.bodySmall),
        ],
      ),
    );
  }
}

class _FirmInvoiceCard extends StatelessWidget {
  final InvoiceModel invoice;
  final BillingService billing;
  final bool canManage;
  final VoidCallback onRecordPayment;

  const _FirmInvoiceCard({
    required this.invoice,
    required this.billing,
    required this.canManage,
    required this.onRecordPayment,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  invoice.caseTitle?.isNotEmpty == true
                      ? invoice.caseTitle!
                      : 'Legal Fee',
                  style:
                      AppTheme.bodyLarge.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              StatusBadge(invoice: invoice),
              if (canManage)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Delete invoice',
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.redAccent, size: 20),
                  onPressed: () =>
                      _confirmDeleteInvoice(context, billing, invoice),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.tag, size: 14, color: AppTheme.mutedText),
              const SizedBox(width: 4),
              Text('Case No: ${invoice.displayCaseNumber}',
                  style: AppTheme.bodySmall),
            ],
          ),
          if (invoice.clientName?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.person_outline,
                    size: 14, color: AppTheme.mutedText),
                const SizedBox(width: 4),
                Text(invoice.clientName!, style: AppTheme.bodySmall),
              ],
            ),
          ],
          if (invoice.description?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(invoice.description!, style: AppTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          _row('Total Fee', invoice.totalLegalFee),
          const SizedBox(height: 6),
          _row('Total Paid', invoice.amountPaid),
          const SizedBox(height: 6),
          _row(
            'Remaining Balance',
            invoice.remainingBalance,
            emphasize: true,
          ),
          _PerCasePaymentHistory(
            stream: billing.streamPaymentsForInvoice(invoice.id),
            billing: billing,
            canManage: canManage,
          ),
          if (canManage && invoice.hasOutstanding) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onRecordPayment,
                icon: const Icon(Icons.add_card_outlined),
                label: const Text('Record Payment'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.royalBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, num value, {bool emphasize = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTheme.bodyMedium.copyWith(
            color: emphasize ? AppTheme.darkText : AppTheme.mutedText,
            fontWeight: emphasize ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        CurrencyText(
          amount: value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: emphasize ? AppTheme.royalBlue : AppTheme.darkText,
          ),
        ),
      ],
    );
  }
}

/// Expandable per-case payment history shown inside each invoice card.
class _PerCasePaymentHistory extends StatelessWidget {
  final Stream<List<PaymentModel>> stream;
  final BillingService billing;
  final bool canManage;

  const _PerCasePaymentHistory({
    required this.stream,
    required this.billing,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PaymentModel>>(
      stream: stream,
      builder: (context, snapshot) {
        final payments = snapshot.data ?? [];
        if (payments.isEmpty) return const SizedBox.shrink();
        return Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text(
              'Payment History (${payments.length})',
              style: AppTheme.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: AppTheme.royalBlue,
              ),
            ),
            children: payments
                .map((p) => PaymentHistoryTile(
                      payment: p,
                      showClientName: true,
                      onDelete: canManage
                          ? () => _confirmDeletePayment(context, billing, p)
                          : null,
                    ))
                .toList(),
          ),
        );
      },
    );
  }
}

/// Bottom sheet to record a payment received physically for an invoice.
class _RecordPaymentSheet extends StatefulWidget {
  final InvoiceModel invoice;
  final BillingService billing;
  final String recorderRole;
  final String? recorderName;

  const _RecordPaymentSheet({
    required this.invoice,
    required this.billing,
    required this.recorderRole,
    this.recorderName,
  });

  @override
  State<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<_RecordPaymentSheet> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _refController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  String _method = PaymentMethod.cash;
  DateTime _paidAt = DateTime.now();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Default to settling the full remaining balance.
    _amountController.text = widget.invoice.remainingBalance.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _refController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _paidAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_paidAt),
    );
    final time = pickedTime ?? TimeOfDay.fromDateTime(_paidAt);
    setState(() {
      _paidAt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid payment amount.');
      return;
    }
    if (amount > widget.invoice.remainingBalance + 0.001) {
      setState(() => _error =
          'Amount exceeds the remaining balance of '
          '${Currency.peso(widget.invoice.remainingBalance)}.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final result = await widget.billing.recordPayment(
      invoice: widget.invoice,
      amount: amount,
      method: _method,
      referenceNo: _refController.text.trim(),
      note: _noteController.text.trim(),
      paidAt: _paidAt,
      recordedBy: uid,
      recordedByName: widget.recorderName,
      recordedByRole: widget.recorderRole,
    );

    if (!mounted) return;
    if (result.success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment recorded successfully.')),
      );
    } else {
      setState(() {
        _submitting = false;
        _error = result.message ?? 'Failed to record payment.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final invoice = widget.invoice;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.borderGray,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Record Payment', style: AppTheme.heading4),
            const SizedBox(height: 4),
            Text(
              invoice.caseTitle?.isNotEmpty == true
                  ? invoice.caseTitle!
                  : 'Legal Fee',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.mutedText),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.lightGray,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Remaining Balance', style: AppTheme.bodyMedium),
                  CurrencyText(
                    amount: invoice.remainingBalance,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.royalBlue,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(Currency.label('Amount Received'), style: AppTheme.bodyMedium),
            const SizedBox(height: 6),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: 'e.g. 5000'),
            ),
            const SizedBox(height: 16),
            Text('Payment Method', style: AppTheme.bodyMedium),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _method,
              isExpanded: true,
              decoration: const InputDecoration(),
              items: PaymentMethod.all
                  .map(
                    (m) => DropdownMenuItem<String>(
                      value: m,
                      child: Text(PaymentMethod.label(m)),
                    ),
                  )
                  .toList(),
              onChanged: (m) => setState(() => _method = m ?? _method),
            ),
            const SizedBox(height: 16),
            Text('Date & Time Received', style: AppTheme.bodyMedium),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickDateTime,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.borderGray),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 18, color: AppTheme.mutedText),
                    const SizedBox(width: 10),
                    Text(DateFormat('MMM dd, yyyy • hh:mm a').format(_paidAt)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Reference / OR No. (optional)', style: AppTheme.bodyMedium),
            const SizedBox(height: 6),
            TextField(
              controller: _refController,
              decoration: const InputDecoration(hintText: 'e.g. OR-001234'),
            ),
            const SizedBox(height: 16),
            Text('Note (optional)', style: AppTheme.bodyMedium),
            const SizedBox(height: 6),
            TextField(
              controller: _noteController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'e.g. Partial payment for filing fees',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: AppTheme.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.royalBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save Payment'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet to issue a new invoice against one of the attorney's cases.
class _CreateInvoiceSheet extends StatefulWidget {
  final String attorneyId;
  final BillingService billing;

  const _CreateInvoiceSheet({
    required this.attorneyId,
    required this.billing,
  });

  @override
  State<_CreateInvoiceSheet> createState() => _CreateInvoiceSheetState();
}

class _CreateInvoiceSheetState extends State<_CreateInvoiceSheet> {
  final CaseService _caseService = CaseService();
  final TextEditingController _feeController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _selectedCaseId;
  List<CaseModel> _cases = const [];
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _feeController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final fee = double.tryParse(_feeController.text.trim());
    CaseModel? selectedCase;
    for (final c in _cases) {
      if (c.id == _selectedCaseId) {
        selectedCase = c;
        break;
      }
    }
    if (selectedCase == null) {
      setState(() => _error = 'Please select a case.');
      return;
    }
    if (fee == null || fee <= 0) {
      setState(() => _error = 'Enter a valid legal fee amount.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      String? clientName;
      try {
        final userDoc = await _firestore
            .collection('users')
            .doc(selectedCase.clientId)
            .get();
        final data = userDoc.data();
        clientName = (data?['fullName'] ?? data?['name']) as String?;
      } catch (_) {}

      // Use the case's own number if it has one (caseNumber / caseNo).
      String? caseNumber;
      try {
        final caseDoc = await _firestore
            .collection('cases')
            .doc(selectedCase.id)
            .get();
        final cdata = caseDoc.data();
        caseNumber = (cdata?['caseNumber'] ?? cdata?['caseNo']) as String?;
      } catch (_) {}

      final result = await widget.billing.createInvoice(
        clientId: selectedCase.clientId,
        clientName: clientName,
        attorneyId: widget.attorneyId,
        caseId: selectedCase.id,
        caseNumber: caseNumber,
        caseTitle: selectedCase.caseTitle,
        totalLegalFee: fee,
        description: _descController.text.trim().isEmpty
            ? null
            : _descController.text.trim(),
        createdBy: FirebaseAuth.instance.currentUser?.uid,
      );
      if (!mounted) return;
      if (result.success) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice issued successfully.')),
        );
      } else {
        setState(() {
          _submitting = false;
          _error = result.message ?? 'Failed to create invoice.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Failed to create invoice: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.borderGray,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Issue New Invoice', style: AppTheme.heading4),
            const SizedBox(height: 16),
            Text('Case', style: AppTheme.bodyMedium),
            const SizedBox(height: 6),
            StreamBuilder<List<InvoiceModel>>(
              stream: widget.billing.streamInvoicesForAttorney(widget.attorneyId),
              builder: (context, invoiceSnapshot) {
                return StreamBuilder<List<CaseModel>>(
                  stream: _caseService.getCasesForUser(
                    widget.attorneyId,
                    'attorney',
                  ),
                  builder: (context, caseSnapshot) {
                    if (caseSnapshot.connectionState ==
                            ConnectionState.waiting ||
                        invoiceSnapshot.connectionState ==
                            ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: LinearProgressIndicator(),
                      );
                    }

                    final paidCaseIds = <String>{};
                    for (final invoice in invoiceSnapshot.data ??
                        const <InvoiceModel>[]) {
                      final caseId = invoice.caseId;
                      if (caseId != null &&
                          caseId.isNotEmpty &&
                          !invoice.isCancelled &&
                          invoice.isPaid) {
                        paidCaseIds.add(caseId);
                      }
                    }

                    // De-duplicate by id so the dropdown never has two items with
                    // the same value (Flutter asserts on that).
                    final byId = <String, CaseModel>{};
                    for (final c in caseSnapshot.data ?? const <CaseModel>[]) {
                      if (!paidCaseIds.contains(c.id)) {
                        byId[c.id] = c;
                      }
                    }
                    _cases = byId.values.toList();

                    if (_cases.isEmpty) {
                      return Text(
                        paidCaseIds.isEmpty
                            ? 'No cases available to bill.'
                            : 'All cases are fully paid. No new invoice needed.',
                        style: AppTheme.bodySmall
                            .copyWith(color: AppTheme.mutedText),
                      );
                    }

                    final valueId = byId.containsKey(_selectedCaseId)
                        ? _selectedCaseId
                        : null;

                    return DropdownButtonFormField<String>(
                      initialValue: valueId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        hintText: 'Select a case',
                      ),
                      items: _cases
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: c.id,
                              child: Text(
                                c.caseTitle,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (id) => setState(() => _selectedCaseId = id),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 16),
            Text(Currency.label('Total Legal Fee'), style: AppTheme.bodyMedium),
            const SizedBox(height: 6),
            TextField(
              controller: _feeController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: 'e.g. 25000'),
            ),
            const SizedBox(height: 16),
            Text('Description (optional)', style: AppTheme.bodyMedium),
            const SizedBox(height: 6),
            TextField(
              controller: _descController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'e.g. Filing fees and consultation',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: AppTheme.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.royalBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Issue Invoice'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
