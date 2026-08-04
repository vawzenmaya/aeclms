// lib/features/loans/presentation/application_form_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/amount_to_words.dart';
import '../../auth/data/auth_service.dart';
import '../data/loan_repository.dart';
import '../domain/loan_calculations.dart';
import 'widgets/repayment_preview_card.dart';

class ApplicationFormScreen extends StatefulWidget {
  const ApplicationFormScreen({
    super.key,
    required this.repository,
    required this.profile,
    required this.currentUserEmail,
  });

  final LoanRepository repository;
  final Profile profile;
  final String? currentUserEmail;

  @override
  State<ApplicationFormScreen> createState() => _ApplicationFormScreenState();
}

class _ApplicationFormScreenState extends State<ApplicationFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Loan classification
  String _loanType = 'new'; // new | topup
  String _loanCategory = 'normal'; // emergency | normal
  String _applicantCategory = 'member'; // member | non_member

  // Controllers
  late final _fullNameCtrl = TextEditingController(text: widget.profile.fullName);
  late final _emailCtrl = TextEditingController(text: widget.currentUserEmail ?? '');
  late final _phoneCtrl = TextEditingController(text: widget.profile.phone ?? '');
  late final _employeeNumberCtrl =
      TextEditingController(text: widget.profile.employeeNumber ?? '');
  final _amountCtrl = TextEditingController();
  final _amountInWordsCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController();
  final _securityDescCtrl = TextEditingController();
  final _securityValueCtrl = TextEditingController();
  final _netPayCtrl = TextEditingController();
  late final _bankHolderCtrl = TextEditingController(text: widget.profile.fullName);
  final _bankNameCtrl = TextEditingController();
  final _bankAccountCtrl = TextEditingController();
  final _bankSortCodeCtrl = TextEditingController();
  final _bankSwiftCtrl = TextEditingController();

  DateTime? _expectedEndDate;
  String? _guarantorId;
  bool _bankDetailsConfirmed = false;

  LoanSettings _settings = LoanSettings.fallback;
  List<GuarantorOption> _guarantors = [];
  bool _loadingContext = true;
  bool _saving = false;
  String? _error;

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
    );
    if (picked != null) {
      setState(() => _expectedEndDate = picked);
    }
  }

  Future<void> _handleSave({required bool submit}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_expectedEndDate == null) {
      setState(() => _error = 'Please choose an expected end date.');
      return;
    }
    if (submit && !_bankDetailsConfirmed) {
      setState(() => _error = 'Please confirm your bank details before submitting.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final loanId = await widget.repository.saveDraft(
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
        expectedEndDate: _expectedEndDate!,
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
      Navigator.of(context).pop(loanId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(submit ? 'Application submitted' : 'Draft saved')),
      );
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } catch (e, st) {
      // Temporary: surface the real error while we're debugging save issues.
      debugPrint('saveDraft/submit failed: $e\n$st');
      setState(() => _error = 'Error: $e');
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Loan Application')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionHeader('Loan type'),
            _card([
              _EnumChips(
                label: 'Category',
                value: _loanCategory,
                options: const {'normal': 'Normal', 'emergency': 'Emergency'},
                onChanged: (v) => setState(() {
                  _loanCategory = v;
                  if (v == 'emergency') _loanType = 'new'; // topups are normal-only
                }),
              ),
              const SizedBox(height: 8),
              _EnumChips(
                label: 'New or top-up',
                value: _loanType,
                options: {
                  'new': 'New loan',
                  if (_loanCategory == 'normal') 'topup': 'Top-up',
                },
                onChanged: (v) => setState(() => _loanType = v),
              ),
            ]),

            _SectionHeader('Applicant details'),
            _card([
              _EnumChips(
                label: 'Applicant category',
                value: _applicantCategory,
                options: const {'member': 'Member', 'non_member': 'Non-Member'},
                onChanged: (v) => setState(() {
                  _applicantCategory = v;
                  if (v == 'member') {
                    _employeeNumberCtrl.text = widget.profile.employeeNumber ?? '';
                  }
                }),
              ),
              const SizedBox(height: 12),
              _field(_fullNameCtrl, "Applicant's name", validator: _required),
              _field(_emailCtrl, 'Email', validator: _required),
              _field(_phoneCtrl, 'Phone number', validator: _required),
              _field(
                _employeeNumberCtrl,
                _applicantCategory == 'member' ? 'Employee Number (AEC/...)' : 'ID / Reference Number',
                validator: _required,
              ),
            ]),

            _SectionHeader('Loan details'),
            _card([
              _field(_amountCtrl, 'Amount applied for', keyboardType: TextInputType.number, validator: _requiredNumber),
              _field(_amountInWordsCtrl, 'Amount in words', maxLines: 2),
              _field(_purposeCtrl, 'Purpose of the loan', maxLines: 3, validator: _required),
              const SizedBox(height: 4),
              _DatePickerField(
                label: 'Expected end date (determines loan period)',
                value: _expectedEndDate,
                onTap: _pickEndDate,
              ),
              if (_termMonths != null) ...[
                const SizedBox(height: 6),
                Text('Period: $_termMonths month(s)', style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 12),
              _field(_netPayCtrl, 'Net pay (monthly)', keyboardType: TextInputType.number, validator: _requiredNumber),
            ]),

            _SectionHeader('Security & guarantor'),
            _card([
              _field(_securityDescCtrl, "Security's name (where necessary)"),
              _field(_securityValueCtrl, 'Estimated value', keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _guarantorId,
                decoration: const InputDecoration(labelText: 'Guarantor (optional)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('No guarantor needed')),
                  ..._guarantors.map((g) => DropdownMenuItem(value: g.id, child: Text(g.fullName))),
                ],
                onChanged: (v) => setState(() => _guarantorId = v),
              ),
              if (_guarantorId != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Your guarantor will be notified and must confirm digitally before '
                  'this application reaches the Loan Officer.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ]),

            _SectionHeader('Bank details for disbursement (RTGS)'),
            _card([
              _field(_bankHolderCtrl, 'Full legal name (as on account)', validator: _required),
              _field(_bankNameCtrl, 'Bank name', validator: _required),
              _field(_bankAccountCtrl, 'Account number', validator: _required),
              _field(_bankSortCodeCtrl, 'Sort code'),
              _field(_bankSwiftCtrl, 'SWIFT / BIC code', validator: _required),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _bankDetailsConfirmed,
                onChanged: (v) => setState(() => _bankDetailsConfirmed = v ?? false),
                title: const Text('I confirm these bank details are correct and I am the '
                    'authorized signatory on this account.'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ]),

            _SectionHeader('Preview'),
            RepaymentPreviewCard(
              preview: _preview,
              amountRequested: double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0,
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Color(0xFFD9534F))),
            ],

            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _handleSave(submit: false),
                    child: const Text('Save as draft'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : () => _handleSave(submit: true),
                    child: _saving
                        ? const SizedBox(
                            height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Submit'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      );

  Widget _field(
    TextEditingController ctrl,
    String label, {
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;
  String? _requiredNumber(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    if (double.tryParse(v.replaceAll(',', '')) == null) return 'Enter a valid number';
    return null;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary),
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
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: options.entries.map((e) {
            return ChoiceChip(
              label: Text(e.value),
              selected: value == e.key,
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
    final text = value == null
        ? 'Select a date'
        : '${value!.day}/${value!.month}/${value!.year}';
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(text),
            const Icon(Icons.calendar_today_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}
