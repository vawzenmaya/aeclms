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
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hourglass_top_rounded, size: 56, color: scheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Almost there',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  "Your account is created, but you haven't been added to a "
                  "community yet. Ask an administrator to finish setting up "
                  "your account, then come back and log in again.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () => authService.signOut(),
                  child: const Text('Log out'),
                ),
              ],
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
      appBar: AppBar(
        title: const Text('Loan Management System'),
        actions: [
          IconButton(
            onPressed: () => authService.signOut(),
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Log out',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.savings_rounded, size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              'Welcome, ${profile.fullName}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Logged in and ready.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.add_rounded),
              label: const Text('Apply for a loan'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ApplicationFormScreen(
                    repository: loanRepository,
                    profile: profile,
                    currentUserEmail: authService.currentUser?.email,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
