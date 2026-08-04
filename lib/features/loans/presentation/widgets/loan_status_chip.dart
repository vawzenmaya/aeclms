// lib/features/loans/presentation/widgets/loan_status_chip.dart

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class LoanStatusChip extends StatelessWidget {
  const LoanStatusChip({super.key, required this.status});
  final String status;

  String get _label {
    switch (status) {
      case 'draft':
        return 'Draft';
      case 'awaiting_guarantor':
        return 'Awaiting guarantor';
      case 'in_review':
        return 'In review';
      case 'returned_to_applicant':
        return 'Returned to you';
      case 'rejected':
        return 'Rejected';
      case 'approved':
        return 'Approved';
      case 'disbursed':
        return 'Disbursed';
      case 'completed':
        return 'Completed';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = StatusColors.forLoanStatus(status, scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(_label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}
