// lib/features/auth/presentation/auth_gate.dart
//
// Listens to the Supabase auth session and decides what to show:
//  - no session            -> LoginScreen
//  - session, no community -> PendingAssignmentScreen (needs admin setup)
//  - session, has community -> HomePlaceholderScreen (real dashboard comes later)

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_service.dart';
import '../../home/presentation/home_placeholder_screen.dart';
import '../../loans/data/loan_repository.dart';
import '../../loans/presentation/loans_dashboard_screen.dart';
import '../../notifications/data/notifications_repository.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.authService,
    required this.loanRepository,
    required this.notificationsRepository,
  });
  final AuthService authService;
  final LoanRepository loanRepository;
  final NotificationsRepository notificationsRepository;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: widget.authService.onAuthStateChange,
      builder: (context, snapshot) {
        final session = widget.authService.currentUser;

        if (session == null) {
          return LoginScreen(authService: widget.authService);
        }

        // Logged in -> fetch their profile to decide pending vs. home.
        return FutureBuilder<Profile?>(
          future: widget.authService.fetchCurrentProfile(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            if (profileSnapshot.hasError) {
              // Surface the real error instead of silently showing "pending".
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        const Text('Could not load your profile:'),
                        const SizedBox(height: 8),
                        Text('${profileSnapshot.error}', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () => widget.authService.signOut(),
                          child: const Text('Log out'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final profile = profileSnapshot.data;
            if (profile == null || profile.communityId == null) {
              return PendingAssignmentScreen(authService: widget.authService);
            }

            return LoansDashboardScreen(
              repository: widget.loanRepository,
              profile: profile,
              authService: widget.authService,
              notificationsRepository: widget.notificationsRepository,
            );
          },
        );
      },
    );
  }
}
