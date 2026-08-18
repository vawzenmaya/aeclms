// lib/features/loans/presentation/repayments_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/widgets/custom_loader.dart';

class RepaymentsScreen extends StatefulWidget {
  const RepaymentsScreen({super.key, required this.profileId});
  final String profileId;

  @override
  State<RepaymentsScreen> createState() => _RepaymentsScreenState();
}

class _RepaymentsScreenState extends State<RepaymentsScreen> {
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

  Future<void> _fetchLoanRepaymentsDetails() async {
    if (_selectedLoanId == null) return;
    setState(() => _loadingDetails = true);

    try {
      final supabase = Supabase.instance.client;
      final loanData = await supabase.from('loans').select('*').eq('id', _selectedLoanId!).single();
      final scheduleResponse = await supabase.from('loan_amortization_schedule').select('*').eq('loan_id', _selectedLoanId!).order('period_number', ascending: true);
      final repaymentsResponse = await supabase.from('repayments').select('*').eq('loan_id', _selectedLoanId!).order('due_date', ascending: true);

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

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Repayments Ledger', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5)),
        centerTitle: true,
      ),
      body: _buildBody(scheme, currency),
    );
  }

  Widget _buildBody(ColorScheme scheme, NumberFormat currency) {
    if (_loadingLoans) return Center(child: CustomLoader(size: 48, color: scheme.primary));

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

    final totalInstallments = _schedule.length;
    final installmentsMade = _repayments.length;
    final remainingInstallments = totalInstallments - installmentsMade;
    
    // Financial Metrics
    final totalPaidCash = _repayments.fold(0.0, (sum, r) => sum + (r['amount'] as num));
    final requestedAmount = (_selectedLoanData?['amount_requested'] as num?)?.toDouble() ?? 0.0;
    final remainingPrincipal = installmentsMade > 0 
        ? (_schedule[installmentsMade - 1]['balance'] as num).toDouble() 
        : requestedAmount;

    return RefreshIndicator(
      onRefresh: _fetchLoanRepaymentsDetails,
      color: scheme.primary,
      backgroundColor: scheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // STYLISH PREMIUM LOAN SELECTOR
          Text('Select Account Ledger', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary, fontSize: 13)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedLoanId,
                isExpanded: true,
                dropdownColor: scheme.surface,
                borderRadius: BorderRadius.circular(20),
                icon: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Icon(Icons.unfold_more_rounded, color: scheme.onSurface.withValues(alpha: 0.5)),
                ),
                // 1. HOW IT LOOKS WHEN THE MENU IS OPEN
                items: _userLoans.map((l) {
                  final date = DateFormat('MMM dd, yyyy').format(DateTime.parse(l['created_at']));
                  final cat = l['loan_category'] == 'emergency' ? 'Emergency' : 'Normal';
                  return DropdownMenuItem<String>(
                    value: l['id'],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$cat Loan — UGX ${currency.format(l['amount_requested'])}', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface, fontSize: 15)),
                          const SizedBox(height: 2),
                          Text('Applied: $date', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5), fontSize: 12, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                // 2. HOW IT LOOKS WHEN CLOSED (Selected State)
                selectedItemBuilder: (BuildContext context) {
                  return _userLoans.map<Widget>((l) {
                    final cat = l['loan_category'] == 'emergency' ? 'Emergency' : 'Normal';
                    return Row(
                      children: [
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                          child: Icon(Icons.account_balance_wallet_rounded, size: 18, color: scheme.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '$cat Loan — UGX ${currency.format(l['amount_requested'])}',
                            style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface, fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    );
                  }).toList();
                },
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedLoanId = val);
                    _fetchLoanRepaymentsDetails();
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          if (_loadingDetails)
            SizedBox(height: 200, child: Center(child: CustomLoader(size: 40, color: scheme.primary)))
          else ...[
            // 1. TIME TRACKING CARDS
            Row(
              children: [
                Expanded(
                  child: _MetricCounterBox(
                    title: 'Installments Paid', count: '$installmentsMade', subtitle: 'Months Cleared',
                    icon: Icons.check_circle_rounded, color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetricCounterBox(
                    title: 'Remaining Period', count: '$remainingInstallments', subtitle: 'Months Pending',
                    icon: Icons.pending_actions_rounded, color: remainingInstallments == 0 ? Colors.green : const Color(0xFFE9A63C),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 2. FINANCIAL PROGRESS GRAPHIC
            _PaymentProgressCard(
              requestedAmount: requestedAmount,
              remainingPrincipal: remainingPrincipal,
              totalPaidCash: totalPaidCash,
              currency: currency,
            ),
            
            const SizedBox(height: 32),
            Text('Amortization & Payment Ledger', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: scheme.onSurface)),
            const SizedBox(height: 12),
            
            // 3. THE DATATABLE (With visually shaded completed rows)
            Container(
              decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5))),
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
                      
                      final textColor = isPaid ? scheme.onSurface.withValues(alpha: 0.4) : scheme.onSurface;
                      final textWeight = isPaid ? FontWeight.w500 : FontWeight.w700;

                      return DataRow(
                        color: WidgetStateProperty.all(
                          isPaid ? scheme.surfaceContainerHighest.withValues(alpha: 0.2) : Colors.transparent
                        ),
                        cells: [
                          DataCell(Text('#$periodNum', style: TextStyle(fontWeight: textWeight, color: textColor))),
                          DataCell(Text(formattedDate, style: TextStyle(fontWeight: textWeight, color: textColor))),
                          DataCell(Text(currency.format(row['installment']), style: TextStyle(fontWeight: textWeight, color: textColor))),
                          DataCell(Text('UGX ${currency.format(row['balance'])}', style: TextStyle(fontWeight: textWeight, color: textColor))),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isPaid ? Colors.green.withValues(alpha: 0.1) : const Color(0xFFE9A63C).withValues(alpha: 0.15), 
                                borderRadius: BorderRadius.circular(8)
                              ),
                              child: Text(
                                isPaid ? 'CLEARED' : 'PENDING', 
                                style: TextStyle(
                                  fontSize: 11, 
                                  fontWeight: FontWeight.w800, 
                                  color: isPaid ? Colors.green.withValues(alpha: 0.6) : const Color(0xFFE9A63C)
                                )
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
  const _MetricCounterBox({required this.title, required this.count, required this.subtitle, required this.icon, required this.color});
  final String title; final String count; final String subtitle; final IconData icon; final Color color;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, size: 16, color: color), const SizedBox(width: 8), Expanded(child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface.withValues(alpha: 0.6)), maxLines: 1, overflow: TextOverflow.ellipsis))]),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(count, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: scheme.onSurface, letterSpacing: -1)),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.5))),
        ],
      ),
    );
  }
}

/// A stunning graphical representation of the user's financial progress.
class _PaymentProgressCard extends StatelessWidget {
  final double requestedAmount;
  final double remainingPrincipal;
  final double totalPaidCash;
  final NumberFormat currency;

  const _PaymentProgressCard({
    required this.requestedAmount,
    required this.remainingPrincipal,
    required this.totalPaidCash,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    // Calculate exact percentage based purely on Principal cleared.
    // (We don't use totalPaidCash against requestedAmount because totalPaidCash includes interest).
    final principalCleared = (requestedAmount - remainingPrincipal).clamp(0.0, requestedAmount);
    final double progress = requestedAmount > 0 ? (principalCleared / requestedAmount).clamp(0.0, 1.0) : 0.0;
    final int percentage = (progress * 100).floor();
    final bool isFullyPaid = percentage == 100;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // THE DONUT CHART
              SizedBox(
                height: 90,
                width: 90,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: 1.0, // The full background track
                      strokeWidth: 8,
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.0, end: progress),
                      duration: const Duration(milliseconds: 1200),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) {
                        return CircularProgressIndicator(
                          value: value,
                          strokeWidth: 8,
                          strokeCap: StrokeCap.round,
                          color: isFullyPaid ? Colors.green : scheme.primary,
                        );
                      },
                    ),
                    Center(
                      child: Text(
                        '$percentage%',
                        style: TextStyle(
                          fontSize: 20, 
                          fontWeight: FontWeight.w800, 
                          letterSpacing: -1,
                          color: isFullyPaid ? Colors.green : scheme.onSurface
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              
              // THE TEXT DETAILS
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Principal Cleared', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface.withValues(alpha: 0.6))),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('UGX ${currency.format(principalCleared)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: scheme.onSurface)),
                    ),
                    
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1)),
                    
                    Text('Remaining Principal', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface.withValues(alpha: 0.6))),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'UGX ${currency.format(remainingPrincipal)}', 
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: isFullyPaid ? Colors.green : const Color(0xFFD9534F))
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // EXTRA DETAIL: CASH OUT OF POCKET
          if (totalPaidCash > 0) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.payments_rounded, size: 16, color: scheme.primary.withValues(alpha: 0.8)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Total Cash Paid (Includes Interest)', 
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurface.withValues(alpha: 0.7)),
                    ),
                  ),
                  Text('UGX ${currency.format(totalPaidCash)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                ],
              ),
            )
          ]
        ],
      ),
    );
  }
}