// lib/features/admin/presentation/admin_all_loans_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/custom_loader.dart';
import '../../auth/data/auth_service.dart';
import '../../loans/data/loan_repository.dart';
import '../../loans/presentation/loan_detail_screen.dart';
import '../../loans/presentation/widgets/loan_status_chip.dart';

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
      // Fetch ALL loans and join with profiles to get the applicant's name
      // Note: Your Supabase RLS policies must allow Admins to read all loans for this to work!
      final response = await Supabase.instance.client
          .from('loans')
          .select('*, profiles!loans_applicant_id_fkey(full_name)')
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
    _fetchAllSystemLoans(); // Refresh when returning in case the admin changed the loan status
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Apply local filtering
    final filteredLoans = _allLoans.where((loan) {
      if (_selectedFilter == 'all') return true;
      if (_selectedFilter == 'pending') return loan['status'] == 'in_review';
      return loan['status'] == _selectedFilter;
    }).toList();

    return Scaffold(
      appBar: AppBar(
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
                  // _FilterChip(label: 'Pending', value: 'pending', groupValue: _selectedFilter, onChanged: (v) => setState(() => _selectedFilter = v)),
                  _FilterChip(label: 'Active / Running', value: 'approved', groupValue: _selectedFilter, onChanged: (v) => setState(() => _selectedFilter = v)),
                  _FilterChip(label: 'Cleared', value: 'cleared', groupValue: _selectedFilter, onChanged: (v) => setState(() => _selectedFilter = v)),
                  // _FilterChip(label: 'Rejected', value: 'rejected', groupValue: _selectedFilter, onChanged: (v) => setState(() => _selectedFilter = v)),
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
                    : filteredLoans.isEmpty
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
                            child: ListView.builder(
                              padding: const EdgeInsets.all(24),
                              itemCount: filteredLoans.length,
                              itemBuilder: (context, index) {
                                final loan = filteredLoans[index];
                                final amountRaw = loan['amount_requested'] as num?;
                                final amountStr = amountRaw != null ? currency.format(amountRaw) : '0';
                                
                                // Extract name from the join
                                String applicantName = 'Unknown Applicant';
                                if (loan['profiles'] != null && loan['profiles']['full_name'] != null) {
                                  applicantName = loan['profiles']['full_name'];
                                }

                                final dateStr = loan['created_at'] != null 
                                    ? DateFormat('MMM dd, yyyy').format(DateTime.parse(loan['created_at']))
                                    : 'Unknown Date';

                                return _StaggeredFadeIn(
                                  index: index,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).cardTheme.color,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                                      boxShadow: [
                                        BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
                                      ],
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => _openLoan(loan),
                                        borderRadius: BorderRadius.circular(20),
                                        child: Padding(
                                          padding: const EdgeInsets.all(20),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      applicantName,
                                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  LoanStatusChip(status: loan['status'] ?? 'draft'),
                                                ],
                                              ),
                                              const Padding(
                                                padding: EdgeInsets.symmetric(vertical: 12),
                                                child: Divider(height: 1),
                                              ),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text('Amount Requested', style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6))),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        'UGX $amountStr', 
                                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: scheme.primary, letterSpacing: -0.5),
                                                      ),
                                                    ],
                                                  ),
                                                  Column(
                                                    crossAxisAlignment: CrossAxisAlignment.end,
                                                    children: [
                                                      Text('Applied On', style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6))),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        dateStr, 
                                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
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
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String groupValue;
  final Function(String) onChanged;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

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
              border: Border.all(
                color: isSelected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.5),
              ),
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
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}