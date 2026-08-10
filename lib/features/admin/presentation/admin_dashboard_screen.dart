// lib/features/admin/presentation/admin_dashboard_screen.dart

import 'package:aeclms/features/admin/presentation/admin_all_loans_screen.dart';
import 'package:aeclms/features/admin/presentation/report_generation_screen.dart';
import 'package:aeclms/features/admin/presentation/user_management_screen.dart';
import 'package:aeclms/main.dart';
import 'package:flutter/material.dart';
import '../../auth/data/auth_service.dart';

class AdminDashboardScreen extends StatelessWidget {
  final Profile profile;

  const AdminDashboardScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Hub', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5)),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.primary.withValues(alpha: 0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: scheme.primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: scheme.onPrimary.withValues(alpha: 0.2), shape: BoxShape.circle),
                  child: Icon(Icons.shield_rounded, size: 32, color: scheme.onPrimary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Chairperson Access', style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.8), fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Text('System Command', style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -0.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          Text('Core Modules', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 16),

          // Action Cards
          Row(
            children: [
              Expanded(
                child: _AdminActionCard(
                  icon: Icons.manage_accounts_rounded,
                  title: 'User Roles',
                  subtitle: 'Assign & manage',
                  color: const Color(0xFF4A90E2),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const UserManagementScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _AdminActionCard(
                  icon: Icons.account_balance_rounded,
                  title: 'All Loans',
                  subtitle: 'System overview',
                  color: const Color(0xFF58B982),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AdminAllLoansScreen(
                          profile: profile,
                          repository: loanRepository,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // PDF Reports Section (Full Width)
          _AdminActionCard(
            icon: Icons.picture_as_pdf_rounded,
            title: 'Generate Reports',
            subtitle: 'Schedules, Amortizations, & Analytics',
            color: const Color(0xFFD9534F),
            isFullWidth: true,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReportGenerationScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AdminActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool isFullWidth;

  const _AdminActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.isFullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: isFullWidth 
              ? Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
                      child: Icon(icon, size: 32, color: color),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                          const SizedBox(height: 4),
                          Text(subtitle, style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 14)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: scheme.onSurface.withValues(alpha: 0.3)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, size: 28, color: color),
                    ),
                    const SizedBox(height: 16),
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
                  ],
                ),
          ),
        ),
      ),
    );
  }
}