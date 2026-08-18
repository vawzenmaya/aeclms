// lib/features/loans/presentation/widgets/repayments_view.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../../core/widgets/custom_loader.dart';

class RepaymentsView extends StatefulWidget {
  const RepaymentsView({super.key, required this.profileId});
  final String profileId;

  @override
  State<RepaymentsView> createState() => _RepaymentsViewState();
}

class _RepaymentsViewState extends State<RepaymentsView> {
  bool _loadingLoans = true;
  bool _loadingDetails = false;
  
  List<Map<String, dynamic>> _userLoans = [];
  String? _selectedLoanId;
  
  List<Map<String, dynamic>> _schedule = [];
  List<Map<String, dynamic>> _repayments = [];
  Map<String, dynamic>? _selectedLoanData;

  @override
  void initState() {
    super.initState();
    _fetchUserLoans();
  }

  /// Fetches any loans belonging to the user that are approved, active, or cleared
  Future<void> _fetchUserLoans() async {
    try {
      final response = await Supabase.instance.client
          .from('loans')
          .select('id, amount_requested, loan_category, created_at, status')
          .eq('applicant_id', widget.profileId)
          .inFilter('status', ['approved', 'active', 'cleared', 'disbursed', 'completed'])
          .order('created_at', ascending: false);

      final loans = List<Map<String, dynamic>>.from(response);
      
      if (mounted) {
        setState(() {
          _userLoans = loans;
          if (loans.isNotEmpty) {
            _selectedLoanId = loans.first['id'] as String;
          }
          _loadingLoans = false;
        });
        if (_selectedLoanId != null) {
          _fetchLoanRepaymentsDetails();
        }
      }
    } catch (e) {
      debugPrint('Error fetching user loans: $e');
      if (mounted) setState(() => _loadingLoans = false);
    }
  }

  /// Fetches both the complete Amortization Schedule and the posted Repayments logs
  Future<void> _fetchLoanRepaymentsDetails() async {
    if (_selectedLoanId == null) return;
    setState(() => _loadingDetails = true);

    try {
      final supabase = Supabase.instance.client;
      
      // 1. Fetch loan basic details again to get up-to-date metrics
      final loanData = await supabase.from('loans').select('*').eq('id', _selectedLoanId!).single();

      // 2. Fetch entire amortization schedule structure
      final scheduleResponse = await supabase
          .from('loan_amortization_schedule')
          .select('*')
          .eq('loan_id', _selectedLoanId!)
          .order('period_number', ascending: true);

      // 3. Fetch all payments made so far
      final repaymentsResponse = await supabase
          .from('repayments')
          .select('*')
          .eq('loan_id', _selectedLoanId!)
          .order('due_date', ascending: true);

      if (mounted) {
        setState(() {
          _selectedLoanData = loanData;
          _schedule = List<Map<String, dynamic>>.from(scheduleResponse);
          _repayments = List<Map<String, dynamic>>.from(repaymentsResponse);
          _loadingDetails = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching repayment data blocks: $e');
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currency = NumberFormat("#,##0", "en_US");

    if (_loadingLoans) {
      return Center(child: CustomLoader(size: 48, color: scheme.primary));
    }

    if (_userLoans.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.account_balance_wallet_outlined, size: 64, color: scheme.onSurface.withValues(alpha: 0.2)),
              const SizedBox(height: 16),
              Text('No Running Loans', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: scheme.onSurface)),
              const SizedBox(height: 8),
              Text(
                'Once your applied loan is authorized and disbursed by the treasurer, your payment ledger and schedule will automatically appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: scheme.onSurface.withValues(alpha: 0.6), height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    // Math metrics
    final totalInstallments = _schedule.length;
    final installmentsMade = _repayments.length;
    final remainingInstallments = totalInstallments - installmentsMade;

    return RefreshIndicator(
      onRefresh: _fetchLoanRepaymentsDetails,
      color: scheme.primary,
      backgroundColor: scheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // LOAN SELECTOR DROPDOWN (If user has multiple loans)
          Text('Select Account Ledger', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary, fontSize: 13)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedLoanId,
            dropdownColor: scheme.surface,
            isExpanded: true,
            decoration: InputDecoration(
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            items: _userLoans.map((l) {
              final date = DateFormat('MMM yyyy').format(DateTime.parse(l['created_at']));
              final cat = l['loan_category'] == 'emergency' ? 'Emergency' : 'Normal';
              return DropdownMenuItem<String>(
                value: l['id'],
                child: Text('$cat Loan — UGX ${currency.format(l['amount_requested'])} ($date)', style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface)),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedLoanId = val);
                _fetchLoanRepaymentsDetails();
              }
            },
          ),

          const SizedBox(height: 24),

          if (_loadingDetails)
            SizedBox(height: 200, child: Center(child: CustomLoader(size: 40, color: scheme.primary)))
          else ...[
            // COUNTER CARDS
            Row(
              children: [
                Expanded(
                  child: _MetricCounterBox(
                    title: 'Installments Paid',
                    count: '$installmentsMade',
                    subtitle: 'Months Cleared',
                    icon: Icons.check_circle_rounded,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetricCounterBox(
                    title: 'Remaining Period',
                    count: '$remainingInstallments',
                    subtitle: 'Months Pending',
                    icon: Icons.pending_actions_rounded,
                    color: remainingInstallments == 0 ? Colors.green : const Color(0xFFE9A63C),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // LEDGER STATEMENT TABLE
            Text('Amortization & Payment Ledger', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: scheme.onSurface)),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(scheme.primary.withValues(alpha: 0.05)),
                    horizontalMargin: 16,
                    columns: [
                      DataColumn(label: Text('Month', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary))),
                      DataColumn(label: Text('Due Date', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary))),
                      DataColumn(label: Text('Installment (UGX)', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary))),
                      DataColumn(label: Text('Remaining Balance', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary))),
                      DataColumn(label: Text('Ledger Status', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary))),
                    ],
                    rows: _schedule.map((row) {
                      final periodNum = row['period_number'] as int;
                      final isPaid = periodNum <= installmentsMade;
                      
                      final formattedDate = DateFormat('MMM dd, yyyy').format(DateTime.parse(row['due_date']));

                      return DataRow(
                        cells: [
                          DataCell(Text('#$periodNum', style: const TextStyle(fontWeight: FontWeight.w600))),
                          DataCell(Text(formattedDate)),
                          DataCell(Text(currency.format(row['installment']))),
                          DataCell(Text('UGX ${currency.format(row['balance'])}')),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isPaid ? Colors.green.withValues(alpha: 0.1) : const Color(0xFFE9A63C).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isPaid ? 'PAID' : 'PENDING',
                                style: TextStyle(
                                  fontSize: 11, 
                                  fontWeight: FontWeight.w800, 
                                  color: isPaid ? Colors.green : const Color(0xFFE9A63C)
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ]
        ],
      ),
    );
  }
}

class _MetricCounterBox extends StatelessWidget {
  const _MetricCounterBox({
    required this.title,
    required this.count,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String count;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface.withValues(alpha: 0.6)),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(count, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: scheme.onSurface, letterSpacing: -1)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.5))),
        ],
      ),
    );
  }
}