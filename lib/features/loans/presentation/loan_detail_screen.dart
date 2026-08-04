// lib/features/loans/presentation/loan_detail_screen.dart

import 'package:aeclms/core/widgets/custom_loader.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/data/auth_service.dart';
import '../../documents/data/documents_repository.dart';
import '../../documents/presentation/documents_section.dart';
import '../data/loan_repository.dart';
import 'application_form_screen.dart';
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
  final DocumentsRepository _documentsRepo = DocumentsRepository(Supabase.instance.client);
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
        helpText: 'Select First Deduction Date',
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(
                    surface: Theme.of(context).colorScheme.surface,
                  ),
            ),
            child: child!,
          );
        },
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
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter your reason here...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  bool get _isEditableDraft {
    if (_loan == null) return false;
    return _loan!['applicant_id'] == widget.profile.id &&
        (_loan!['status'] == 'draft' || _loan!['status'] == 'returned_to_applicant');
  }

  Future<void> _editApplication() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ApplicationFormScreen(
          repository: widget.repository,
          profile: widget.profile,
          currentUserEmail: Supabase.instance.client.auth.currentUser?.email,
          existingLoan: _loan,
        ),
      ),
    );
    _load();
  }

  Future<void> _submitDraft() async {
    setState(() => _acting = true);
    try {
      await widget.repository.submit(widget.loanId, hasGuarantor: _loan!['guarantor_id'] != null);
      await _load();
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _loan == null) {
      return Scaffold(body: Center(child: CustomLoader(size: 56, color: Theme.of(context).colorScheme.primary)));
    }

    return FutureBuilder<void>(
      future: _ensureRoles(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(body: Center(child: CustomLoader(size: 56, color: Theme.of(context).colorScheme.primary)));
        }
        return _buildLoaded(context);
      },
    );
  }

  Widget _buildLoaded(BuildContext context) {
    final loan = _loan!;
    final scheme = Theme.of(context).colorScheme;
    
    final amountRaw = loan['amount_requested'] as num?;
    final amountString = amountRaw != null 
        ? amountRaw.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},') 
        : '-';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          loan['full_name'] as String? ?? 'Loan Details',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              children: [
                // 1. Hero Section
                _StaggeredFadeIn(
                  index: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Amount Requested',
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        color: scheme.onSurface.withValues(alpha: 0.6),
                                        letterSpacing: 0.5,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      'UGX ',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                        color: scheme.onSurface.withValues(alpha: 0.5),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        amountString,
                                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -1,
                                              color: scheme.onSurface,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          LoanStatusChip(status: loan['status'] as String? ?? 'draft'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        loan['amount_in_words'] as String? ?? '',
                        style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontStyle: FontStyle.italic, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),

                // 2. Metrics Grid
                _StaggeredFadeIn(
                  index: 1,
                  child: _buildMetricsGrid(context, loan),
                ),

                const SizedBox(height: 24),

                // 3. Details Card
                _StaggeredFadeIn(
                  index: 2,
                  child: _buildDetailsCard(context, loan),
                ),

                const SizedBox(height: 32),

                // 4. Documents Section
                _StaggeredFadeIn(
                  index: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader('Supporting Documents', icon: Icons.folder_open_rounded),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: DocumentsSection(
                          repository: _documentsRepo,
                          loanId: loan['id'] as String,
                          uploadedBy: widget.profile.id,
                          canUpload: loan['applicant_id'] == widget.profile.id &&
                              (loan['status'] == 'draft' || loan['status'] == 'returned_to_applicant'),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // 5. Stage Tracker Timeline
                _StaggeredFadeIn(
                  index: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader('Approval Tracker', icon: Icons.route_rounded),
                      _buildTimeline(context, loan),
                    ],
                  ),
                ),
                
                const SizedBox(height: 48), // Padding for scrolling past FAB/Bottom nav
              ],
            ),
          ),
          
          // Action Area docked at bottom
          if (_isEditableDraft || _isGuarantorPending || _isMyApprovalTurn || _error != null)
            _buildActionDock(context),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(BuildContext context, Map<String, dynamic> loan) {
    final isDtiExceeded = loan['dti_exceeded'] == true;
    final dtiValue = loan['debt_to_income_ratio'] != null 
        ? '${((loan['debt_to_income_ratio'] as num) * 100).toStringAsFixed(1)}%' 
        : 'N/A';

    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _MetricTile(
                title: 'Interest Rate',
                value: '${loan['interest_rate']}%',
                subtitle: loan['interest_method'] as String?,
                icon: Icons.percent_rounded,
              ),
              const SizedBox(height: 12),
              _MetricTile(
                title: 'Processing Fee',
                value: '${loan['processing_fee']}',
                icon: Icons.receipt_long_rounded,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              _MetricTile(
                title: 'Monthly Installment',
                value: '${loan['installment_amount']}',
                icon: Icons.calendar_month_rounded,
                isHighlight: true,
              ),
              const SizedBox(height: 12),
              _MetricTile(
                title: 'DTI Ratio',
                value: dtiValue,
                icon: Icons.balance_rounded,
                warn: isDtiExceeded,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsCard(BuildContext context, Map<String, dynamic> loan) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _DetailRow('Category', loan['loan_category'] == 'emergency' ? 'Emergency' : 'Normal'),
          const Divider(height: 24),
          _DetailRow('Type', loan['loan_type'] == 'topup' ? 'Top-up' : 'New Loan'),
          const Divider(height: 24),
          _DetailRow('Purpose', loan['purpose'] as String? ?? '-'),
        ],
      ),
    );
  }

  Widget _buildTimeline(BuildContext context, Map<String, dynamic> loan) {
    final scheme = Theme.of(context).colorScheme;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(_allStages.length, (index) {
          final s = _allStages[index];
          final isCurrent = loan['status'] == 'in_review' && s['stage_order'] == loan['current_stage_order'];
          final isPast = loan['status'] != 'draft' &&
              loan['status'] != 'awaiting_guarantor' &&
              (s['stage_order'] as int) < (loan['current_stage_order'] as int);
          final isLast = index == _allStages.length - 1;

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Timeline Line & Dot
                Column(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCurrent 
                            ? scheme.primary.withValues(alpha: 0.2) 
                            : (isPast ? scheme.primary : scheme.surface),
                        border: Border.all(
                          color: isCurrent || isPast ? scheme.primary : scheme.outline,
                          width: isCurrent ? 2 : 1.5,
                        ),
                      ),
                      child: Center(
                        child: isCurrent 
                            ? Container(width: 10, height: 10, decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle))
                            : (isPast ? Icon(Icons.check, size: 14, color: scheme.onPrimary) : null),
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: isPast ? scheme.primary : scheme.outlineVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                // Timeline Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s['stage_name'] as String? ?? '',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isCurrent ? FontWeight.w700 : (isPast ? FontWeight.w600 : FontWeight.w500),
                            color: isCurrent ? scheme.primary : (isPast ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.5)),
                          ),
                        ),
                        if (isCurrent)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Waiting for review',
                              style: TextStyle(fontSize: 12, color: scheme.primary.withValues(alpha: 0.8)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildActionDock(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, -5)),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFD9534F).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD9534F).withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFD9534F)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_error!, style: const TextStyle(color: Color(0xFFD9534F), fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
          ],
          
          if (_isEditableDraft) ...[
            Text(
              _loan!['status'] == 'returned_to_applicant'
                  ? 'Returned for corrections. Please edit and resubmit.'
                  : 'Draft saved. Add documents and submit when ready.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _acting ? null : _editApplication,
                  icon: const Icon(Icons.edit_rounded, size: 20),
                  label: const Text('Edit'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _acting ? null : _submitDraft,
                  icon: _acting ? const CustomLoader(size: 20, color: Colors.white) : const Icon(Icons.send_rounded, size: 20),
                  label: _acting ? const SizedBox.shrink() : const Text('Submit'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ),
            ]),
          ] 
          else if (_isGuarantorPending) ...[
            Row(
              children: [
                Icon(Icons.shield_rounded, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You are requested to guarantee this loan.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _acting ? null : () => _guarantorRespond(false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: const Color(0xFFD9534F),
                    side: BorderSide(color: const Color(0xFFD9534F).withValues(alpha: 0.5)),
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _acting ? null : () => _guarantorRespond(true),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Confirm Support'),
                ),
              ),
            ]),
          ]
          else if (_isMyApprovalTurn) ...[
            Row(
              children: [
                Icon(Icons.assignment_turned_in_rounded, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Awaiting your review: ${_currentStage!['stage_name']}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _acting ? null : () => _act('rejected'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: const Color(0xFFD9534F),
                    side: BorderSide(color: const Color(0xFFD9534F).withValues(alpha: 0.5)),
                  ),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _acting ? null : () => _act('approved'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: Text(_currentStage!['is_disbursement_stage'] == true ? 'Approve & Disburse' : 'Approve'),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    this.warn = false,
    this.isHighlight = false,
  });

  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final bool warn;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bgColor = warn 
        ? const Color(0xFFD9534F).withValues(alpha: 0.1) 
        : (isHighlight ? scheme.primary.withValues(alpha: 0.1) : scheme.surfaceContainerHighest.withValues(alpha: 0.3));
    final iconColor = warn ? const Color(0xFFD9534F) : scheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: warn ? const Color(0xFFD9534F).withValues(alpha: 0.3) : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: warn ? const Color(0xFFD9534F) : scheme.onSurface,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.5)),
            ),
          ]
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ),
      ],
    );
  }
}

/// A lightweight wrapper to provide a staggered fade & slide entrance animation.
class _StaggeredFadeIn extends StatefulWidget {
  final Widget child;
  final int index;

  const _StaggeredFadeIn({required this.child, required this.index});

  @override
  State<_StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<_StaggeredFadeIn> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    Future.delayed(Duration(milliseconds: 100 * widget.index), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}