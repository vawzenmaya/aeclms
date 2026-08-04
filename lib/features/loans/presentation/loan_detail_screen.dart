// lib/features/loans/presentation/loan_detail_screen.dart

import 'package:aeclms/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/data/auth_service.dart';
import '../data/loan_repository.dart';
import 'widgets/loan_status_chip.dart';

class LoanDetailScreen extends StatefulWidget {
  const LoanDetailScreen({
    super.key,
    required this.repository,
    required this.profile,
    required this.loanId,
  });

  final LoanRepository repository;
  final Profile profile;
  final String loanId;

  @override
  State<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends State<LoanDetailScreen> {
  Map<String, dynamic>? _loan;
  Map<String, dynamic>? _currentStage;
  List<Map<String, dynamic>> _allStages = [];
  bool _loading = true;
  bool _acting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final loan = await widget.repository.fetchLoan(widget.loanId);
    Map<String, dynamic>? currentStage;
    if (loan['status'] == 'in_review') {
      currentStage = await widget.repository.fetchCurrentStage(loan);
    }
    final stages = await widget.repository.fetchAllStages(loan['template_id'] as String);
    if (!mounted) return;
    setState(() {
      _loan = loan;
      _currentStage = currentStage;
      _allStages = stages;
      _loading = false;
    });
  }

  bool get _isGuarantorPending =>
      _loan!['guarantor_id'] == widget.profile.id && _loan!['guarantor_response'] == 'pending';

  bool get _isMyApprovalTurn {
    if (_loan!['status'] != 'in_review' || _currentStage == null) return false;
    // We don't have the user's roles cached here; rely on RLS + the stage
    // fetch: if fetchCurrentStage succeeded and the loan is visible to us
    // as a non-applicant/non-guarantor, the dashboard already filtered this,
    // but for direct navigation we double check via a lightweight role probe.
    return _myRoleIds != null && _myRoleIds!.contains(_currentStage!['role_id']);
  }

  Set<int>? _myRoleIds;

  Future<void> _ensureRoles() async {
    if (_myRoleIds != null) return;
    final client = Supabase.instance.client;
    final rows = await client
        .from('user_roles')
        .select('role_id')
        .eq('profile_id', widget.profile.id)
        .eq('community_id', widget.profile.communityId!)
        .eq('is_active', true);
    _myRoleIds = (rows as List).map((r) => r['role_id'] as int).toSet();
  }

  Future<void> _guarantorRespond(bool confirm) async {
    String? comment;
    if (!confirm) {
      comment = await _promptForComment('Why are you declining to guarantee this loan?');
      if (comment == null || comment.trim().isEmpty) return;
    }
    setState(() => _acting = true);
    try {
      await widget.repository.respondAsGuarantor(widget.loanId, confirm: confirm, comment: comment);
      await _load();
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _act(String action) async {
    String? comment;
    DateTime? firstDeductionDate;

    if (action == 'rejected') {
      comment = await _promptForComment('Reason for rejecting (required)');
      if (comment == null || comment.trim().isEmpty) return;
    } else if (action == 'approved' && _currentStage!['is_disbursement_stage'] == true) {
      firstDeductionDate = await showDatePicker(
        context: context,
        initialDate: DateTime.now().add(const Duration(days: 30)),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 366)),
        helpText: 'First deduction date',
      );
      if (firstDeductionDate == null) return;
    }

    setState(() => _acting = true);
    try {
      await widget.repository.recordStageAction(
        loanId: widget.loanId,
        stageId: _currentStage!['id'] as String,
        actorId: widget.profile.id,
        action: action,
        comment: comment,
        firstDeductionDate: firstDeductionDate,
      );
      await _load();
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<String?> _promptForComment(String title) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, maxLines: 3, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Confirm')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _loan == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return FutureBuilder<void>(
      future: _ensureRoles(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return _buildLoaded(context);
      },
    );
  }

  Widget _buildLoaded(BuildContext context) {
    final loan = _loan!;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(loan['full_name'] as String? ?? 'Loan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${loan['amount_requested']}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              LoanStatusChip(status: loan['status'] as String? ?? 'draft'),
            ],
          ),
          Text(loan['amount_in_words'] as String? ?? '', style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),

          _infoCard(context, [
            _row('Loan category', loan['loan_category'] == 'emergency' ? 'Emergency' : 'Normal'),
            _row('Type', loan['loan_type'] == 'topup' ? 'Top-up' : 'New'),
            _row('Purpose', loan['purpose'] as String? ?? '-'),
            _row('Interest rate', '${loan['interest_rate']}% (${loan['interest_method']})'),
            _row('Monthly installment', '${loan['installment_amount']}'),
            _row('Processing fee', '${loan['processing_fee']}'),
            if (loan['debt_to_income_ratio'] != null)
              _row('Repayment vs net pay',
                  '${((loan['debt_to_income_ratio'] as num) * 100).toStringAsFixed(1)}%',
                  warn: loan['dti_exceeded'] == true),
          ]),

          const SizedBox(height: 16),
          Text('Stage tracker', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._allStages.map((s) {
            final isCurrent = loan['status'] == 'in_review' && s['stage_order'] == loan['current_stage_order'];
            final isPast = loan['status'] != 'draft' &&
                loan['status'] != 'awaiting_guarantor' &&
                (s['stage_order'] as int) < (loan['current_stage_order'] as int);
            return ListTile(
              dense: true,
              leading: Icon(
                isCurrent
                    ? Icons.radio_button_checked
                    : isPast
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                color: isCurrent ? scheme.primary : (isPast ? scheme.primary.withValues(alpha: 0.6) : scheme.outline),
              ),
              title: Text(s['stage_name'] as String? ?? ''),
            );
          }),

          const SizedBox(height: 24),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Color(0xFFD9534F))),
            const SizedBox(height: 12),
          ],
          _buildActionArea(context),
        ],
      ),
    );
  }

  Widget _buildActionArea(BuildContext context) {
    if (_isGuarantorPending) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('You have been asked to guarantee this loan.',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _acting ? null : () => _guarantorRespond(false),
                child: const Text('Decline'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _acting ? null : () => _guarantorRespond(true),
                child: const Text('Confirm'),
              ),
            ),
          ]),
        ],
      );
    }

    if (_isMyApprovalTurn) {
      final isDisbursement = _currentStage!['is_disbursement_stage'] == true;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('This loan is waiting at your stage: ${_currentStage!['stage_name']}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _acting ? null : () => _act('rejected'),
                child: const Text('Reject'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _acting ? null : () => _act('approved'),
                child: Text(isDisbursement ? 'Approve & Disburse' : 'Approve'),
              ),
            ),
          ]),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _infoCard(BuildContext context, List<Widget> rows) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
      ),
    );
  }

  Widget _row(String label, String value, {bool warn = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFB0B6B2),
              fontSize: 15,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: warn
                  ? AppColors.danger
                  : Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
