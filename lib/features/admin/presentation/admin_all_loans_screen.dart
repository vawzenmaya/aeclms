// lib/features/admin/presentation/admin_all_loans_screen.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/custom_loader.dart';
import '../../auth/data/auth_service.dart';
import '../../loans/data/loan_repository.dart';
import '../../loans/presentation/loan_detail_screen.dart';
import '../../loans/presentation/widgets/loan_status_chip.dart';
import '../services/pdf_report_service.dart';

class AdminAllLoansScreen extends StatefulWidget {
  final Profile profile;
  final LoanRepository repository;

  const AdminAllLoansScreen({
    super.key,
    required this.profile,
    required this.repository,
  });

  @override
  State<AdminAllLoansScreen> createState() => _AdminAllLoansScreenState();
}

class _AdminAllLoansScreenState extends State<AdminAllLoansScreen> {
  bool _loading = true;
  bool _isGeneratingPdf = false;
  List<Map<String, dynamic>> _allLoans = [];
  String _selectedFilter = 'all';
  String? _error;

  final currency = NumberFormat("#,##0", "en_US");

  @override
  void initState() {
    super.initState();
    _fetchAllSystemLoans();
  }

  Future<void> _fetchAllSystemLoans() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Fetch loans, profile names, AND their full repayment/amortization history in one query!
      final response = await Supabase.instance.client
          .from('loans')
          .select('''
            *, 
            profiles!loans_applicant_id_fkey(full_name),
            repayments(amount),
            loan_amortization_schedule(period_number, balance)
          ''')
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _allLoans = List<Map<String, dynamic>>.from(response);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load system loans: $e';
        _loading = false;
      });
    }
  }

  void _openLoan(Map<String, dynamic> loan) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoanDetailScreen(
          repository: widget.repository,
          profile: widget.profile,
          loanId: loan['id'] as String,
        ),
      ),
    );
    _fetchAllSystemLoans(); // Refresh when returning
  }

  // Gets the currently filtered list
  List<Map<String, dynamic>> get _filteredLoans {
    return _allLoans.where((loan) {
      if (_selectedFilter == 'all') return true;
      if (_selectedFilter == 'pending') return loan['status'] == 'in_review';
      return loan['status'] == _selectedFilter;
    }).toList();
  }

  Future<void> _printCurrentView() async {
    setState(() => _isGeneratingPdf = true);
    try {
      final loansToPrint = _filteredLoans;
      final List<Map<String, dynamic>> formattedData = [];

      for (var loan in loansToPrint) {
        final repayments = (loan['repayments'] as List?) ?? [];
        final amountRequested = (loan['amount_requested'] as num?)?.toDouble() ?? 0.0;
        final totalMonths = loan['duration_months'] as int? ?? 0;
        final monthsPaid = repayments.length;

        formattedData.add({
          'name': loan['profiles']?['full_name'] ?? 'Unknown Applicant',
          'approved_amount': amountRequested, 
          'monthly_installment': loan['installment_amount'] ?? 0.0, 
          'total_months': totalMonths,
          'remaining_months': max(0, totalMonths - monthsPaid),
          'clearance_month': loan['expected_end_date'] != null 
              ? DateFormat('MMM yyyy').format(DateTime.parse(loan['expected_end_date'])) 
              : '-',
          'status': loan['status'] == 'cleared' ? 'Cleared' : (['approved', 'active', 'completed'].contains(loan['status']) ? 'Running' : 'Pending'),
        });
      }

      String filterLabel = 'All';
      if (_selectedFilter == 'approved') filterLabel = 'Running';
      if (_selectedFilter == 'cleared') filterLabel = 'Cleared';

      await PdfReportService.generateMasterSchedule(
        reportMonth: DateFormat('MMMM yyyy').format(DateTime.now()),
        loans: formattedData,
        filterStatus: filterLabel,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate PDF: $e'), backgroundColor: const Color(0xFFD9534F)));
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentList = _filteredLoans;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        title: const Text('System Loans', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5)),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Filter Chips Section
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2)),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  _FilterChip(label: 'All Loans', value: 'all', groupValue: _selectedFilter, onChanged: (v) => setState(() => _selectedFilter = v)),
                  _FilterChip(label: 'Active / Running', value: 'approved', groupValue: _selectedFilter, onChanged: (v) => setState(() => _selectedFilter = v)),
                  _FilterChip(label: 'Cleared', value: 'cleared', groupValue: _selectedFilter, onChanged: (v) => setState(() => _selectedFilter = v)),
                  _FilterChip(label: 'Pending', value: 'pending', groupValue: _selectedFilter, onChanged: (v) => setState(() => _selectedFilter = v)),
                ],
              ),
            ),
          ),
          
          // List Section
          Expanded(
            child: _loading
                ? Center(child: CustomLoader(size: 56, color: scheme.primary))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, style: const TextStyle(color: Color(0xFFD9534F), height: 1.5), textAlign: TextAlign.center),
                        ),
                      )
                    : currentList.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.folder_off_outlined, size: 64, color: scheme.onSurface.withValues(alpha: 0.2)),
                                const SizedBox(height: 16),
                                Text('No loans found for this filter.', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6))),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _fetchAllSystemLoans,
                            color: scheme.primary,
                            backgroundColor: scheme.surface,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(24),
                              itemCount: currentList.length,
                              itemBuilder: (context, index) {
                                final loan = currentList[index];
                                
                                // --- FINANCIAL & PROGRESS CALCULATIONS ---
                                final repayments = (loan['repayments'] as List?) ?? [];
                                final schedule = (loan['loan_amortization_schedule'] as List?) ?? [];
                                schedule.sort((a, b) => (a['period_number'] as int).compareTo(b['period_number'] as int));

                                final amountRaw = (loan['amount_requested'] as num?)?.toDouble() ?? 0.0;
                                final totalMonths = loan['duration_months'] as int? ?? 0;
                                final monthsPaid = repayments.length;
                                final monthsRemaining = totalMonths > monthsPaid ? totalMonths - monthsPaid : 0;

                                final totalPaid = repayments.fold(0.0, (sum, r) => sum + (r['amount'] as num));
                                
                                double remainingPrincipal = amountRaw;
                                if (monthsPaid > 0 && schedule.length >= monthsPaid) {
                                  remainingPrincipal = (schedule[monthsPaid - 1]['balance'] as num).toDouble();
                                } else if (monthsPaid >= totalMonths && totalMonths > 0) {
                                  remainingPrincipal = 0.0;
                                }

                                final progress = totalMonths > 0 ? (monthsPaid / totalMonths).clamp(0.0, 1.0) : 0.0;
                                // ------------------------------------------
                                
                                String applicantName = loan['profiles']?['full_name'] ?? 'Unknown Applicant';
                                final dateStr = loan['created_at'] != null ? DateFormat('MMM dd, yyyy').format(DateTime.parse(loan['created_at'])) : 'Unknown Date';
                                final isCleared = loan['status'] == 'cleared' || loan['status'] == 'completed';

                                return _StaggeredFadeIn(
                                  index: index,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 20),
                                    decoration: BoxDecoration(
                                      color: scheme.surface,
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => _openLoan(loan),
                                        borderRadius: BorderRadius.circular(24),
                                        child: Padding(
                                          padding: const EdgeInsets.all(20),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // HEADER
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      applicantName,
                                                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: scheme.onSurface),
                                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  LoanStatusChip(status: loan['status'] ?? 'draft'),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text('Applied: $dateStr', style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.5))),
                                              
                                              const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),
                                              
                                              // CORE AMOUNT
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text('Amount Requested', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface.withValues(alpha: 0.6))),
                                                      const SizedBox(height: 4),
                                                      Text('UGX ${currency.format(amountRaw)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: scheme.primary, letterSpacing: -0.5)),
                                                    ],
                                                  ),
                                                  Column(
                                                    crossAxisAlignment: CrossAxisAlignment.end,
                                                    children: [
                                                      Text('Monthly EMI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface.withValues(alpha: 0.6))),
                                                      const SizedBox(height: 4),
                                                      Text('UGX ${currency.format(loan['installment_amount'] ?? 0)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                                                    ],
                                                  ),
                                                ],
                                              ),

                                              // ONLY SHOW PROGRESS IF IT IS AN ACTIVE OR CLEARED LOAN
                                              if (['approved', 'active', 'cleared', 'completed', 'disbursed'].contains(loan['status'])) ...[
                                                const SizedBox(height: 20),
                                                
                                                // PROGRESS BAR
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: ClipRRect(
                                                        borderRadius: BorderRadius.circular(4),
                                                        child: LinearProgressIndicator(
                                                          value: progress,
                                                          minHeight: 6,
                                                          backgroundColor: scheme.surfaceContainerHighest,
                                                          valueColor: AlwaysStoppedAnimation<Color>(isCleared ? Colors.green : scheme.primary),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Text('${(progress * 100).toInt()}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: isCleared ? Colors.green : scheme.primary)),
                                                  ],
                                                ),
                                                const SizedBox(height: 16),
                                                
                                                // 4-GRID METRICS
                                                Container(
                                                  padding: const EdgeInsets.all(12),
                                                  decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            _MiniStat(label: 'Months Paid', value: '$monthsPaid mo', color: scheme.onSurface),
                                                            const SizedBox(height: 8),
                                                            _MiniStat(label: 'Amount Paid', value: currency.format(totalPaid), color: scheme.onSurface),
                                                          ],
                                                        ),
                                                      ),
                                                      Container(width: 1, height: 40, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                                                      const SizedBox(width: 12),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            _MiniStat(label: 'Months Left', value: '$monthsRemaining mo', color: isCleared ? Colors.green : const Color(0xFFE9A63C)),
                                                            const SizedBox(height: 8),
                                                            _MiniStat(label: 'Balance Left', value: currency.format(remainingPrincipal), color: isCleared ? Colors.green : const Color(0xFFD9534F)),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
      floatingActionButton: _filteredLoans.isNotEmpty 
          ? FloatingActionButton.extended(
              onPressed: _isGeneratingPdf ? null : _printCurrentView,
              backgroundColor: scheme.primary,
              icon: _isGeneratingPdf 
                  ? const CustomLoader(size: 20, color: Colors.white) 
                  : const Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
              label: Text(
                _isGeneratingPdf ? 'Generating...' : 'Print Report', 
                style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)
              ),
            )
          : null,
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
        Expanded(
          child: Text(
            value, 
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String groupValue;
  final Function(String) onChanged;

  const _FilterChip({required this.label, required this.value, required this.groupValue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = value == groupValue;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(value),
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? scheme.primary : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isSelected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? scheme.onPrimary : scheme.onSurface,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
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
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    Future.delayed(Duration(milliseconds: 50 * widget.index), () {
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
    return FadeTransition(opacity: _fadeAnimation, child: SlideTransition(position: _slideAnimation, child: widget.child));
  }
}