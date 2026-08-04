// lib/features/loans/presentation/loans_dashboard_screen.dart

import 'package:aeclms/core/widgets/custom_loader.dart';
import 'package:flutter/material.dart';

import '../../auth/data/auth_service.dart';
import '../../notifications/data/notifications_repository.dart';
import '../../notifications/presentation/notifications_screen.dart';
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
    required this.notificationsRepository,
  });

  final LoanRepository repository;
  final Profile profile;
  final AuthService authService;
  final NotificationsRepository notificationsRepository;

  @override
  State<LoansDashboardScreen> createState() => _LoansDashboardScreenState();
}

class _LoansDashboardScreenState extends State<LoansDashboardScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _mine = [];
  List<Map<String, dynamic>> _awaitingAction = [];
  List<Map<String, dynamic>> _history = [];
  int _unreadCount = 0;

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
      widget.notificationsRepository.fetchUnreadCount(),
    ]);
    final loans = results[0] as List<Map<String, dynamic>>;
    final myStages = results[1] as Set<String>;
    final unread = results[2] as int;

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
      _unreadCount = unread;
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
        title: const Text(
          'AEC Dashboard',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => NotificationsScreen(
                    repository: widget.notificationsRepository,
                    loanRepository: widget.repository,
                    profile: widget.profile,
                  ),
                ),
              );
              _load();
            },
            icon: Badge(
              label: Text('$_unreadCount'),
              isLabelVisible: _unreadCount > 0,
              backgroundColor: const Color(0xFFD9534F),
              child: const Icon(Icons.notifications_rounded),
            ),
            tooltip: 'Notifications',
          ),
          IconButton(
            onPressed: () => widget.authService.signOut(),
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Log out',
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_rounded, size: 24),
        label: const Text('Apply Now', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        elevation: 4,
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
          ? Center(child: CustomLoader(size: 56, color: scheme.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: scheme.primary,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 120), // Padding for FAB
                children: [
                  _StaggeredFadeIn(
                    index: 0,
                    child: _DashboardHero(profile: widget.profile),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_awaitingAction.isNotEmpty) ...[
                          _StaggeredFadeIn(
                            index: 1,
                            child: _SectionLabel('Awaiting Your Action', color: scheme.primary, icon: Icons.assignment_late_rounded),
                          ),
                          ..._awaitingAction.asMap().entries.map((entry) {
                            return _StaggeredFadeIn(
                              index: 2 + entry.key,
                              child: _LoanCard(
                                loan: entry.value,
                                onTap: () => _openLoan(entry.value),
                                isActionRequired: true,
                              ),
                            );
                          }),
                          const SizedBox(height: 24),
                        ],
                        
                        _StaggeredFadeIn(
                          index: _awaitingAction.isNotEmpty ? 3 + _awaitingAction.length : 1,
                          child: const _SectionLabel('My Applications', icon: Icons.folder_shared_rounded),
                        ),
                        
                        if (_mine.isEmpty)
                          _StaggeredFadeIn(
                            index: _awaitingAction.isNotEmpty ? 4 + _awaitingAction.length : 2,
                            child: const _EmptyState(
                              message: 'No applications yet.',
                              subMessage: 'Tap the button below to start your first loan application.',
                              icon: Icons.account_balance_wallet_rounded,
                            ),
                          )
                        else
                          ..._mine.asMap().entries.map((entry) {
                            return _StaggeredFadeIn(
                              index: (_awaitingAction.isNotEmpty ? 4 + _awaitingAction.length : 2) + entry.key,
                              child: _LoanCard(
                                loan: entry.value,
                                onTap: () => _openLoan(entry.value),
                              ),
                            );
                          }),
                          
                        const SizedBox(height: 24),
                        
                        if (_history.isNotEmpty) ...[
                          _StaggeredFadeIn(
                            index: 10, // Arbitrary high index to ensure it trails the rest
                            child: const _SectionLabel('Community History', icon: Icons.history_rounded),
                          ),
                          ..._history.map((l) => _StaggeredFadeIn(
                                index: 11,
                                child: _LoanCard(
                                  loan: l,
                                  onTap: () => _openLoan(l),
                                  isHistory: true,
                                ),
                              )),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _DashboardHero extends StatelessWidget {
  final Profile profile;
  const _DashboardHero({required this.profile});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: 0.15),
            scheme.primary.withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: scheme.primary.withValues(alpha: 0.2),
            child: Text(
              profile.fullName.isNotEmpty ? profile.fullName[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back,',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.6),
                        letterSpacing: 0.5,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  profile.fullName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.color, required this.icon});
  final String text;
  final Color? color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, size: 22, color: color ?? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
          const SizedBox(width: 12),
          Text(
            text,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: color ?? Theme.of(context).colorScheme.onSurface,
                ),
          ),
        ],
      ),
    );
  }
}

class _LoanCard extends StatelessWidget {
  const _LoanCard({
    required this.loan, 
    required this.onTap, 
    this.isActionRequired = false,
    this.isHistory = false,
  });
  
  final Map<String, dynamic> loan;
  final VoidCallback onTap;
  final bool isActionRequired;
  final bool isHistory;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amountRaw = loan['amount_requested'] as num?;
    
    // Format amount with commas (e.g. 50,000.00)
    final amountString = amountRaw != null 
        ? amountRaw.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},') 
        : '-';
        
    final name = loan['full_name'] as String? ?? 'Applicant';
    final isEmergency = loan['loan_category'] == 'emergency';
    final category = isEmergency ? 'Emergency' : 'Normal';
    
    // Visual styling based on priority
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
                // Top Row: Icon, Category & Status
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
                    LoanStatusChip(status: loan['status'] as String? ?? 'draft'),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // Middle Row: Amount & Name
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      'UGX ', // Adjust currency symbol to your preference
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
                
                // Bottom Row: Purpose (if exists)
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, required this.subMessage, required this.icon});
  
  final String message;
  final String subMessage;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 20),
          Text(
            message,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            subMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14, 
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              height: 1.5,
            ),
          ),
        ],
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

    Future.delayed(Duration(milliseconds: 75 * widget.index), () {
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