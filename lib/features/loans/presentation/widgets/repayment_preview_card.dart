// lib/features/loans/presentation/widgets/repayment_preview_card.dart

import 'package:flutter/material.dart';

import '../../domain/loan_calculations.dart';

class RepaymentPreviewCard extends StatelessWidget {
  const RepaymentPreviewCard({super.key, required this.preview, required this.amountRequested});

  final LoanPreview preview;
  final double amountRequested;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final scheme = Theme.of(context).colorScheme;
    String fmt(num? v) => v == null ? '—' : v.toStringAsFixed(2);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Repayment summary', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _row('Interest rate', preview.interestMethod == 'flat'
                ? '${preview.interestRate}% flat (one-time)'
                : '${preview.interestRate}% p.a. (reducing balance)'),
            _row('Processing fee', fmt(preview.processingFee)),
            _row('Monthly installment', fmt(preview.installmentAmount), emphasize: true),
            if (preview.debtToIncomeRatio != null)
              _row(
                'Repayment vs net pay',
                '${(preview.debtToIncomeRatio! * 100).toStringAsFixed(1)}%',
                warn: preview.dtiExceeded,
              ),
            if (preview.dtiExceeded) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFD9534F).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'This repayment exceeds 20% of net pay. Your application can still be '
                  'submitted, but the committee will see this flagged.',
                  style: TextStyle(color: Color(0xFFD9534F)),
                ),
              ),
            ],
            if (preview.termExceeded) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFD9534F).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'This loan type allows a maximum of ${preview.maxTermMonths} months. '
                  'Please choose an earlier end date.',
                  style: const TextStyle(color: Color(0xFFD9534F)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool emphasize = false, bool warn = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
              color: warn ? const Color(0xFFD9534F) : null,
            ),
          ),
        ],
      ),
    );
  }
}
