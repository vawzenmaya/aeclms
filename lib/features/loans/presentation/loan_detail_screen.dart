// lib/features/loans/presentation/loan_detail_screen.dart

import 'package:aeclms/core/widgets/custom_loader.dart';
import 'package:aeclms/features/loans/utils/loan_form_pdf_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart'; 

import '../../auth/data/auth_service.dart';
import '../../documents/data/documents_repository.dart';
import '../../documents/presentation/document_upload_screen.dart';
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
  List<Map<String, dynamic>> _stageActions = []; 
  bool _loading = true;
  bool _acting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    
    try {
      final loan = await widget.repository.fetchLoan(widget.loanId);
      
      Map<String, dynamic>? currentStage;
      if (loan['status'] == 'in_review') {
        currentStage = await widget.repository.fetchCurrentStage(loan);
      }
      
      final stages = await widget.repository.fetchAllStages(loan['template_id'] as String);
      
      List<Map<String, dynamic>> actions = [];
      try {
        actions = await widget.repository.fetchStageActions(widget.loanId); 
      } catch (e) {
        debugPrint('Warning: Could not fetch stage comments: $e');
      }

      if (!mounted) return;
      setState(() {
        _loan = loan;
        _currentStage = currentStage;
        _allStages = stages;
        _stageActions = actions;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load loan details: $e';
          _loading = false;
        });
      }
    }
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
      final result = await _showActionSignatureSheet('Decline Guarantorship', isReject: true);
      if (result == null || result['comment'].trim().isEmpty) return;
      comment = result['comment'];
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
    final isApproval = action == 'approved';
    final isDisbursement = isApproval && _currentStage!['is_disbursement_stage'] == true;
    
    final result = await _showActionSignatureSheet(
      isApproval ? (isDisbursement ? 'Disburse Loan' : 'Approve') : 'Reject Application',
      isReject: !isApproval,
      isDisbursement: isDisbursement,
    );

    if (result == null) return; 

    setState(() => _acting = true);
    try {
      await widget.repository.recordStageAction(
        loanId: widget.loanId,
        stageId: _currentStage!['id'] as String,
        actorId: widget.profile.id,
        action: action,
        comment: result['comment'],
        firstDeductionDate: result['date'],
        disbursementMode: result['disbursementMode'], 
        chequeNumber: result['chequeNumber'],         
      );
      await _load();
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<Map<String, dynamic>?> _showActionSignatureSheet(String title, {bool isReject = false, bool isDisbursement = false}) async {
    final ctrl = TextEditingController();
    final chequeCtrl = TextEditingController();
    DateTime? selectedDate = isDisbursement ? DateTime.now().add(const Duration(days: 30)) : null;
    String? disbursementMode;
    bool isSubmitEnabled = false;

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final scheme = Theme.of(context).colorScheme;
          final buttonColor = isReject ? const Color(0xFFD9534F) : scheme.primary;

          void validate() {
             bool valid = ctrl.text.trim().isNotEmpty;
             if (isDisbursement && !isReject) {
                 if (disbursementMode == null) valid = false;
                 if (disbursementMode == 'Cheque' && chequeCtrl.text.trim().isEmpty) valid = false;
             }
             setSheetState(() => isSubmitEnabled = valid);
          }

          return Container(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(width: 40, height: 4, decoration: BoxDecoration(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: buttonColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                        child: Icon(isReject ? Icons.cancel_outlined : Icons.draw_rounded, color: buttonColor),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Approval Remarks', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: scheme.onSurface))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'A mandatory remark is required to officially sign off. This comment will be permanently visible on the loan tracker.',
                    style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  
                  TextField(
                    controller: ctrl,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (val) => validate(),
                    decoration: InputDecoration(
                      hintText: isReject ? 'State the detailed reason for rejection...' : 'Enter your approval remarks...',
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: buttonColor, width: 2)),
                    ),
                  ),

                  if (isDisbursement && !isReject) ...[
                    const SizedBox(height: 32),
                    Text('Disbursement Details', style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary)),
                    const SizedBox(height: 16),
                    
                    Text('First Deduction Date', style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface.withValues(alpha: 0.7), fontSize: 13)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate!,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 366)),
                        );
                        if (picked != null) {
                          setSheetState(() => selectedDate = picked);
                          validate();
                        }
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_month_rounded, color: scheme.primary, size: 20),
                            const SizedBox(width: 12),
                            Text(DateFormat('MMMM dd, yyyy').format(selectedDate!), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                    Text('Mode of Disbursement', style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface.withValues(alpha: 0.7), fontSize: 13)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: disbursementMode,
                      hint: Text('Select Mode', style: TextStyle(color: scheme.onSurface)),
                      dropdownColor: scheme.surface,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                      items: ['RTGS', 'EFT', 'Cheque'].map((e) => DropdownMenuItem(
                        value: e, 
                        child: Text(e, style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface))
                      )).toList(),
                      onChanged: (val) {
                        setSheetState(() => disbursementMode = val);
                        validate();
                      },
                    ),

                    if (disbursementMode == 'Cheque') ...[
                      const SizedBox(height: 16),
                      Text('Cheque Number', style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface.withValues(alpha: 0.7), fontSize: 13)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: chequeCtrl,
                        onChanged: (val) => validate(),
                        decoration: InputDecoration(
                          hintText: 'Enter Cheque Number...',
                          filled: true,
                          fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                      ),
                    ],
                  ],

                  const SizedBox(height: 32),
                  
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isSubmitEnabled 
                        ? () => Navigator.pop(context, {
                            'comment': ctrl.text.trim(), 
                            'date': selectedDate,
                            'disbursementMode': disbursementMode,
                            'chequeNumber': chequeCtrl.text.trim(),
                          }) 
                        : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: buttonColor,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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

  Future<void> _goToDocumentUpload() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentUploadScreen(
          loanRepository: widget.repository,
          profile: widget.profile,
          loanId: widget.loanId,
          hasGuarantor: _loan!['guarantor_id'] != null,
        ),
      ),
    );
    _load(); 
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(body: Center(child: CustomLoader(size: 56, color: Theme.of(context).colorScheme.primary)));
    }
    if (_error != null || _loan == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          title: const Text('Error', style: TextStyle(fontWeight: FontWeight.w600)),
          leading: const BackButton(),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded, color: Color(0xFFD9534F), size: 48),
                const SizedBox(height: 16),
                Text(
                  _error ?? 'An unknown error occurred while loading this loan.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFD9534F), fontSize: 16),
                ),
                const SizedBox(height: 24),
                FilledButton.tonal(
                  onPressed: _load,
                  child: const Text('Try Again'),
                )
              ],
            ),
          ),
        ),
      );
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
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        title: Text(
          loan['full_name'] as String? ?? 'Loan Details',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Print Application Form',
            onPressed: () => LoanFormPdfService.generateInitialApplicationForm(loan: loan),
          ),
          if (['approved', 'active', 'cleared', 'disbursed', 'completed'].contains((loan['status'] as String? ?? '').toLowerCase()))
            IconButton(
              icon: const Icon(Icons.verified_rounded, color: Colors.green),
              tooltip: 'Print Final Execution Certificate',
              onPressed: () => LoanFormPdfService.generateFinalExecutionForm(
                loan: loan,
                stages: _allStages,
                actions: _stageActions,
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              children: [
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

                _StaggeredFadeIn(
                  index: 1,
                  child: _buildMetricsGrid(context, loan),
                ),

                const SizedBox(height: 24),

                _StaggeredFadeIn(
                  index: 2,
                  child: _buildDetailsCard(context, loan),
                ),

                const SizedBox(height: 32),

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
                          hasGuarantor: loan['guarantor_id'] != null,
                          canUpload: loan['applicant_id'] == widget.profile.id &&
                              (loan['status'] == 'draft' || loan['status'] == 'returned_to_applicant'),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

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

                const SizedBox(height: 48),
              ],
            ),
          ),

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
        
    // Formatting numbers with commas
    final currency = NumberFormat("#,##0", "en_US");

    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _MetricTile(
                title: 'Interest Rate',
                value: '${loan['interest_rate']}%',
                subtitle: 'Per Annum${loan['interest_method'] != null ? ' • ${loan['interest_method']}' : ''}',
                icon: Icons.percent_rounded,
              ),
              const SizedBox(height: 12),
              _MetricTile(
                title: 'Processing Fee',
                value: loan['processing_fee'] != null ? currency.format(loan['processing_fee']) : '0',
                subtitle: '0.005 of Principal',
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
                value: loan['installment_amount'] != null ? currency.format(loan['installment_amount']) : '0',
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
        color: Theme.of(context).colorScheme.surface,
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
    final sortedStages = List<Map<String, dynamic>>.from(_allStages)
      ..sort((a, b) => (a['stage_order'] as int).compareTo(b['stage_order'] as int));

    final dbStatus = (loan['status'] as String? ?? 'draft').toLowerCase();
    final maxStageOrder = sortedStages.isNotEmpty ? sortedStages.last['stage_order'] as int : -1;
    final currentStageOrder = loan['current_stage_order'] as int? ?? 0;
    
    final isFullyApproved = ['approved', 'active', 'cleared', 'disbursed', 'completed'].contains(dbStatus) || 
                            (currentStageOrder > maxStageOrder && dbStatus != 'rejected' && dbStatus != 'returned_to_applicant' && dbStatus != 'draft');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(sortedStages.length, (index) {
          final s = sortedStages[index];
          final stageOrder = s['stage_order'] as int;
          final isCurrent = dbStatus == 'in_review' && stageOrder == currentStageOrder;
          
          final isPast = isFullyApproved || (
              dbStatus != 'draft' &&
              dbStatus != 'awaiting_guarantor' &&
              stageOrder < currentStageOrder
          );
          
          final isLast = index == sortedStages.length - 1;
          IconData pastIcon = (isLast && isPast) ? Icons.sports_score_rounded : Icons.check;

          final matchingAction = _stageActions.where((a) => a['stage_id'] == s['id']).lastOrNull;

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
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
                            : (isPast ? Icon(pastIcon, size: 16, color: scheme.onPrimary) : null),
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
                          
                        if (matchingAction != null)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: matchingAction['action'] == 'rejected' 
                                  ? const Color(0xFFD9534F).withValues(alpha: 0.1) 
                                  : scheme.primary.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: matchingAction['action'] == 'rejected' 
                                    ? const Color(0xFFD9534F).withValues(alpha: 0.3) 
                                    : scheme.primary.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        matchingAction['profiles']?['full_name'] ?? 'Authorized Approver',
                                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: scheme.onSurface),
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      matchingAction['created_at'] != null 
                                          ? DateFormat('MMM d, yyyy').format(DateTime.parse(matchingAction['created_at']))
                                          : '',
                                      style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.5)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  matchingAction['comment'] as String? ?? 'No remark provided.',
                                  style: TextStyle(
                                    fontSize: 13, 
                                    color: scheme.onSurface.withValues(alpha: 0.8), 
                                    fontStyle: FontStyle.italic,
                                    height: 1.4,
                                  ),
                                ),
                                
                                if (matchingAction['disbursement_mode'] != null)
                                  Container(
                                    margin: const EdgeInsets.only(top: 8),
                                    padding: const EdgeInsets.only(top: 8),
                                    decoration: BoxDecoration(
                                      border: Border(top: BorderSide(color: scheme.primary.withValues(alpha: 0.2))),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.payments_rounded, size: 14, color: scheme.primary),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'Paid via ${matchingAction['disbursement_mode']}${matchingAction['cheque_number'] != null ? ' (Chq: ${matchingAction['cheque_number']})' : ''}',
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
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
        color: Theme.of(context).colorScheme.surface,
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
                  onPressed: _acting ? null : _goToDocumentUpload,
                  icon: const Icon(Icons.upload_file_rounded, size: 20),
                  label: const Text('Documents & Submit'),
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
                  child: const Text('Confirm Guarantorship'),
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
                  child: Text(_currentStage!['is_disbursement_stage'] == true ? 'Disburse Loan' : 'Approve'),
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