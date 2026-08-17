// lib/features/loans/presentation/loans_dashboard_screen.dart

import 'package:aeclms/core/widgets/custom_loader.dart';
import 'package:aeclms/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:flutter/material.dart';
import '../../auth/data/auth_service.dart';
import '../../notifications/data/notifications_repository.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../profile/presentation/settings_screen.dart';
import '../data/loan_repository.dart';
import 'application_form_screen.dart';
import 'loan_list_screen.dart';

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
  
  bool get _isAdmin {
    // TODO: Connect this to your actual user_roles check if necessary.
    return true; 
  }

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

  // --- NAVIGATION HELPERS ---

  Future<void> _startNewApplication() async {
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
  }

  Future<void> _navigateToListScreen({
    required String title,
    required List<Map<String, dynamic>> loans,
    bool isActionRequired = false,
    bool isHistory = false,
  }) async {
    final shouldRefresh = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LoanListScreen(
          title: title,
          loans: loans,
          repository: widget.repository,
          profile: widget.profile,
          isActionRequired: isActionRequired,
          isHistory: isHistory,
        ),
      ),
    );
    
    if (shouldRefresh == true) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      drawer: _DashboardDrawer(
        profile: widget.profile,
        authService: widget.authService,
        isAdmin: _isAdmin,
      ),
      appBar: AppBar(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        title: const Text(
          'Dashboard',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5),
        ),
        centerTitle: true,
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
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? Center(child: CustomLoader(size: 56, color: scheme.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: scheme.primary,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 40), 
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
                        _StaggeredFadeIn(
                          index: 1,
                          child: Text('Overview', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                        ),
                        const SizedBox(height: 16),
                        
                        // The New Grid Layout
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1.1,
                          children: [
                            _StaggeredFadeIn(
                              index: 2,
                              child: _DashboardBox(
                                title: 'Apply Now',
                                subtitle: 'New Loan Request',
                                icon: Icons.add_circle_outline_rounded,
                                color: scheme.primary,
                                isPrimary: true,
                                onTap: _startNewApplication,
                              ),
                            ),
                            _StaggeredFadeIn(
                              index: 3,
                              child: _DashboardBox(
                                title: 'Pending Action',
                                subtitle: '${_awaitingAction.length} Requires Review',
                                icon: Icons.assignment_late_rounded,
                                color: const Color(0xFFE9A63C),
                                badgeCount: _awaitingAction.length,
                                onTap: () => _navigateToListScreen(
                                  title: 'Pending Action', 
                                  loans: _awaitingAction,
                                  isActionRequired: true,
                                ),
                              ),
                            ),
                            _StaggeredFadeIn(
                              index: 4,
                              child: _DashboardBox(
                                title: 'My Loans',
                                subtitle: '${_mine.length} Active / Drafts',
                                icon: Icons.folder_shared_rounded,
                                color: const Color(0xFF4A90E2),
                                onTap: () => _navigateToListScreen(
                                  title: 'My Applications', 
                                  loans: _mine,
                                ),
                              ),
                            ),
                            _StaggeredFadeIn(
                              index: 5,
                              child: _DashboardBox(
                                title: 'History',
                                subtitle: '${_history.length} Past Records',
                                icon: Icons.history_rounded,
                                color: scheme.onSurface.withValues(alpha: 0.6),
                                onTap: () => _navigateToListScreen(
                                  title: 'History', 
                                  loans: _history,
                                  isHistory: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _DashboardBox extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isPrimary;
  final int badgeCount;

  const _DashboardBox({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.isPrimary = false,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bgColor = isPrimary ? color : scheme.surfaceContainerHighest.withValues(alpha: 0.3);
    final fgColor = isPrimary ? scheme.onPrimary : color;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isPrimary ? Colors.transparent : scheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: isPrimary 
            ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))] 
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isPrimary ? Colors.white.withValues(alpha: 0.2) : color.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: isPrimary ? Colors.white : fgColor, size: 28),
                    ),
                    const Spacer(),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: isPrimary ? Colors.white : scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isPrimary ? Colors.white.withValues(alpha: 0.8) : scheme.onSurface.withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (badgeCount > 0)
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFD9534F),
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    child: Text(
                      '$badgeCount',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// The Drawer and Hero components remain exactly the same as your previous code
// -----------------------------------------------------------------------------

class _DashboardDrawer extends StatelessWidget {
  final Profile profile;
  final AuthService authService;
  final bool isAdmin;

  const _DashboardDrawer({required this.profile, required this.authService, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final email = authService.currentUser?.email ?? 'Unknown Email';

    return Drawer(
      backgroundColor: scheme.surface,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 24, 24, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary.withValues(alpha: 0.15), scheme.primary.withValues(alpha: 0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border(bottom: BorderSide(color: scheme.primary.withValues(alpha: 0.1))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.primary.withValues(alpha: 0.3), width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: scheme.primary.withValues(alpha: 0.2),
                    child: Text(
                      profile.fullName.isNotEmpty ? profile.fullName[0].toUpperCase() : '?',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: scheme.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  profile.fullName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: TextStyle(fontSize: 14, color: scheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                if (isAdmin) ...[
                  const Padding(padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16), child: Divider(height: 1)),
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 8, top: 8),
                    child: Text(
                      'ADMINISTRATION',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: scheme.primary.withValues(alpha: 0.8)),
                    ),
                  ),
                  _DrawerItem(
                    icon: Icons.admin_panel_settings_rounded,
                    title: 'Admin Hub',
                    isSelected: false,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => AdminDashboardScreen(profile: profile)));
                    },
                  ),
                ],
                _DrawerItem(icon: Icons.dashboard_rounded, title: 'Dashboard', isSelected: true, onTap: () => Navigator.pop(context)),
                _DrawerItem(
                  icon: Icons.settings_rounded,
                  title: 'Settings',
                  isSelected: false,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(profile: profile, authService: authService)));
                  },
                ),
                const Padding(padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16), child: Divider(height: 1)),
                _DrawerItem(icon: Icons.help_outline_rounded, title: 'Help & Support', isSelected: false, onTap: () => Navigator.pop(context)),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).padding.bottom + 24),
            child: InkWell(
              onTap: () => _confirmSignOut(context),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFD9534F).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFD9534F).withValues(alpha: 0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.logout_rounded, color: Color(0xFFD9534F), size: 22),
                    SizedBox(width: 16),
                    Text('Log Out', style: TextStyle(color: Color(0xFFD9534F), fontWeight: FontWeight.w700, fontSize: 16)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final scheme = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Log Out?', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to log out of your account?'),
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
            child: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirm == true) authService.signOut();
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _DrawerItem({required this.icon, required this.title, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? scheme.primary.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, color: isSelected ? scheme.primary : scheme.onSurface.withValues(alpha: 0.6), size: 24),
              const SizedBox(width: 16),
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? scheme.primary : scheme.onSurface.withValues(alpha: 0.8),
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
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
          colors: [scheme.primary.withValues(alpha: 0.15), scheme.primary.withValues(alpha: 0.02)],
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
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: scheme.primary),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back,',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.onSurface.withValues(alpha: 0.6), letterSpacing: 0.5),
                ),
                const SizedBox(height: 4),
                Text(
                  profile.fullName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
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
    return FadeTransition(opacity: _fadeAnimation, child: SlideTransition(position: _slideAnimation, child: widget.child));
  }
}