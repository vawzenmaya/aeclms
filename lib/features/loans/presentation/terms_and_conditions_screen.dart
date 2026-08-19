// lib/features/loans/presentation/terms_and_conditions_screen.dart

import 'package:flutter/material.dart';
import '../../auth/data/auth_service.dart';
import '../data/loan_repository.dart';
import 'application_form_screen.dart';

class TermsAndConditionsScreen extends StatefulWidget {
  final LoanRepository repository;
  final Profile profile;
  final String? currentUserEmail;

  const TermsAndConditionsScreen({
    super.key,
    required this.repository,
    required this.profile,
    required this.currentUserEmail,
  });

  @override
  State<TermsAndConditionsScreen> createState() => _TermsAndConditionsScreenState();
}

class _TermsAndConditionsScreenState extends State<TermsAndConditionsScreen> {
  bool _hasAgreed = false;

  void _proceedToApplication() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ApplicationFormScreen(
          repository: widget.repository,
          profile: widget.profile,
          currentUserEmail: widget.currentUserEmail,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Terms & Conditions', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5)),
        centerTitle: true,
      ),
      // RESPONSIVE: Center and constrain the body to 800px max width
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.gavel_rounded, color: scheme.primary, size: 28),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              'Atomic Energy Council Investment Club',
                              style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary, fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    Text('1. Eligibility & Requirements', style: _headerStyle(scheme)),
                    _paragraph('• A borrower must provide a signed employment contract.\n• You must secure one guarantor who is currently a member of the AEC investment club.'),
                    
                    Text('2. Interest & Repayment Rules', style: _headerStyle(scheme)),
                    _paragraph('• The annual interest rate for members is 10%, which is charged using the reducing balance method.\n• The loan repayment period shall not exceed your remaining contract period.\n• If you choose to prepay the loan before the agreed time, you will refund 10% of the principal of the remaining balance.'),
        
                    Text('3. Salary Deduction Consent', style: _headerStyle(scheme)),
                    _paragraph('• The loan payment will automatically be deducted from your monthly salary.\n• By agreeing to this, you voluntarily authorize this deduction from your monthly net salary pursuant to Section 46 (1) (b) of the Employment Act 2006.'),
        
                    Text('4. Default & Late Penalties', style: _headerStyle(scheme)),
                    _paragraph('• Any payment not remunerated within ten (10) days of its due date shall be subject to a late charge of 5% of the payment.\n• If you fail to make payments on time, the club can demand instant payment of the entire remaining unpaid balance without further notice.\n• If the full amount is not paid when the final payment is due, you will be charged interest on the unpaid balance at 6% per week.\n• If placed with a legal representative for collection, you agree to pay an attorney\'s fee of fifteen percent (15%) of the voluntary balance.'),
        
                    Text('5. Accountability & Membership', style: _headerStyle(scheme)),
                    _paragraph('• Any guarantor signing the agreement is likewise accountable with the borrower for the loan.\n• If you cease membership to the Investment Club before full repayment, the club will automatically deduct the outstanding loan balance from your Savings.'),
                  ],
                ),
              ),
              
              // BOTTOM CONSENT DOCK
              Container(
                padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, -5))],
                  border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _hasAgreed = !_hasAgreed),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _hasAgreed,
                              onChanged: (val) => setState(() => _hasAgreed = val ?? false),
                              activeColor: scheme.primary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'I have read, understood, and agree to the Club\'s terms, conditions, and salary deduction policies.',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface.withValues(alpha: 0.8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _hasAgreed ? _proceedToApplication : null,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Accept & Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _headerStyle(ColorScheme scheme) {
    return TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: scheme.onSurface, letterSpacing: -0.3);
  }

  Widget _paragraph(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      child: Text(text, style: TextStyle(fontSize: 14, height: 1.6, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
    );
  }
}