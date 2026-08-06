// lib/features/loans/presentation/application_form_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/amount_to_words.dart';
import '../../../core/widgets/custom_loader.dart';
import '../../auth/data/auth_service.dart';
import '../../documents/presentation/document_upload_screen.dart';
import '../data/loan_repository.dart';
import '../domain/loan_calculations.dart';

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

  // Controllers - Notice the .toInt() to strip trailing .0 floats from the DB
  late final _fullNameCtrl =
      TextEditingController(text: widget.existingLoan?['full_name'] as String? ?? widget.profile.fullName);
  late final _emailCtrl = TextEditingController(
      text: widget.existingLoan?['email'] as String? ?? widget.currentUserEmail ?? '');
  late final _phoneCtrl = TextEditingController(
      text: widget.existingLoan?['phone'] as String? ?? widget.profile.phone ?? '');
  late final _employeeNumberCtrl = TextEditingController(
      text: widget.existingLoan?['employee_number'] as String? ?? widget.profile.employeeNumber ?? '');
  
  late final _amountCtrl = TextEditingController(
      text: (widget.existingLoan?['amount_requested'] as num?)?.toInt().toString() ?? '');
  late final _amountInWordsCtrl =
      TextEditingController(text: widget.existingLoan?['amount_in_words'] as String? ?? '');
  
  late final _netPayCtrl =
      TextEditingController(text: (widget.existingLoan?['net_pay'] as num?)?.toInt().toString() ?? '');
  late final _netPayInWordsCtrl = 
      TextEditingController(text: _calculateWordsInitial((widget.existingLoan?['net_pay'] as num?)?.toDouble()));
      
  late final _purposeCtrl = TextEditingController(text: widget.existingLoan?['purpose'] as String? ?? '');
  late final _securityDescCtrl =
      TextEditingController(text: widget.existingLoan?['security_description'] as String? ?? '');
  late final _securityValueCtrl = TextEditingController(
      text: (widget.existingLoan?['security_estimated_value'] as num?)?.toInt().toString() ?? '');
      
  late final _bankHolderCtrl = TextEditingController(
      text: widget.existingLoan?['bank_account_holder_name'] as String? ?? widget.profile.fullName);
  late String? _bankName = widget.existingLoan?['bank_name'] as String?;
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

  // Major Ugandan Commercial Banks
  final List<String> _ugandanBanks = [
    'Absa Bank Uganda',
    'Bank of Africa',
    'Bank of Baroda',
    'Centenary Bank',
    'Citibank Uganda',
    'DFCU Bank',
    'Diamond Trust Bank (DTB)',
    'Ecobank Uganda',
    'Equity Bank',
    'Housing Finance Bank',
    'KCB Bank',
    'NCBA Bank',
    'PostBank Uganda',
    'Stanbic Bank',
    'Standard Chartered Bank',
    'Tropical Bank',
    'UBA Uganda'
  ];

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onAmountChanged);
    _netPayCtrl.addListener(_onNetPayChanged);
    _loadContext();
  }

  String _calculateWordsInitial(double? value) {
    if (value == null) return '';
    return AmountToWords.convert(value);
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
  
  void _onNetPayChanged() {
    final value = double.tryParse(_netPayCtrl.text.replaceAll(',', ''));
    _netPayInWordsCtrl.text = value != null ? AmountToWords.convert(value) : '';
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

    if (_currentStep == 1) isValid = _step1Key.currentState?.validate() ?? true;
    if (_currentStep == 2) {
      isValid = _step2Key.currentState?.validate() ?? true;
      if (_expectedEndDate == null) {
        setState(() => _error = 'Please choose an expected end date.');
        return;
      }
    }
    if (_currentStep == 3) {
      isValid = _step3Key.currentState?.validate() ?? true;
      if (_guarantorId == null) {
         setState(() => _error = 'A community guarantor is required to proceed.');
         return;
      }
    }
    if (_currentStep == 4) {
      isValid = _step4Key.currentState?.validate() ?? true;
      if (_bankName == null) {
        setState(() => _error = 'Please select your bank.');
        return;
      }
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

  Future<void> _handleSave() async {
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
        expectedEndDate: _expectedEndDate ?? DateTime.now(),
        netPay: double.parse(_netPayCtrl.text.replaceAll(',', '')),
        guarantorId: _guarantorId,
        bankAccountHolderName: _bankHolderCtrl.text.trim(),
        bankName: _bankName ?? 'Unknown',
        bankAccountNumber: _bankAccountCtrl.text.trim(),
        bankSortCode: _bankSortCodeCtrl.text.trim().isEmpty ? null : _bankSortCodeCtrl.text.trim(),
        bankSwiftCode: _bankSwiftCtrl.text.trim(),
        bankDetailsConfirmed: _bankDetailsConfirmed,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Application saved. Now add your documents.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
        ),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DocumentUploadScreen(
            loanRepository: widget.repository,
            profile: widget.profile,
            loanId: loanId,
            hasGuarantor: _guarantorId != null,
          ),
        ),
      );
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } catch (e, st) {
      debugPrint('saveDraft failed: $e\n$st');
      setState(() => _error = 'Please fill out all required numeric fields before saving.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_onAmountChanged);
    _netPayCtrl.removeListener(_onNetPayChanged);
    for (final c in [
      _fullNameCtrl, _emailCtrl, _phoneCtrl, _employeeNumberCtrl, _amountCtrl,
      _amountInWordsCtrl, _purposeCtrl, _securityDescCtrl, _securityValueCtrl,
      _netPayCtrl, _netPayInWordsCtrl, _bankHolderCtrl, _bankAccountCtrl,
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
            onPressed: _saving ? null : _handleSave,
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
        
        Text('Category', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _SelectionCard(
                title: 'Normal',
                subtitle: 'Standard timeline',
                icon: Icons.calendar_month_rounded,
                isSelected: _loanCategory == 'normal',
                onTap: () => setState(() => _loanCategory = 'normal'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _SelectionCard(
                title: 'Emergency',
                subtitle: 'Quick flat rate',
                icon: Icons.bolt_rounded,
                isSelected: _loanCategory == 'emergency',
                onTap: () => setState(() {
                  _loanCategory = 'emergency';
                  _loanType = 'new';
                }),
              ),
            ),
          ],
        ),
        
        const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider(height: 1)),
        
        Text('Loan Type', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _SelectionCard(
                title: 'New Loan',
                subtitle: 'Fresh application',
                icon: Icons.add_circle_outline_rounded,
                isSelected: _loanType == 'new',
                onTap: () => setState(() => _loanType = 'new'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _loanCategory == 'normal' 
                  ? _SelectionCard(
                      title: 'Top-up',
                      subtitle: 'Add to existing',
                      icon: Icons.upgrade_rounded,
                      isSelected: _loanType == 'topup',
                      onTap: () => setState(() => _loanType = 'topup'),
                    )
                  : Opacity(
                      opacity: 0.3,
                      child: _SelectionCard(
                        title: 'Top-up',
                        subtitle: 'Normal loans only',
                        icon: Icons.block_rounded,
                        isSelected: false,
                        onTap: () {},
                      ),
                    ),
            ),
          ],
        ),

        const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider(height: 1)),
        
        Text('Applicant Role', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _SelectionCard(
                title: 'Member',
                subtitle: 'Registered AEC',
                icon: Icons.verified_user_rounded,
                isSelected: _applicantCategory == 'member',
                onTap: () => setState(() {
                  _applicantCategory = 'member';
                  _employeeNumberCtrl.text = widget.profile.employeeNumber ?? '';
                }),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _SelectionCard(
                title: 'Non-Member',
                subtitle: 'External entity',
                icon: Icons.person_outline_rounded,
                isSelected: _applicantCategory == 'non_member',
                onTap: () => setState(() => _applicantCategory = 'non_member'),
              ),
            ),
          ],
        ),
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
            _field(_emailCtrl, 'Email Address', icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress, validator: _required),
            _field(_phoneCtrl, 'Phone Number', icon: Icons.phone_outlined, keyboardType: TextInputType.phone, formatters: [FilteringTextInputFormatter.digitsOnly], validator: _required),
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
                icon: Icons.attach_money_rounded, keyboardType: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly], validator: _requiredNumber),
            _field(_amountInWordsCtrl, 'Amount in Words (Auto)',
                icon: Icons.text_fields_rounded, maxLines: 2, readOnly: true),
                
            _field(_purposeCtrl, 'Purpose of the Loan',
                icon: Icons.edit_note_rounded, 
                maxLength: 250, // Limits characters and shows counter automatically
                // textAlign: TextAlign.center, // Centers the input text
                validator: _required),
            
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
            const SizedBox(height: 32),
            _field(_netPayCtrl, 'Net Pay (Monthly)',
                icon: Icons.account_balance_wallet_outlined, keyboardType: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly], validator: _requiredNumber),
            _field(_netPayInWordsCtrl, 'Net Pay in Words (Auto)',
                icon: Icons.text_fields_rounded, maxLines: 2, readOnly: true),
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
            _field(_securityValueCtrl, 'Estimated Value (Optional)',
                icon: Icons.price_change_outlined, keyboardType: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly]),
            
            const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),
            
            DropdownButtonFormField<String>(
              value: _guarantorId,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              decoration: InputDecoration(
                labelText: 'Mandatory Guarantor',
                prefixIcon: const Icon(Icons.group_add_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                filled: true,
              ),
              items: _guarantors.map((g) => DropdownMenuItem(value: g.id, child: Text(g.fullName))).toList(),
              onChanged: (v) => setState(() {
                _guarantorId = v;
                _error = null;
              }),
              validator: (v) => v == null ? 'A community guarantor is required' : null,
            ),
            
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.gavel_rounded, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'A guarantor is mandatory and must be a registered member of the AEC community. '
                      'They will be notified and must sign digitally before the loan officer reviews this.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ]),
          if (_error != null) _buildErrorBanner(),
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
            
            // Ugandan Banks Dropdown
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: DropdownButtonFormField<String>(
                value: _bankName,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                decoration: InputDecoration(
                  labelText: 'Bank Name',
                  prefixIcon: Icon(Icons.account_balance_outlined, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  filled: true,
                ),
                items: _ugandanBanks.map((bank) => DropdownMenuItem(value: bank, child: Text(bank, style: const TextStyle(fontWeight: FontWeight.w500)))).toList(),
                onChanged: (v) => setState(() {
                  _bankName = v;
                  _error = null;
                }),
                validator: (v) => v == null ? 'Please select your bank' : null,
              ),
            ),
            
            _field(_bankAccountCtrl, 'Account Number', icon: Icons.pin_outlined, keyboardType: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly], validator: _required),
            Row(
              children: [
                Expanded(child: _field(_bankSortCodeCtrl, 'Sort Code', icon: Icons.tag, keyboardType: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly])),
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

  // --- Step 5: Review & Save ---
    Widget _buildStep5Review() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(title: 'Review Application', subtitle: 'Ensure everything looks correct before continuing.', icon: Icons.insights_rounded),
          
          _PremiumRepaymentSummary(
            preview: _preview, 
            amountRequested: double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0,
            termMonths: _termMonths, // Passing the calculated term directly to the UI
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
                : (_currentStep == _totalSteps - 1 ? _handleSave : _nextStep),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              elevation: 0,
            ),
            child: _saving
                ? const CustomLoader(size: 24, color: Colors.white)
                : Text(
                    _currentStep == _totalSteps - 1 ? 'Continue to Documents' : 'Next Step',
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
    int? maxLength,
    TextAlign textAlign = TextAlign.start,
    bool readOnly = false,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        inputFormatters: formatters,
        maxLines: maxLines,
        maxLength: maxLength,
        textAlign: textAlign,
        readOnly: readOnly,
        validator: validator,
        style: TextStyle(
          fontSize: 15, 
          fontWeight: FontWeight.w500, 
          color: readOnly ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5) : Theme.of(context).colorScheme.onSurface,
        ),
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

class _SelectionCard extends StatelessWidget {
  const _SelectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected ? scheme.primary.withValues(alpha: 0.15) : scheme.surfaceContainerHighest.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.5),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 32, color: isSelected ? scheme.primary : scheme.onSurface.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? scheme.primary : scheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
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

class _PremiumRepaymentSummary extends StatelessWidget {
  final LoanPreview preview;
  final double amountRequested;
  final int? termMonths;

  const _PremiumRepaymentSummary({
    required this.preview, 
    required this.amountRequested,
    this.termMonths,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final formatter = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    
    // Updated to accept num? to safely handle the double? from LoanPreview
    String format(num? value) => (value ?? 0).toStringAsFixed(0).replaceAllMapped(formatter, (Match m) => '${m[1]},');
    
    // Calculate UI-only display metrics safely
    final installment = preview.installmentAmount ?? 0.0;
    final months = termMonths ?? 0;
    final totalRepayment = installment * months;
    final interestAmount = totalRepayment > amountRequested ? (totalRepayment - amountRequested) : 0.0;
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 30, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        children: [
          // Top Receipt Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Text('ESTIMATED INSTALLMENT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: scheme.primary)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('UGX ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: scheme.primary.withValues(alpha: 0.7))),
                    Text(format(installment), style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1.5, color: scheme.primary)),
                  ],
                ),
                Text('per month for $months months', style: TextStyle(fontSize: 14, color: scheme.primary.withValues(alpha: 0.8))),
              ],
            ),
          ),
          
          // Dashed Divider
          Row(
            children: List.generate(30, (index) => Expanded(
              child: Container(color: index.isEven ? scheme.outlineVariant : Colors.transparent, height: 1),
            )),
          ),
          
          // Breakdown Details
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _SummaryRow('Principal Amount', 'UGX ${format(amountRequested)}'),
                const SizedBox(height: 16),
                _SummaryRow('Estimated Interest', '+ UGX ${format(interestAmount)}'),
                const SizedBox(height: 16),
                // Assuming processingFee is a field on LoanPreview. 
                // Using dynamic lookup in case it's named differently, but type-safe format.
                _SummaryRow('Processing Fee', 'UGX ${format(preview.processingFee)}', isSub: true),
                
                const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Repayment', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    Text('UGX ${format(totalRepayment)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  ],
                ),
              ],
            ),
          ),
          
          // DTI Warning (if applicable)
          if (preview.dtiExceeded && preview.debtToIncomeRatio != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFD9534F).withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFD9534F), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Debt-to-income ratio is ${preview.debtToIncomeRatio!.toStringAsFixed(1)}%. '
                      'This exceeds the standard threshold and will be flagged for committee review.',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFD9534F), height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isSub;

  const _SummaryRow(this.label, this.value, {this.isSub = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: scheme.onSurface.withValues(alpha: isSub ? 0.5 : 0.7), fontSize: 15)),
        Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface.withValues(alpha: isSub ? 0.5 : 1), fontSize: 15)),
      ],
    );
  }
}