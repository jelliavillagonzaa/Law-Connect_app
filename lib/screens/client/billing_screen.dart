import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';
import '../../models/invoice_model.dart';
import '../../models/payment_model.dart';
import '../../services/billing_service.dart';
import '../../utils/currency.dart';
import '../../widgets/empty_state.dart';

/// Client-facing billing (read-only). Shows the outstanding balance, every
/// invoice's total legal fee / amount paid / remaining balance / status, and
/// the full payment history. Payments are made physically at the law office;
/// the attorney or staff records each one.
class BillingScreen extends StatelessWidget {
  const BillingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final billing = BillingService();
    final clientId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: AppTheme.lightGray,
      appBar: AppBar(
        title: const Text('Billing & Payments'),
        backgroundColor: AppTheme.royalBlue,
      ),
      body: clientId == null
          ? const EmptyState(
              icon: Icons.lock_outline,
              title: 'Not signed in',
              message: 'Please sign in to view your billing.',
            )
          : StreamBuilder<List<InvoiceModel>>(
              stream: billing.streamInvoicesForClient(clientId),
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
                final invoices = (snapshot.data ?? [])
                    .where((i) => !i.isCancelled)
                    .toList();
                if (invoices.isEmpty) {
                  return const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No invoices yet',
                    message:
                        'When your attorney issues a legal fee, it will appear '
                        'here with your balance and payment history.',
                  );
                }

                final outstanding =
                    invoices.fold<double>(0, (s, i) => s + i.remainingBalance);
                final totalFees =
                    invoices.fold<double>(0, (s, i) => s + i.totalLegalFee);
                final totalPaid =
                    invoices.fold<double>(0, (s, i) => s + i.amountPaid);

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    _OutstandingCard(
                      outstanding: outstanding,
                      totalFees: totalFees,
                      totalPaid: totalPaid,
                    ),
                    const SizedBox(height: 24),
                    Text('Your Invoices', style: AppTheme.heading4),
                    const SizedBox(height: 12),
                    ...invoices.map((inv) => _InvoiceCard(invoice: inv)),
                    const SizedBox(height: 24),
                    _PaymentHistorySection(
                      stream: billing.streamPaymentsForClient(clientId),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _OutstandingCard extends StatelessWidget {
  final double outstanding;
  final double totalFees;
  final double totalPaid;

  const _OutstandingCard({
    required this.outstanding,
    required this.totalFees,
    required this.totalPaid,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Text(
            'Outstanding Balance',
            style: AppTheme.bodyMedium.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Text(
            Currency.peso(outstanding),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _miniStat('Total Legal Fees', Currency.peso(totalFees)),
              ),
              Container(width: 1, height: 36, color: Colors.white24),
              Expanded(
                child: _miniStat('Total Paid', Currency.peso(totalPaid)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final InvoiceModel invoice;

  const _InvoiceCard({required this.invoice});

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
            ],
          ),
          if (invoice.description?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(invoice.description!, style: AppTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          _row('Total Legal Fee', Currency.peso(invoice.totalLegalFee)),
          const SizedBox(height: 6),
          _row('Amount Paid', Currency.peso(invoice.amountPaid)),
          const Divider(height: 20),
          _row(
            'Remaining Balance',
            Currency.peso(invoice.remainingBalance),
            emphasize: true,
          ),
          if (invoice.hasOutstanding) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.royalBlue.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.storefront_outlined,
                      size: 18, color: AppTheme.royalBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Please settle this balance at the law office. '
                      'Payments are recorded by your attorney or staff.',
                      style: AppTheme.bodySmall
                          .copyWith(color: AppTheme.royalBlue),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool emphasize = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: emphasize
              ? AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600)
              : AppTheme.bodyMedium.copyWith(color: AppTheme.mutedText),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasize ? 18 : 14,
            fontWeight: emphasize ? FontWeight.bold : FontWeight.w600,
            color: emphasize ? AppTheme.royalBlue : AppTheme.darkText,
          ),
        ),
      ],
    );
  }
}

/// Status pill (Unpaid / Partially Paid / Fully Paid / Cancelled). Shared.
class StatusBadge extends StatelessWidget {
  final InvoiceModel invoice;

  const StatusBadge({super.key, required this.invoice});

  @override
  Widget build(BuildContext context) {
    Color color;
    if (invoice.isCancelled) {
      color = AppTheme.mutedText;
    } else if (invoice.isPaid) {
      color = AppTheme.success;
    } else if (invoice.amountPaid > 0) {
      color = AppTheme.warning;
    } else {
      color = AppTheme.royalBlue;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        invoice.statusLabel,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Read-only payment history list shared by client/firm screens. Only settled
/// payments are shown.
class _PaymentHistorySection extends StatelessWidget {
  final Stream<List<PaymentModel>> stream;

  const _PaymentHistorySection({required this.stream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PaymentModel>>(
      stream: stream,
      builder: (context, snapshot) {
        final payments =
            (snapshot.data ?? []).where((p) => p.isSuccessful).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Payment History', style: AppTheme.heading4),
            const SizedBox(height: 12),
            if (payments.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.cardDecoration,
                child: Text(
                  'No payments yet.',
                  style:
                      AppTheme.bodyMedium.copyWith(color: AppTheme.mutedText),
                ),
              )
            else
              ...payments.map((p) => PaymentHistoryTile(payment: p)),
          ],
        );
      },
    );
  }
}

/// A single payment row (date, method, amount). Reused by firm screens.
class PaymentHistoryTile extends StatelessWidget {
  final PaymentModel payment;
  final bool showClientName;

  /// When provided (firm screens), shows a delete/void button on the tile.
  final VoidCallback? onDelete;

  const PaymentHistoryTile({
    super.key,
    required this.payment,
    this.showClientName = false,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = payment.isSuccessful ? AppTheme.success : AppTheme.warning;
    final date = payment.paidAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              payment.isSuccessful
                  ? Icons.check_circle_outline
                  : Icons.schedule,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.methodLabel,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('MMM dd, yyyy • hh:mm a').format(date),
                  style: AppTheme.bodySmall,
                ),
                Text(
                  '${payment.displayPaymentId} • Case No: ${payment.displayCaseNumber}',
                  style: AppTheme.bodySmall,
                ),
                if (showClientName && payment.clientName?.isNotEmpty == true)
                  Text(
                    'Client: ${payment.clientName}',
                    style: AppTheme.bodySmall,
                  ),
                if (payment.referenceNo?.isNotEmpty == true)
                  Text(
                    'Ref: ${payment.referenceNo}',
                    style: AppTheme.bodySmall,
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Currency.peso(payment.amount),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Recorded by',
                style: AppTheme.bodySmall,
              ),
              Text(
                payment.recordedByLabel,
                style: AppTheme.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.darkText,
                ),
              ),
            ],
          ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Delete payment',
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}
