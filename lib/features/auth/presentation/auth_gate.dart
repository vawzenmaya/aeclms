// lib/features/auth/presentation/auth_gate.dart

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
              return Scaffold(
                backgroundColor: Theme.of(context).colorScheme.surface,
                body: Center(
                  child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              );
            }

            if (profileSnapshot.hasError) {
              final scheme = Theme.of(context).colorScheme;
              final errorStr = profileSnapshot.error.toString().toLowerCase();
              
              // Detect if the error is a network/offline issue
              final isOffline = errorStr.contains('socketexception') || 
                                errorStr.contains('failed host lookup') || 
                                errorStr.contains('network');

              return Scaffold(
                backgroundColor: scheme.surface,
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD9534F).withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isOffline ? Icons.wifi_off_rounded : Icons.error_outline_rounded, 
                              size: 56, 
                              color: const Color(0xFFD9534F),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            isOffline ? 'No Internet Connection' : 'Profile Load Failed',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            isOffline 
                                ? 'It looks like you are offline. Please check your network connection and try again.'
                                : 'An unexpected error occurred while loading your profile data.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              color: scheme.onSurface.withValues(alpha: 0.7),
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 32),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => widget.authService.signOut(),
                                  icon: const Icon(Icons.logout_rounded),
                                  label: const Text('Log out'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: FilledButton.icon(
                                  // Calling setState rebuilds the AuthGate, which re-triggers the FutureBuilder
                                  onPressed: () => setState(() {}),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Retry'),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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