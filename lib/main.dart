// lib/main.dart
//
// Starter entry point. Fill in your Supabase URL + anon key below
// (Project Settings -> API in the Supabase dashboard).
// Once auth + routing screens exist, swap `home:` for go_router.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_service.dart';
import 'features/auth/presentation/auth_gate.dart';
import 'features/loans/data/loan_repository.dart';

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

/// Convenience accessor used throughout the app, e.g.:
/// final loans = await supabase.from('loans').select();
final supabase = Supabase.instance.client;
final authService = AuthService(supabase);
final loanRepository = LoanRepository(supabase);

class LoanManagementApp extends StatelessWidget {
  const LoanManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Loan Management System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: AuthGate(authService: authService, loanRepository: loanRepository),
    );
  }
}
