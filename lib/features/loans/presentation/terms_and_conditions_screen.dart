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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Atomic Energy Council Investment Club',
                                  style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary, fontSize: 16),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Rules governing members who wish to take credit.',
                                  style: TextStyle(fontWeight: FontWeight.w600, color: scheme.primary.withValues(alpha: 0.8), fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    Text('1. Eligibility & Documentation', style: _headerStyle(scheme)),
                    _paragraph(
                      '• A borrower shall get one guarantor who is also a member of the AEC investment club.\n'
                      '• A member, who would like to take a loan, shall provide a signed employment contract and an appointment letter.'
                    ),
                    
                    Text('2. Interest Rates & Limits', style: _headerStyle(scheme)),
                    _paragraph(
                      '• Annual Interest rate for members is 10% to be charged on reducing balance method.\n'
                      '• Annual interest rate for members taking emergency loan is 4% charged on reducing balance method.\n'
                      '• A borrower can get up to a maximum determined during loan assessment by the Credit committee.\n'
                      '• No top ups shall be allowed for Emergency loans.'
                    ),
        
                    Text('3. Repayment & Deductions', style: _headerStyle(scheme)),
                    _paragraph(
                      '• The loan payment will automatically be deducted from one’s monthly salary.\n'
                      '• A borrower’s repayment period shall not exceed his/her remaining contract period, for loans above the members savings.\n'
                      '• A borrower’s maximum repayment period shall not exceed 5 years for loans below the members available savings.\n'
                      '• For members taking emergency loans, the total repayment amount shall not exceed 40% of the members salary net pay. And the maximum repayment period shall be 3 months.'
                    ),
        
                    Text('4. Approvals & Membership Status', style: _headerStyle(scheme)),
                    _paragraph(
                      '• Approval of the loan payment shall be done by the accounting officer of AEC in addition to the persons mentioned in the constitution after consideration from the loan and credit committee.\n'
                      '• For a borrower who ceases membership to the Investment Club before full repayment of the loan, the club will deduct the outstanding loan balance from his/her Savings.'
                    ),
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
                              'I have read and understood the rules governing the acquisition of the loan from the club.',
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