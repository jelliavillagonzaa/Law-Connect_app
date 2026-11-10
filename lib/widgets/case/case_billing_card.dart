import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/case_model.dart';
import '../../models/invoice_model.dart';
import '../../models/payment_model.dart';
import '../../services/billing_service.dart';
import '../../screens/billing/billing_management_screen.dart'
    show openPaymentHistoryScreen;
import '../../theme/app_theme.dart';
import '../../utils/currency.dart';

/// Embedded billing and payment card for case detail views.
///
/// Displays the total agreed legal fee, amount paid, and remaining balance
/// with real-time updates. Provides in-place payment recording and an
/// expandable payment history timeline.
class CaseBillingCard extends StatefulWidget {
  final CaseModel caseModel;
  final bool canManage;
  final String recorderRole;
  final String? recorderName;

  const CaseBillingCard({
    super.key,
    required this.caseModel,
    this.canManage = true,
    this.recorderRole = 'staff',
    this.recorderName,
  });

  @override
  State<CaseBillingCard> createState() => _CaseBillingCardState();
}

class _CaseBillingCardState extends State<CaseBillingCard> {
  final BillingService _billing = BillingService();
  bool _historyExpanded = true;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<InvoiceModel>>(
      stream: _billing.streamInvoicesForCase(widget.caseModel.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
          );
        }

        final invoices = (snapshot.data ?? [])
            .where((i) => !i.isCancelled)
            .toList();

        if (invoices.isEmpty) {
          return _buildNoInvoiceCard();
        }

        final invoice = invoices.first;
        return _buildActiveBillingCard(invoice);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Empty State: No invoice set yet
  // ---------------------------------------------------------------------------
  Widget _buildNoInvoiceCard() {
    Widget buildSetFeeButton() {
      return SizedBox(
        height: 38,
        child: ElevatedButton.icon(
          onPressed: () => _openSetFeeDialog(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.royalBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
          label: const Text(
            'Set Agreed Legal Fee',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
      ),
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 560;

          if (isWide) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppTheme.royalBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: AppTheme.royalBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Case Billing & Legal Fees',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.darkText,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'No fee schedule has been set for this case yet.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.canManage) ...[
                    const SizedBox(width: 16),
                    buildSetFeeButton(),
                  ],
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: AppTheme.royalBlue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_outlined,
                        color: AppTheme.royalBlue,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Case Billing & Legal Fees',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.darkText,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'No fee schedule has been set for this case yet.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.mutedText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (widget.canManage) ...[
                  const SizedBox(height: 12),
                  buildSetFeeButton(),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Active Invoice Card
  // ---------------------------------------------------------------------------
  Widget _buildActiveBillingCard(InvoiceModel invoice) {
    final remaining = invoice.remainingBalance;
    final total = invoice.totalLegalFee;
    final paid = invoice.amountPaid;
    final percent = total > 0 ? (paid / total).clamp(0.0, 1.0) : 1.0;

    final Color statusColor;
    final String statusText;
    if (invoice.isPaid || remaining <= 0) {
      statusColor = Colors.green.shade700;
      statusText = 'FULLY PAID';
    } else if (invoice.isPartiallyPaid) {
      statusColor = const Color(0xFFD97706); // amber/orange
      statusText = 'PARTIALLY PAID';
    } else {
      statusColor = const Color(0xFFDC2626); // red
      statusText = 'UNPAID';
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
      ),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppTheme.royalBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: AppTheme.royalBlue,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Case Billing & Payments',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.darkText,
                        ),
                      ),
                      Text(
                        'Official Legal Fee Ledger',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

          // Financial Metrics Row (3 balanced columns side-by-side)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatPill(
                    title: 'Total Legal Fee',
                    amount: total,
                    accentColor: AppTheme.royalBlue,
                    bgColor: const Color(0xFFF1F5F9),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatPill(
                    title: 'Total Paid',
                    amount: paid,
                    accentColor: Colors.green.shade700,
                    bgColor: const Color(0xFFF0FDF4),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatPill(
                    title: 'Remaining Balance',
                    amount: remaining,
                    accentColor: remaining > 0
                        ? const Color(0xFFD97706)
                        : Colors.green.shade700,
                    bgColor: remaining > 0
                        ? const Color(0xFFFFFBEB)
                        : const Color(0xFFF0FDF4),
                    isHighlight: true,
                  ),
                ),
              ],
            ),
          ),

          // Progress Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Payment Progress',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.mutedText,
                      ),
                    ),
                    Text(
                      '${(percent * 100).toStringAsFixed(1)}% settled',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: remaining <= 0
                            ? Colors.green.shade700
                            : const Color(0xFF2563EB),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: percent,
                    minHeight: 5,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      remaining <= 0
                          ? Colors.green.shade600
                          : const Color(0xFF2563EB),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Action Buttons
          if (widget.canManage)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(
                children: [
                  if (remaining > 0) ...[
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              _openRecordPaymentSheet(context, invoice),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: const Color(0xFFFBBF24), // gold text
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.payment_rounded, size: 15),
                          label: const Text(
                            'Record Payment',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  SizedBox(
                    height: 36,
                    child: OutlinedButton.icon(
                      onPressed: () => _openSetFeeDialog(
                        context,
                        existingInvoice: invoice,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.royalBlue,
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.edit_note_rounded, size: 16),
                      label: const Text(
                        'Adjust Fee',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

          // Payment History Expansion Section
          _buildHistorySection(invoice),
        ],
      ),
    );
  }

  Widget _buildStatPill({
    required String title,
    required double amount,
    required Color accentColor,
    required Color bgColor,
    bool isHighlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isHighlight
              ? accentColor.withValues(alpha: 0.35)
              : const Color(0xFFE2E8F0),
          width: isHighlight ? 1.2 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.mutedText,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: CurrencyText(
              amount: amount,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Payment History & Receipts Timeline
  // ---------------------------------------------------------------------------
  Widget _buildHistorySection(InvoiceModel invoice) {
    return StreamBuilder<List<PaymentModel>>(
      stream: _billing.streamPaymentsForInvoice(invoice.id),
      builder: (context, snapshot) {
        final payments = snapshot.data ?? [];

        return Column(
          children: [
            InkWell(
              onTap: () => setState(() => _historyExpanded = !_historyExpanded),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(
                  children: [
                    const Icon(
                      Icons.history_rounded,
                      size: 20,
                      color: AppTheme.royalBlue,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Payment History',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.darkText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.royalBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${payments.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.royalBlue,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _historyExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppTheme.mutedText,
                    ),
                  ],
                ),
              ),
            ),
            if (_historyExpanded) ...[
              if (payments.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppTheme.borderGray.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'No payments have been recorded for this case yet.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.mutedText,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: payments.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final payment = payments[index];
                      return _buildPaymentReceiptTile(payment);
                    },
                  ),
                ),
              if (widget.canManage &&
                  widget.recorderRole.toLowerCase() != 'client')
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () => openPaymentHistoryScreen(
                        context,
                        recorderRole: widget.recorderRole,
                        recorderName: widget.recorderName,
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.royalBlue,
                        backgroundColor:
                            AppTheme.royalBlue.withValues(alpha: 0.06),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.table_view_rounded, size: 16),
                      label: const Text(
                        'View All Firm Transactions Report',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildPaymentReceiptTile(PaymentModel payment) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.receipt_rounded,
              color: Colors.green.shade700,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      Currency.peso(payment.amount),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.green.shade800,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        payment.methodLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('MMM dd, yyyy • hh:mm a').format(payment.paidAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.mutedText,
                  ),
                ),
                if (payment.referenceNo?.isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Ref / OR #: ${payment.referenceNo}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.darkText,
                    ),
                  ),
                ],
                if (payment.recordedByName?.isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Received by: ${payment.recordedByName}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.mutedText,
                    ),
                  ),
                ],
                if (payment.note?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    payment.note!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Color(0xFF475569),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Dialog: Record Payment
  // ---------------------------------------------------------------------------
  Future<void> _openRecordPaymentSheet(
    BuildContext context,
    InvoiceModel invoice,
  ) async {
    final amountController = TextEditingController();
    final refController = TextEditingController();
    final noteController = TextEditingController();
    String method = PaymentMethod.cash;
    DateTime paidAt = DateTime.now();
    String? error;
    bool isSubmitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            void applyQuickAmount(double val) {
              setSheetState(() {
                amountController.text = val.toStringAsFixed(2);
                error = null;
              });
            }

            Future<void> submit() async {
              final amt = double.tryParse(amountController.text.trim());
              if (amt == null || amt <= 0) {
                setSheetState(() => error = 'Please enter a valid amount.');
                return;
              }
              if (amt > invoice.remainingBalance + 0.001) {
                setSheetState(() => error =
                    'Amount cannot exceed the balance of ${Currency.peso(invoice.remainingBalance)}.');
                return;
              }

              setSheetState(() {
                isSubmitting = true;
                error = null;
              });

              final user = FirebaseAuth.instance.currentUser;
              final uid = user?.uid ?? '';
              final name = widget.recorderName ?? user?.displayName ?? 'Staff';

              final result = await _billing.recordPayment(
                invoice: invoice,
                amount: amt,
                method: method,
                referenceNo: refController.text.trim(),
                note: noteController.text.trim(),
                paidAt: paidAt,
                recordedBy: uid,
                recordedByName: name,
                recordedByRole: widget.recorderRole,
              );

              if (!sheetContext.mounted) return;

              if (result.success) {
                Navigator.of(sheetContext).pop();
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.green.shade800,
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          'Payment of ${Currency.peso(amt)} recorded successfully!',
                        ),
                      ],
                    ),
                  ),
                );
              } else {
                setSheetState(() {
                  isSubmitting = false;
                  error = result.message ?? 'Failed to record payment.';
                });
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
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
                    Row(
                      children: [
                        const Icon(
                          Icons.payments_rounded,
                          color: AppTheme.royalBlue,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Record Client Payment',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.darkText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.caseModel.caseTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.mutedText,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Balance Banner
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Outstanding Balance Due:',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF92400E),
                            ),
                          ),
                          Text(
                            Currency.peso(invoice.remainingBalance),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Amount input
                    Text(
                      Currency.label('Amount Received'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      autofocus: true,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 14, right: 8),
                          child: Text(
                            Currency.symbol,
                            style: Currency.style(
                              const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.royalBlue,
                              ),
                            ),
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 0,
                          minHeight: 0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),

                    // Quick percentage / full balance buttons
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('Full Balance'),
                          onPressed: () =>
                              applyQuickAmount(invoice.remainingBalance),
                        ),
                        if (invoice.remainingBalance >= 2000)
                          ActionChip(
                            label: const Text('50%'),
                            onPressed: () => applyQuickAmount(
                              invoice.remainingBalance * 0.5,
                            ),
                          ),
                        if (invoice.remainingBalance >= 5000)
                          ActionChip(
                            label: const Text('₱5,000'),
                            onPressed: () => applyQuickAmount(5000),
                          ),
                        if (invoice.remainingBalance >= 10000)
                          ActionChip(
                            label: const Text('₱10,000'),
                            onPressed: () => applyQuickAmount(10000),
                          ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Payment Method Dropdown
                    const Text(
                      'Payment Method',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: method,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      items: PaymentMethod.all
                          .map(
                            (m) => DropdownMenuItem(
                              value: m,
                              child: Text(PaymentMethod.label(m)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setSheetState(() => method = v);
                      },
                    ),

                    const SizedBox(height: 14),

                    // OR / Reference Number
                    const Text(
                      'Official Receipt (OR) / Ref Number',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: refController,
                      decoration: InputDecoration(
                        hintText: 'e.g. OR-2026-0042',
                        prefixIcon: const Icon(Icons.tag, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Note / Remarks
                    const Text(
                      'Notes / Remarks (optional)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: noteController,
                      decoration: InputDecoration(
                        hintText: 'e.g. Received at front office',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),

                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Colors.red.shade700,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                error!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.red.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isSubmitting ? null : submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: const Color(0xFFFBBF24),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFFFBBF24),
                                  ),
                                ),
                              )
                            : const Text(
                                'Save Payment & Deduct Balance',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Dialog: Set or Adjust Agreed Legal Fee
  // ---------------------------------------------------------------------------
  Future<void> _openSetFeeDialog(
    BuildContext context, {
    InvoiceModel? existingInvoice,
  }) async {
    final feeController = TextEditingController(
      text: existingInvoice != null
          ? existingInvoice.totalLegalFee.toStringAsFixed(2)
          : '',
    );
    final descController = TextEditingController(
      text: existingInvoice?.description ?? '',
    );
    String? error;
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> save() async {
              final fee = double.tryParse(feeController.text.trim());
              if (fee == null || fee <= 0) {
                setDialogState(() => error = 'Please enter a valid legal fee.');
                return;
              }

              if (existingInvoice != null &&
                  fee < existingInvoice.amountPaid - 0.001) {
                setDialogState(() => error =
                    'Total fee cannot be lower than the amount already paid (${Currency.peso(existingInvoice.amountPaid)}).');
                return;
              }

              setDialogState(() {
                isSubmitting = true;
                error = null;
              });

              final user = FirebaseAuth.instance.currentUser;
              final uid = user?.uid ?? '';

              final BillingResult result;
              if (existingInvoice != null) {
                result = await _billing.updateInvoiceFee(
                  invoice: existingInvoice,
                  totalLegalFee: fee,
                  description: descController.text.trim(),
                );
              } else {
                result = await _billing.createInvoice(
                  clientId: widget.caseModel.clientId,
                  attorneyId: widget.caseModel.attorneyId ?? uid,
                  totalLegalFee: fee,
                  caseId: widget.caseModel.id,
                  caseTitle: widget.caseModel.caseTitle,
                  description: descController.text.trim().isNotEmpty
                      ? descController.text.trim()
                      : 'Agreed Case Legal Representation Fee',
                  createdBy: uid,
                  staffId: uid,
                );
              }

              if (!dialogContext.mounted) return;

              if (result.success) {
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.green.shade800,
                    content: Text(
                      existingInvoice != null
                          ? 'Case fee adjusted to ${Currency.peso(fee)}.'
                          : 'Case legal fee set to ${Currency.peso(fee)}.',
                    ),
                  ),
                );
              } else {
                setDialogState(() {
                  isSubmitting = false;
                  error = result.message ?? 'Failed to save fee.';
                });
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  const Icon(
                    Icons.account_balance_wallet,
                    color: AppTheme.royalBlue,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    existingInvoice != null
                        ? 'Adjust Legal Fee'
                        : 'Set Case Legal Fee',
                    style: const TextStyle(fontSize: 18),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.caseModel.caseTitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.mutedText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      Currency.label('Total Agreed Legal Fee'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: feeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      autofocus: true,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g. 50000',
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 14, right: 8),
                          child: Text(
                            Currency.symbol,
                            style: Currency.style(
                              const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.royalBlue,
                              ),
                            ),
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 0,
                          minHeight: 0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Description / Agreement Note',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: descController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'e.g. Legal representation & filing fee',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        error!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting ? null : save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.royalBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save Fee'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
