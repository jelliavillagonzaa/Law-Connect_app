import 'package:flutter_test/flutter_test.dart';
import 'package:law_connect4/models/invoice_model.dart';
import 'package:law_connect4/models/payment_model.dart';
import 'package:law_connect4/utils/payment_history_report.dart';

InvoiceModel _invoice(String id) {
  final now = DateTime(2026, 9, 30);
  return InvoiceModel(
    id: id,
    clientId: 'c1',
    attorneyId: 'a1',
    totalLegalFee: 6000,
    amountPaid: 2000,
    createdAt: now,
    updatedAt: now,
  );
}

PaymentModel _payment({
  required String invoiceId,
  required DateTime paidAt,
}) {
  return PaymentModel(
    id: 'p-$invoiceId-${paidAt.millisecondsSinceEpoch}',
    invoiceId: invoiceId,
    clientId: 'c1',
    attorneyId: 'a1',
    amount: 2000,
    paidAt: paidAt,
    createdAt: paidAt,
  );
}

PaymentReportRow _row(String invoiceId, String client) {
  final invoice = _invoice(invoiceId);
  return PaymentReportRow(
    clientName: client,
    caseNumber: 'CASE-1',
    totalFee: invoice.totalLegalFee,
    totalPaid: invoice.amountPaid,
    remainingBalance: invoice.remainingBalance,
    statusLabel: 'PARTIAL',
    lastPaymentDate: DateTime(2026, 9, 30),
    invoice: invoice,
  );
}

void main() {
  test('staff prepared by keeps the staff name', () {
    expect(
      paymentHistoryPreparedBy(
        recorderRole: 'staff',
        recorderName: 'apaostaff',
        attorneyDisplayName: 'attorney',
      ),
      'apaostaff',
    );
    expect(paymentHistoryPreparedByTitle('staff'), 'Staff');
  });

  test('attorney prepared by prefixes Atty.', () {
    expect(
      paymentHistoryPreparedBy(
        recorderRole: 'attorney',
        recorderName: 'attorney',
        attorneyDisplayName: 'attorney',
      ),
      'Atty. attorney',
    );
    expect(paymentHistoryPreparedByTitle('attorney'), 'Attorney at Law');
  });

  test('staff header contact uses staff phone and email', () {
    final contact = paymentHistoryHeaderContact(
      recorderRole: 'staff',
      attorneyData: {
        'phone': '09351914214',
        'email': 'attorney@gmail.com',
      },
      recorderData: {
        'phoneNumber': '09171234567',
        'email': 'apaostaff@gmail.com',
      },
    );
    expect(contact.phone, '09171234567');
    expect(contact.email, 'apaostaff@gmail.com');
  });

  test('attorney header contact keeps attorney phone and email', () {
    final contact = paymentHistoryHeaderContact(
      recorderRole: 'attorney',
      attorneyData: {
        'phone': '09351914214',
        'email': 'attorney@gmail.com',
      },
      recorderData: {
        'phoneNumber': '09171234567',
        'email': 'apaostaff@gmail.com',
      },
    );
    expect(contact.phone, '09351914214');
    expect(contact.email, 'attorney@gmail.com');
  });

  test('month and year keep only cases with a payment in that period', () {
    final rows = [_row('inv-sep', 'Joren'), _row('inv-aug', 'Other')];
    final payments = [
      _payment(invoiceId: 'inv-sep', paidAt: DateTime(2026, 9, 30)),
      _payment(invoiceId: 'inv-aug', paidAt: DateTime(2026, 8, 1)),
    ];

    final filtered = filterReportRowsByPaidPeriod(
      rows,
      payments,
      year: 2026,
      month: 9,
    );

    expect(filtered.map((r) => r.invoice.id), ['inv-sep']);
    expect(
      paymentHistoryPeriodNote(
        const PaymentHistoryPeriod(
          fromYear: 2026,
          fromMonth: 9,
          toYear: 2026,
          toMonth: 9,
        ),
      ),
      contains('September 2026'),
    );
  });

  test('last 3 months includes payments across the range', () {
    final rows = [
      _row('inv-jul', 'A'),
      _row('inv-aug', 'B'),
      _row('inv-jun', 'C'),
    ];
    final payments = [
      _payment(invoiceId: 'inv-jul', paidAt: DateTime(2026, 7, 2)),
      _payment(invoiceId: 'inv-aug', paidAt: DateTime(2026, 8, 2)),
      _payment(invoiceId: 'inv-jun', paidAt: DateTime(2026, 6, 2)),
    ];
    final period = PaymentHistoryPeriod.lastMonths(DateTime(2026, 9, 30), 3);
    final filtered = filterReportRowsByPaidPeriod(
      rows,
      payments,
      period: period,
    );
    expect(filtered.map((r) => r.invoice.id), ['inv-jul', 'inv-aug']);
    expect(paymentHistoryPeriodNote(period), contains('July 2026'));
    expect(paymentHistoryPeriodNote(period), contains('September 2026'));
  });

  test('archived invoice with payments stays on payment history', () {
    final now = DateTime(2026, 9, 30);
    final archived = InvoiceModel(
      id: 'inv-kept',
      clientId: 'c1',
      attorneyId: 'a1',
      totalLegalFee: 6000,
      amountPaid: 2000,
      status: InvoiceStatus.cancelled,
      createdAt: now,
      updatedAt: now,
    );
    final unpaidArchived = InvoiceModel(
      id: 'inv-gone',
      clientId: 'c1',
      attorneyId: 'a1',
      totalLegalFee: 1000,
      status: InvoiceStatus.cancelled,
      createdAt: now,
      updatedAt: now,
    );
    final payments = [
      _payment(invoiceId: 'inv-kept', paidAt: now),
    ];
    expect(includeInvoiceInPaymentHistory(archived, payments), isTrue);
    expect(includeInvoiceInPaymentHistory(unpaidArchived, payments), isFalse);
    expect(paymentStatusCode(archived), 'PARTIAL');
  });

  test('year dropdown includes a range plus older payment years', () {
    final years = paymentHistoryFilterYears(
      [_payment(invoiceId: 'old', paidAt: DateTime(2020, 1, 1))],
      now: DateTime(2026, 9, 30),
    );
    expect(years, [2027, 2026, 2025, 2024, 2023, 2020]);
  });

  test('all years and months leaves every case', () {
    final rows = [_row('a', 'A'), _row('b', 'B')];
    expect(
      filterReportRowsByPaidPeriod(rows, const [], year: null, month: null),
      rows,
    );
  });
}
