// lib/features/loans/presentation/loans_dashboard_screen.dart

import 'package:flutter/material.dart';

import '../../auth/data/auth_service.dart';
import '../data/loan_repository.dart';
import 'application_form_screen.dart';
import 'loan_detail_screen.dart';
import 'widgets/loan_status_chip.dart';

class LoansDashboardScreen extends StatefulWidget {
  const LoansDashboardScreen({
    super.key,
    required this.repository,
    required this.profile,
    required this.authService,
  });

  final LoanRepository repository;
  final Profile profile;
  final AuthService authService;

  @override
  State<LoansDashboardScreen> createState() => _LoansDashboardScreenState();
}

class _LoansDashboardScreenState extends State<LoansDashboardScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _mine = [];
  List<Map<String, dynamic>> _awaitingAction = [];
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final results = await Future.wait([
      widget.repository.fetchVisibleLoans(),
      widget.repository.fetchMyStageAssignments(
        profileId: widget.profile.id,
        communityId: widget.profile.communityId!,
      ),
    ]);
    final loans = results[0] as List<Map<String, dynamic>>;
    final myStages = results[1] as Set<String>;

    final mine = <Map<String, dynamic>>[];
    final awaiting = <Map<String, dynamic>>[];
    final history = <Map<String, dynamic>>[];

    for (final loan in loans) {
      final isApplicant = loan['applicant_id'] == widget.profile.id;
      final isPendingGuarantor =
          loan['guarantor_id'] == widget.profile.id && loan['guarantor_response'] == 'pending';
      final stageKey = '${loan['template_id']}:${loan['current_stage_order']}';
      final isMyApprovalTurn = loan['status'] == 'in_review' && myStages.contains(stageKey);

      if (isPendingGuarantor || isMyApprovalTurn) {
        awaiting.add(loan);
      } else if (isApplicant) {
        mine.add(loan);
      } else {
        history.add(loan);
      }
    }

    if (!mounted) return;
    setState(() {
      _mine = mine;
      _awaitingAction = awaiting;
      _history = history;
      _loading = false;
    });
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
    _load(); // refresh in case something changed
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loan Management System'),
        actions: [
          IconButton(
            onPressed: () => widget.authService.signOut(),
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Log out',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_rounded),
        label: const Text('Apply'),
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ApplicationFormScreen(
                repository: widget.repository,
                profile: widget.profile,
                currentUserEmail: widget.authService.currentUser?.email,
              ),
            ),
          );
          _load();
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  Text('Hi, ${widget.profile.fullName}',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  if (_awaitingAction.isNotEmpty) ...[
                    _SectionLabel('Awaiting your action', color: scheme.primary),
                    ..._awaitingAction.map((l) => _LoanCard(loan: l, onTap: () => _openLoan(l))),
                    const SizedBox(height: 16),
                  ],
                  _SectionLabel('My applications'),
                  if (_mine.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('No applications yet — tap Apply to get started.',
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ),
                  ..._mine.map((l) => _LoanCard(loan: l, onTap: () => _openLoan(l))),
                  const SizedBox(height: 16),
                  if (_history.isNotEmpty) ...[
                    _SectionLabel('History'),
                    ..._history.map((l) => _LoanCard(loan: l, onTap: () => _openLoan(l))),
                  ],
                ],
              ),
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _LoanCard extends StatelessWidget {
  const _LoanCard({required this.loan, required this.onTap});
  final Map<String, dynamic> loan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final amount = (loan['amount_requested'] as num?)?.toStringAsFixed(2) ?? '-';
    final name = loan['full_name'] as String? ?? 'Applicant';
    final category = loan['loan_category'] == 'emergency' ? 'Emergency' : 'Normal';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        title: Text('$name — $amount'),
        subtitle: Text('$category loan · ${loan['purpose'] ?? ''}'),
        trailing: LoanStatusChip(status: loan['status'] as String? ?? 'draft'),
      ),
    );
  }
}
