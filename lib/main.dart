// lib/main.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_service.dart';
import 'features/auth/presentation/auth_gate.dart';
import 'features/loans/data/loan_repository.dart';
import 'features/notifications/data/notifications_repository.dart';

const supabaseUrl = 'https://wtoalqqzuareemmipwla.supabase.co';
const supabaseAnonKey = 'sb_publishable_LA8rj6lPsxII6dlvzDnaZA_KtsBshYx';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const LoanManagementApp());
}

/// Convenience accessors
final supabase = Supabase.instance.client;
final authService = AuthService(supabase);
final loanRepository = LoanRepository(supabase);
final notificationsRepository = NotificationsRepository(supabase);

/// GLOBAL THEME STATE: Listens for light/dark mode toggles app-wide
final ValueNotifier<ThemeMode> appThemeNotifier = ValueNotifier(ThemeMode.system);

class LoanManagementApp extends StatelessWidget {
  const LoanManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ValueListenableBuilder rebuilds the app whenever appThemeNotifier changes
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          title: 'Loan Management System',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: currentMode, // Dynamically driven by the notifier
          home: AuthGate(
            authService: authService,
            loanRepository: loanRepository,
            notificationsRepository: notificationsRepository,
          ),
        );
      },
    );
  }
}