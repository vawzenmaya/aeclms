// lib/features/loans/presentation/loan_list_screen.dart

import 'package:flutter/material.dart';
import '../../auth/data/auth_service.dart';
import '../data/loan_repository.dart';
import 'loan_detail_screen.dart';
import 'widgets/loan_status_chip.dart';

class LoanListScreen extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> loans;
  final LoanRepository repository;
  final Profile profile;
  final bool isActionRequired;
  final bool isHistory;

  const LoanListScreen({
    super.key,
    required this.title,
    required this.loans,
    required this.repository,
    required this.profile,
    this.isActionRequired = false,
    this.isHistory = false,
  });

  @override
  State<LoanListScreen> createState() => _LoanListScreenState();
}

class _LoanListScreenState extends State<LoanListScreen> {
  // We keep a local mutable copy so we can remove deleted drafts instantly
  late List<Map<String, dynamic>> _localLoans;

  @override
  void initState() {
    super.initState();
    _localLoans = List.from(widget.loans);
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
    // Note: To automatically refresh this list with backend changes when returning, 
    // you would typically convert this screen to fetch its own data. For now, we pop.
    if (mounted) Navigator.pop(context, true); 
  }

  Future<void> _confirmDelete(Map<String, dynamic> loan) async {
    final scheme = Theme.of(context).colorScheme;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFD9534F).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFD9534F)),
            ),
            const SizedBox(width: 12),
            const Text('Delete Draft?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
          ],
        ),
        content: const Text(
          'Are you sure you want to permanently delete this draft application? This action cannot be undone.',
          style: TextStyle(height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD9534F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.repository.deleteDraft(loan['id'] as String);
        setState(() {
          _localLoans.removeWhere((l) => l['id'] == loan['id']);
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft application securely deleted.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: const Color(0xFFD9534F)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        backgroundColor: scheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5)),
        centerTitle: true,
        elevation: 0,
      ),
      body: _localLoans.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.folder_off_outlined, size: 64, color: scheme.onSurface.withValues(alpha: 0.2)),
                    const SizedBox(height: 16),
                    Text('No loans found in this category.', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6))),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _localLoans.length,
              itemBuilder: (context, index) {
                final loan = _localLoans[index];
                final isDeletableDraft = loan['status'] == 'draft';

                return _LoanCard(
                  loan: loan,
                  isActionRequired: widget.isActionRequired,
                  isHistory: widget.isHistory,
                  onTap: () => _openLoan(loan),
                  onDelete: isDeletableDraft ? () => _confirmDelete(loan) : null,
                );
              },
            ),
    );
  }
}

// Inherited directly from your original dashboard code
class _LoanCard extends StatelessWidget {
  const _LoanCard({
    required this.loan, 
    required this.onTap, 
    this.isActionRequired = false,
    this.isHistory = false,
    this.onDelete,
  });
  
  final Map<String, dynamic> loan;
  final VoidCallback onTap;
  final bool isActionRequired;
  final bool isHistory;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amountRaw = loan['amount_requested'] as num?;
    
    final amountString = amountRaw != null 
        ? amountRaw.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},') 
        : '-';
        
    final name = loan['full_name'] as String? ?? 'Applicant';
    final isEmergency = loan['loan_category'] == 'emergency';
    final category = isEmergency ? 'Emergency' : 'Normal';
    
    final cardBorder = isActionRequired 
        ? Border.all(color: scheme.primary.withValues(alpha: 0.5), width: 1.5)
        : Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5), width: 1);
        
    final shadow = isActionRequired
        ? [BoxShadow(color: scheme.primary.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 8))]
        : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 4))];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isHistory ? scheme.surfaceContainerHighest.withValues(alpha: 0.2) : Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        border: cardBorder,
        boxShadow: shadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isEmergency 
                                ? const Color(0xFFE9A63C).withValues(alpha: 0.15) 
                                : scheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isEmergency ? Icons.bolt_rounded : Icons.account_balance_rounded,
                            size: 18,
                            color: isEmergency ? const Color(0xFFE9A63C) : scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '$category Loan',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface.withValues(alpha: 0.7),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onDelete != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: onDelete,
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.delete_outline_rounded, 
                                    size: 20, 
                                    color: const Color(0xFFD9534F).withValues(alpha: 0.8),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        LoanStatusChip(status: loan['status'] as String? ?? 'draft'),
                      ],
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                Text(
                  name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      'UGX ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        amountString,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                
                if (loan['purpose'] != null && loan['purpose'].toString().isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),
                  Row(
                    children: [
                      Icon(Icons.edit_note_rounded, size: 16, color: scheme.onSurface.withValues(alpha: 0.4)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          loan['purpose'],
                          style: TextStyle(
                            fontSize: 14,
                            color: scheme.onSurface.withValues(alpha: 0.6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}