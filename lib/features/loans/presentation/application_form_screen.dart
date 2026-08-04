// lib/features/loans/presentation/application_form_screen.dart

import 'package:aeclms/core/widgets/custom_loader.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/amount_to_words.dart';
import '../../auth/data/auth_service.dart';
import '../data/loan_repository.dart';
import '../domain/loan_calculations.dart';
import 'loan_detail_screen.dart';
import 'widgets/repayment_preview_card.dart';

class ApplicationFormScreen extends StatefulWidget {
  const ApplicationFormScreen({
    super.key,
    required this.repository,
    required this.profile,
    required this.currentUserEmail,
    this.existingLoan,
  });

  final LoanRepository repository;
  final Profile profile;
  final String? currentUserEmail;
  /// If provided, the form edits this draft instead of creating a new loan.
  final Map<String, dynamic>? existingLoan;

  @override
  State<ApplicationFormScreen> createState() => _ApplicationFormScreenState();
}

class _ApplicationFormScreenState extends State<ApplicationFormScreen> {
  // Navigation State
  int _currentStep = 0;
  final int _totalSteps = 6;

  // Individual form keys for step-by-step validation
  final _step1Key = GlobalKey<FormState>();
  final _step2Key = GlobalKey<FormState>();
  final _step3Key = GlobalKey<FormState>();
  final _step4Key = GlobalKey<FormState>();

  // Loan classification
  late String _loanType = widget.existingLoan?['loan_type'] as String? ?? 'new';
  late String _loanCategory = widget.existingLoan?['loan_category'] as String? ?? 'normal';
  late String _applicantCategory = widget.existingLoan?['category'] as String? ?? 'member';

  // Controllers
  late final _fullNameCtrl =
      TextEditingController(text: widget.existingLoan?['full_name'] as String? ?? widget.profile.fullName);
  late final _emailCtrl = TextEditingController(
      text: widget.existingLoan?['email'] as String? ?? widget.currentUserEmail ?? '');
  late final _phoneCtrl = TextEditingController(
      text: widget.existingLoan?['phone'] as String? ?? widget.profile.phone ?? '');
  late final _employeeNumberCtrl = TextEditingController(
      text: widget.existingLoan?['employee_number'] as String? ?? widget.profile.employeeNumber ?? '');
  late final _amountCtrl = TextEditingController(
      text: (widget.existingLoan?['amount_requested'] as num?)?.toString() ?? '');
  late final _amountInWordsCtrl =
      TextEditingController(text: widget.existingLoan?['amount_in_words'] as String? ?? '');
  late final _purposeCtrl = TextEditingController(text: widget.existingLoan?['purpose'] as String? ?? '');
  late final _securityDescCtrl =
      TextEditingController(text: widget.existingLoan?['security_description'] as String? ?? '');
  late final _securityValueCtrl = TextEditingController(
      text: (widget.existingLoan?['security_estimated_value'] as num?)?.toString() ?? '');
  late final _netPayCtrl =
      TextEditingController(text: (widget.existingLoan?['net_pay'] as num?)?.toString() ?? '');
  late final _bankHolderCtrl = TextEditingController(
      text: widget.existingLoan?['bank_account_holder_name'] as String? ?? widget.profile.fullName);
  late final _bankNameCtrl = TextEditingController(text: widget.existingLoan?['bank_name'] as String? ?? '');
  late final _bankAccountCtrl =
      TextEditingController(text: widget.existingLoan?['bank_account_number'] as String? ?? '');
  late final _bankSortCodeCtrl =
      TextEditingController(text: widget.existingLoan?['bank_sort_code'] as String? ?? '');
  late final _bankSwiftCtrl =
      TextEditingController(text: widget.existingLoan?['bank_swift_code'] as String? ?? '');

  late DateTime? _expectedEndDate = widget.existingLoan?['expected_end_date'] != null
      ? DateTime.tryParse(widget.existingLoan!['expected_end_date'] as String)
      : null;
  late String? _guarantorId = widget.existingLoan?['guarantor_id'] as String?;
  late bool _bankDetailsConfirmed = widget.existingLoan?['bank_details_confirmed'] as bool? ?? false;

  LoanSettings _settings = LoanSettings.fallback;
  List<GuarantorOption> _guarantors = [];
  bool _loadingContext = true;
  bool _saving = false;
  String? _error;

  bool get _isEditingDraft => widget.existingLoan != null;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onAmountChanged);
    _loadContext();
  }

  Future<void> _loadContext() async {
    final communityId = widget.profile.communityId!;
    final results = await Future.wait([
      widget.repository.fetchLoanSettings(communityId),
      widget.repository.fetchPossibleGuarantors(
        communityId: communityId,
        excludeProfileId: widget.profile.id,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _settings = results[0] as LoanSettings;
      _guarantors = results[1] as List<GuarantorOption>;
      _loadingContext = false;
    });
  }

  void _onAmountChanged() {
    final value = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
    _amountInWordsCtrl.text = value != null ? AmountToWords.convert(value) : '';
    setState(() {}); // refresh preview
  }

  int? get _termMonths {
    if (_expectedEndDate == null) return null;
    final now = DateTime.now();
    final months = (_expectedEndDate!.year - now.year) * 12 + (_expectedEndDate!.month - now.month);
    return months < 1 ? 1 : months;
  }

  LoanPreview get _preview {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0;
    final netPay = double.tryParse(_netPayCtrl.text.replaceAll(',', ''));
    return LoanCalculations.preview(
      settings: _settings,
      loanCategory: _loanCategory,
      amountRequested: amount,
      termMonths: _termMonths,
      netPay: netPay,
    );
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 366 * 6)),
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
    if (picked != null) {
      setState(() {
        _expectedEndDate = picked;
        _error = null;
      });
    }
  }

  void _nextStep() {
    bool isValid = true;
    
    // Validate the current step's form before proceeding
    if (_currentStep == 1) isValid = _step1Key.currentState?.validate() ?? true;
    if (_currentStep == 2) {
      isValid = _step2Key.currentState?.validate() ?? true;
      if (_expectedEndDate == null) {
        setState(() => _error = 'Please choose an expected end date.');
        return;
      }
    }
    if (_currentStep == 3) isValid = _step3Key.currentState?.validate() ?? true;
    if (_currentStep == 4) {
      isValid = _step4Key.currentState?.validate() ?? true;
      if (!_bankDetailsConfirmed) {
        setState(() => _error = 'Please confirm your bank details to proceed.');
        return;
      }
    }

    if (isValid) {
      FocusScope.of(context).unfocus(); // Dismiss keyboard
      setState(() {
        _error = null;
        if (_currentStep < _totalSteps - 1) {
          _currentStep++;
        }
      });
    }
  }

  void _prevStep() {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      if (_currentStep > 0) {
        _currentStep--;
      }
    });
  }

  Future<void> _handleSave({required bool submit}) async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final loanId = await widget.repository.saveDraft(
        existingLoanId: widget.existingLoan?['id'] as String?,
        applicantId: widget.profile.id,
        communityId: widget.profile.communityId!,
        loanType: _loanType,
        loanCategory: _loanCategory,
        category: _applicantCategory,
        fullName: _fullNameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        employeeNumber: _employeeNumberCtrl.text.trim().isEmpty ? null : _employeeNumberCtrl.text.trim(),
        amountRequested: double.parse(_amountCtrl.text.replaceAll(',', '')),
        amountInWords: _amountInWordsCtrl.text,
        purpose: _purposeCtrl.text.trim(),
        securityDescription: _securityDescCtrl.text.trim().isEmpty ? null : _securityDescCtrl.text.trim(),
        securityEstimatedValue: double.tryParse(_securityValueCtrl.text.replaceAll(',', '')),
        expectedEndDate: _expectedEndDate ?? DateTime.now(), // Fallback for draft, caught by validation if submitting
        netPay: double.parse(_netPayCtrl.text.replaceAll(',', '')),
        guarantorId: _guarantorId,
        bankAccountHolderName: _bankHolderCtrl.text.trim(),
        bankName: _bankNameCtrl.text.trim(),
        bankAccountNumber: _bankAccountCtrl.text.trim(),
        bankSortCode: _bankSortCodeCtrl.text.trim().isEmpty ? null : _bankSortCodeCtrl.text.trim(),
        bankSwiftCode: _bankSwiftCtrl.text.trim(),
        bankDetailsConfirmed: _bankDetailsConfirmed,
      );

      if (submit) {
        await widget.repository.submit(loanId, hasGuarantor: _guarantorId != null);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(submit ? 'Application submitted successfully' : 'Draft saved securely'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LoanDetailScreen(
            repository: widget.repository,
            profile: widget.profile,
            loanId: loanId,
          ),
        ),
      );
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } catch (e, st) {
      debugPrint('saveDraft/submit failed: $e\n$st');
      setState(() => _error = 'Please fill out all required numeric fields before saving.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_onAmountChanged);
    for (final c in [
      _fullNameCtrl, _emailCtrl, _phoneCtrl, _employeeNumberCtrl, _amountCtrl,
      _amountInWordsCtrl, _purposeCtrl, _securityDescCtrl, _securityValueCtrl,
      _netPayCtrl, _bankHolderCtrl, _bankNameCtrl, _bankAccountCtrl,
      _bankSortCodeCtrl, _bankSwiftCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingContext) {
      return Scaffold(
        body: Center(
          child: CustomLoader(size: 56, color: Theme.of(context).colorScheme.primary),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _prevStep,
              )
            : const BackButton(),
        title: Text(
          _isEditingDraft ? 'Edit Application' : 'New Application',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _handleSave(submit: false),
            child: const Text('Save Draft'),
          ),
          const SizedBox(width: 8),
        ],
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Step Progress Indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: List.generate(_totalSteps, (index) {
                final isActive = index == _currentStep;
                final isPassed = index < _currentStep;
                return Expanded(
                  flex: isActive ? 3 : 1,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 6,
                    decoration: BoxDecoration(
                      color: isActive || isPassed
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                );
              }),
            ),
          ),
          
          // Main Content Area
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (Widget child, Animation<double> animation) {
                // Determine slide direction based on key comparison (hacky but works for simple ints)
                final inAnimation = Tween<Offset>(
                  begin: const Offset(0.05, 0),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: inAnimation,
                    child: child,
                  ),
                );
              },
              child: SingleChildScrollView(
                key: ValueKey<int>(_currentStep),
                padding: const EdgeInsets.all(24),
                child: _buildCurrentStepView(),
              ),
            ),
          ),

          // Bottom Navigation Bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _buildBottomNav(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case 0:
        return _buildStep0Classification();
      case 1:
        return _buildStep1Personal();
      case 2:
        return _buildStep2LoanDetails();
      case 3:
        return _buildStep3Security();
      case 4:
        return _buildStep4Bank();
      case 5:
        return _buildStep5Review();
      default:
        return const SizedBox.shrink();
    }
  }

  // --- Step 0: Classification ---
  Widget _buildStep0Classification() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeader(title: 'Loan Classification', subtitle: 'Let\'s start with the basics.', icon: Icons.category_rounded),
        _card([
          _EnumChips(
            label: 'Loan Category',
            value: _loanCategory,
            options: const {'normal': 'Normal', 'emergency': 'Emergency'},
            onChanged: (v) => setState(() {
              _loanCategory = v;
              if (v == 'emergency') _loanType = 'new';
            }),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Divider(height: 1),
          ),
          _EnumChips(
            label: 'New or Top-up',
            value: _loanType,
            options: {
              'new': 'New loan',
              if (_loanCategory == 'normal') 'topup': 'Top-up',
            },
            onChanged: (v) => setState(() => _loanType = v),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Divider(height: 1),
          ),
          _EnumChips(
            label: 'Applicant Role',
            value: _applicantCategory,
            options: const {'member': 'Member', 'non_member': 'Non-Member'},
            onChanged: (v) => setState(() {
              _applicantCategory = v;
              if (v == 'member') {
                _employeeNumberCtrl.text = widget.profile.employeeNumber ?? '';
              }
            }),
          ),
        ]),
      ],
    );
  }

  // --- Step 1: Personal Details ---
  Widget _buildStep1Personal() {
    return Form(
      key: _step1Key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(title: 'Applicant Profile', subtitle: 'Confirm your personal details.', icon: Icons.person_rounded),
          _card([
            _field(_fullNameCtrl, "Full Legal Name", icon: Icons.badge_outlined, validator: _required),
            _field(_emailCtrl, 'Email Address', icon: Icons.email_outlined, validator: _required),
            _field(_phoneCtrl, 'Phone Number', icon: Icons.phone_outlined, validator: _required),
            _field(
              _employeeNumberCtrl,
              _applicantCategory == 'member' ? 'Employee Number (AEC/...)' : 'ID / Reference Number',
              icon: Icons.numbers_rounded,
              validator: _required,
            ),
          ]),
        ],
      ),
    );
  }

  // --- Step 2: Loan Details ---
  Widget _buildStep2LoanDetails() {
    return Form(
      key: _step2Key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(title: 'Loan Particulars', subtitle: 'How much do you need?', icon: Icons.request_quote_rounded),
          _card([
            _field(_amountCtrl, 'Amount Applied For',
                icon: Icons.attach_money_rounded, keyboardType: TextInputType.number, validator: _requiredNumber),
            _field(_amountInWordsCtrl, 'Amount in Words',
                icon: Icons.text_fields_rounded, maxLines: 2),
            _field(_purposeCtrl, 'Purpose of the Loan',
                icon: Icons.edit_note_rounded, maxLines: 3, validator: _required),
            const SizedBox(height: 8),
            _DatePickerField(
              label: 'Expected End Date',
              value: _expectedEndDate,
              onTap: _pickEndDate,
            ),
            if (_termMonths != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 12),
                child: Text(
                  'Calculated Period: $_termMonths month(s)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            _field(_netPayCtrl, 'Net Pay (Monthly)',
                icon: Icons.account_balance_wallet_outlined, keyboardType: TextInputType.number, validator: _requiredNumber),
          ]),
          if (_error != null) _buildErrorBanner(),
        ],
      ),
    );
  }

  // --- Step 3: Security & Guarantor ---
  Widget _buildStep3Security() {
    return Form(
      key: _step3Key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(title: 'Security & Guarantor', subtitle: 'Provide backing for your application.', icon: Icons.shield_rounded),
          _card([
            _field(_securityDescCtrl, "Security Description (Optional)", icon: Icons.inventory_2_outlined),
            _field(_securityValueCtrl, 'Estimated Value',
                icon: Icons.price_change_outlined, keyboardType: TextInputType.number),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _guarantorId,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              decoration: InputDecoration(
                labelText: 'Select Guarantor',
                prefixIcon: const Icon(Icons.group_add_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                filled: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('No guarantor needed')),
                ..._guarantors.map((g) => DropdownMenuItem(value: g.id, child: Text(g.fullName))),
              ],
              onChanged: (v) => setState(() => _guarantorId = v),
            ),
            if (_guarantorId != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 20, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your guarantor will be notified and must confirm digitally before '
                        'this application proceeds to the Loan Officer.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ]),
        ],
      ),
    );
  }

  // --- Step 4: Bank Details ---
  Widget _buildStep4Bank() {
    return Form(
      key: _step4Key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(title: 'Disbursement Details', subtitle: 'Where should we send the funds?', icon: Icons.account_balance_rounded),
          _card([
            _field(_bankHolderCtrl, 'Account Holder Name', icon: Icons.person_outline, validator: _required),
            _field(_bankNameCtrl, 'Bank Name', icon: Icons.account_balance_outlined, validator: _required),
            _field(_bankAccountCtrl, 'Account Number', icon: Icons.pin_outlined, validator: _required),
            Row(
              children: [
                Expanded(child: _field(_bankSortCodeCtrl, 'Sort Code', icon: Icons.tag)),
                const SizedBox(width: 12),
                Expanded(child: _field(_bankSwiftCtrl, 'SWIFT / BIC', icon: Icons.public, validator: _required)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(14),
              ),
              child: CheckboxListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                value: _bankDetailsConfirmed,
                activeColor: Theme.of(context).colorScheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onChanged: (v) => setState(() {
                  _bankDetailsConfirmed = v ?? false;
                  if (_bankDetailsConfirmed) _error = null;
                }),
                title: Text(
                  'I confirm these bank details are accurate and I am the authorized signatory.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
          ]),
          if (_error != null) _buildErrorBanner(),
        ],
      ),
    );
  }

  // --- Step 5: Review & Submit ---
  Widget _buildStep5Review() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeader(title: 'Review Application', subtitle: 'Ensure everything looks correct before submitting.', icon: Icons.insights_rounded),
        RepaymentPreviewCard(
          preview: _preview,
          amountRequested: double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0,
        ),
        if (_error != null) _buildErrorBanner(),
      ],
    );
  }

  Widget _buildBottomNav() {
    return Row(
      children: [
        if (_currentStep > 0) ...[
          OutlinedButton(
            onPressed: _saving ? null : _prevStep,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: const Icon(Icons.arrow_back_rounded, size: 20),
          ),
          const SizedBox(width: 16),
        ],
        Expanded(
          child: FilledButton(
            onPressed: _saving 
                ? null 
                : (_currentStep == _totalSteps - 1 ? () => _handleSave(submit: true) : _nextStep),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              elevation: 0,
            ),
            child: _saving
                ? const CustomLoader(size: 24, color: Colors.white)
                : Text(
                    _currentStep == _totalSteps - 1 ? 'Submit Application' : 'Next Step',
                    style: const TextStyle(fontSize: 16),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
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
    );
  }

  Widget _card(List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: Theme.of(context).cardTheme.shape is RoundedRectangleBorder
              ? (Theme.of(context).cardTheme.shape as RoundedRectangleBorder).borderRadius
              : BorderRadius.circular(22),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      );

  Widget _field(
    TextEditingController ctrl,
    String label, {
    IconData? icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon != null ? Icon(icon, size: 22, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)) : null,
          alignLabelWithHint: maxLines > 1,
        ),
      ),
    );
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'This field is required' : null;
  String? _requiredNumber(String? v) {
    if (v == null || v.trim().isEmpty) return 'This field is required';
    if (double.tryParse(v.replaceAll(',', '')) == null) return 'Please enter a valid number';
    return null;
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.title, required this.subtitle, required this.icon});
  
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
          ),
        ],
      ),
    );
  }
}

class _EnumChips extends StatelessWidget {
  const _EnumChips({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: options.entries.map((e) {
            final isSelected = value == e.key;
            return ChoiceChip(
              label: Text(e.value),
              selected: isSelected,
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              labelStyle: TextStyle(
                color: isSelected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              selectedColor: Theme.of(context).colorScheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                ),
              ),
              onSelected: (_) => onChanged(e.key),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({required this.label, required this.value, required this.onTap});
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = value == null ? 'Select a date' : '${value!.day}/${value!.month}/${value!.year}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(Icons.calendar_month_outlined, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 15,
              fontWeight: value == null ? FontWeight.w400 : FontWeight.w500,
              color: value == null ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5) : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}