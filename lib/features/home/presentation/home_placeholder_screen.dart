// lib/features/home/presentation/home_placeholder_screen.dart

import 'package:flutter/material.dart';

import '../../auth/data/auth_service.dart';
import '../../loans/data/loan_repository.dart';
import '../../loans/presentation/application_form_screen.dart';

/// Shown once a profile exists but no admin has assigned a community yet.
class PendingAssignmentScreen extends StatelessWidget {
  const PendingAssignmentScreen({super.key, required this.authService});
  
  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: scheme.surface,
      // RESPONSIVE FIX: Center and constrain the view for desktop monitors
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  
                  // Animated Hero Graphic
                  _StaggeredFadeIn(
                    index: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.primary.withValues(alpha: 0.2), width: 2),
                        ),
                        child: Icon(
                          Icons.admin_panel_settings_rounded, 
                          size: 80, 
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Title
                  _StaggeredFadeIn(
                    index: 1,
                    child: Text(
                      'Almost There',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: scheme.onSurface,
                          ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Subtitle
                  _StaggeredFadeIn(
                    index: 2,
                    child: Text(
                      "Your account is created, but you haven't been added to a community yet. "
                      "Ask an administrator to finish setting up your account, then come back and log in again.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: scheme.onSurface.withValues(alpha: 0.6),
                        height: 1.5,
                      ),
                    ),
                  ),
                  
                  const Spacer(),
                  
                  // Log out Button
                  _StaggeredFadeIn(
                    index: 3,
                    child: OutlinedButton.icon(
                      onPressed: () => authService.signOut(),
                      icon: const Icon(Icons.logout_rounded, size: 20),
                      label: const Text('Log out', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Temporary landing screen after a fully-set-up login.
/// Will be replaced by the real dashboard (My Loans / Approvals / etc).
class HomePlaceholderScreen extends StatelessWidget {
  const HomePlaceholderScreen({
    super.key,
    required this.authService,
    required this.profile,
    required this.loanRepository,
  });
  
  final AuthService authService;
  final Profile profile;
  final LoanRepository loanRepository;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        backgroundColor: scheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        title: const Text('AEC Portal', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5)),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => authService.signOut(),
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Log out',
          ),
          const SizedBox(width: 8),
        ],
      ),
      // RESPONSIVE FIX: Center and constrain the view for desktop monitors
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  
                  // Hero Icon
                  _StaggeredFadeIn(
                    index: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.savings_rounded, size: 64, color: scheme.primary),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Welcome Text
                  _StaggeredFadeIn(
                    index: 1,
                    child: Text(
                      'Welcome,\n${profile.fullName}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                            height: 1.2,
                            color: scheme.onSurface,
                          ),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  _StaggeredFadeIn(
                    index: 2,
                    child: Text(
                      'Logged in and ready to go.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  
                  const Spacer(),
                  
                  // Primary Action
                  _StaggeredFadeIn(
                    index: 3,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ApplicationFormScreen(
                            repository: loanRepository,
                            profile: profile,
                            currentUserEmail: authService.currentUser?.email,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 22),
                      label: const Text('Apply for a Loan', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                ],
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

    Future.delayed(Duration(milliseconds: 100 * widget.index), () {
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