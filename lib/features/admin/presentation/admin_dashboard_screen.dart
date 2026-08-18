// lib/features/admin/presentation/admin_dashboard_screen.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/custom_loader.dart';
import '../../auth/data/auth_service.dart';
import 'admin_all_loans_screen.dart';
import 'report_generation_screen.dart';
import 'user_management_screen.dart';
import '../../loans/data/loan_repository.dart';
import '../../../main.dart'; // To access global loanRepository if needed

class AdminDashboardScreen extends StatefulWidget {
  final Profile profile;

  const AdminDashboardScreen({super.key, required this.profile});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _loading = true;
  String? _error;

  // Aggregate Metrics
  double _totalProcessingFees = 0;
  double _totalDisbursed = 0;
  int _totalLoans = 0;
  int _pendingLoans = 0;

  // Chart Data
  Map<String, int> _statusCounts = {};
  List<Map<String, dynamic>> _monthlyTrends = [];

  final currency = NumberFormat("#,##0", "en_US");

  @override
  void initState() {
    super.initState();
    _fetchDashboardMetrics();
  }

  Future<void> _fetchDashboardMetrics() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await Supabase.instance.client
          .from('loans')
          .select('status, amount_requested, created_at')
          .neq('status', 'draft'); // Exclude drafts from admin stats

      final loans = List<Map<String, dynamic>>.from(response);

      double fees = 0.0;
      double disbursed = 0.0;
      int pending = 0;
      
      Map<String, int> statuses = {
        'Running': 0,
        'Cleared': 0,
        'Pending': 0,
        'Rejected': 0,
      };

      // For the bar chart: Group by YYYY-MM
      Map<String, double> monthlySums = {};

      for (var loan in loans) {
        final status = (loan['status'] as String? ?? '').toLowerCase();
        final amount = (loan['amount_requested'] as num?)?.toDouble() ?? 0.0;
        final date = DateTime.parse(loan['created_at']);
        final monthKey = DateFormat('MMM yy').format(date);

        // Group Statuses
        if (['approved', 'active', 'disbursed', 'completed'].contains(status)) {
          statuses['Running'] = (statuses['Running'] ?? 0) + 1;
          fees += (amount * 0.005); // Calculate 0.5% Processing Fee
          disbursed += amount;
          monthlySums[monthKey] = (monthlySums[monthKey] ?? 0.0) + amount;
        } else if (status == 'cleared') {
          statuses['Cleared'] = (statuses['Cleared'] ?? 0) + 1;
          fees += (amount * 0.005);
          disbursed += amount;
          monthlySums[monthKey] = (monthlySums[monthKey] ?? 0.0) + amount;
        } else if (['in_review', 'awaiting_guarantor'].contains(status)) {
          statuses['Pending'] = (statuses['Pending'] ?? 0) + 1;
          pending += 1;
        } else if (status == 'rejected') {
          statuses['Rejected'] = (statuses['Rejected'] ?? 0) + 1;
        }
      }

      // Format last 6 months for the Bar Chart
      List<Map<String, dynamic>> trends = [];
      DateTime now = DateTime.now();
      for (int i = 5; i >= 0; i--) {
        DateTime pastMonth = DateTime(now.year, now.month - i, 1);
        String key = DateFormat('MMM yy').format(pastMonth);
        trends.add({
          'month': DateFormat('MMM').format(pastMonth),
          'value': monthlySums[key] ?? 0.0,
        });
      }

      if (mounted) {
        setState(() {
          _totalLoans = loans.length;
          _totalProcessingFees = fees;
          _totalDisbursed = disbursed;
          _pendingLoans = pending;
          _statusCounts = statuses;
          _monthlyTrends = trends;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load metrics: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        backgroundColor: scheme.surface,
        title: const Text('Admin Hub', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5)),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchDashboardMetrics,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CustomLoader(size: 56, color: scheme.primary))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.red))))
              : RefreshIndicator(
                  onRefresh: _fetchDashboardMetrics,
                  color: scheme.primary,
                  backgroundColor: scheme.surface,
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      // 1. HERO BANNER
                      _StaggeredFadeIn(
                        index: 0,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [scheme.primary, scheme.primary.withValues(alpha: 0.8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
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
                                    Text('Executive Access', style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.8), fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: 0.5)),
                                    const SizedBox(height: 4),
                                    Text('System Overview', style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -0.5)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 2. FINANCIAL METRICS GRID
                      _StaggeredFadeIn(
                        index: 1,
                        child: Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                title: 'Total Fees Earned',
                                value: 'UGX ${currency.format(_totalProcessingFees)}',
                                subtitle: 'From processing fees',
                                icon: Icons.account_balance_wallet_rounded,
                                color: const Color(0xFF58B982),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _StatCard(
                                title: 'Active Portfolio',
                                value: 'UGX ${currency.format(_totalDisbursed)}',
                                subtitle: 'Total disbursed funds',
                                icon: Icons.trending_up_rounded,
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 3. NATIVE PIE CHART: LOAN STATUS DISTRIBUTION
                      _StaggeredFadeIn(
                        index: 2,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Loan Status Distribution', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: scheme.onSurface)),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  SizedBox(
                                    height: 120,
                                    width: 120,
                                    child: CustomPaint(
                                      painter: _DonutChartPainter(
                                        data: _statusCounts,
                                        colors: {
                                          'Running': scheme.primary,
                                          'Cleared': const Color(0xFF58B982),
                                          'Pending': const Color(0xFFE9A63C),
                                          'Rejected': const Color(0xFFD9534F),
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 32),
                                  Expanded(
                                    child: Column(
                                      children: _statusCounts.entries.map((e) {
                                        if (e.value == 0) return const SizedBox.shrink();
                                        Color c = e.key == 'Running' ? scheme.primary : 
                                                  e.key == 'Cleared' ? const Color(0xFF58B982) : 
                                                  e.key == 'Pending' ? const Color(0xFFE9A63C) : const Color(0xFFD9534F);
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 8),
                                          child: Row(
                                            children: [
                                              Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                                              const SizedBox(width: 8),
                                              Expanded(child: Text(e.key, style: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.7)))),
                                              Text(e.value.toString(), style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface)),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 4. NATIVE BAR CHART: DISBURSEMENT TRENDS
                      _StaggeredFadeIn(
                        index: 3,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Disbursements (Last 6 Months)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: scheme.onSurface)),
                              const SizedBox(height: 24),
                              SizedBox(
                                height: 150,
                                child: _NativeBarChart(data: _monthlyTrends, primaryColor: scheme.primary),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      Text('Admin Modules', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                      const SizedBox(height: 16),

                      // 5. NAVIGATION MODULES
                      _StaggeredFadeIn(
                        index: 4,
                        child: Row(
                          children: [
                            Expanded(
                              child: _AdminModuleCard(
                                icon: Icons.manage_accounts_rounded, title: 'User Roles',
                                color: const Color(0xFF4A90E2),
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UserManagementScreen())),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _AdminModuleCard(
                                icon: Icons.account_balance_rounded, title: 'All Loans',
                                badgeCount: _pendingLoans, color: const Color(0xFFE9A63C),
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminAllLoansScreen(profile: widget.profile, repository: loanRepository))),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _StaggeredFadeIn(
                        index: 5,
                        child: _AdminModuleCard(
                          icon: Icons.picture_as_pdf_rounded, title: 'Generate PDF Reports',
                          color: const Color(0xFFD9534F), isFullWidth: true,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReportGenerationScreen())),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
    );
  }
}

// -------------------------------------------------------------
// STYLISH UI COMPONENTS & NATIVE CHARTS
// -------------------------------------------------------------

class _StatCard extends StatelessWidget {
  final String title; final String value; final String subtitle; final IconData icon; final Color color;
  const _StatCard({required this.title, required this.value, required this.subtitle, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color), const SizedBox(width: 8),
              Expanded(child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface.withValues(alpha: 0.6)), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: scheme.onSurface, letterSpacing: -1))),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.5))),
        ],
      ),
    );
  }
}

class _AdminModuleCard extends StatelessWidget {
  final IconData icon; final String title; final Color color; final VoidCallback onTap; final bool isFullWidth; final int badgeCount;
  const _AdminModuleCard({required this.icon, required this.title, required this.color, required this.onTap, this.isFullWidth = false, this.badgeCount = 0});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: isFullWidth 
              ? Row(
                  children: [
                    Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 24, color: color)),
                    const SizedBox(width: 16),
                    Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                    Icon(Icons.chevron_right_rounded, color: scheme.onSurface.withValues(alpha: 0.3)),
                  ],
                )
              : Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 24, color: color)),
                        const SizedBox(height: 16),
                        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      ],
                    ),
                    if (badgeCount > 0)
                      Positioned(
                        top: 0, right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: const BoxDecoration(color: Color(0xFFD9534F), borderRadius: BorderRadius.all(Radius.circular(10))),
                          child: Text('$badgeCount', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                      ),
                  ],
                ),
          ),
        ),
      ),
    );
  }
}

/// A highly optimized native Bar Chart built without external dependencies.
class _NativeBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final Color primaryColor;
  
  const _NativeBarChart({required this.data, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    final double maxVal = data.map((e) => e['value'] as double).reduce(max);
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: data.map((d) {
        final val = d['value'] as double;
        final heightFactor = maxVal == 0 ? 0.0 : val / maxVal;
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: heightFactor),
                  duration: const Duration(milliseconds: 1000),
                  curve: Curves.easeOutCubic,
                  builder: (context, factor, child) {
                    return FractionallySizedBox(
                      heightFactor: factor > 0 ? factor : 0.01,
                      child: Container(
                        width: 28,
                        decoration: BoxDecoration(
                          color: val > 0 ? primaryColor : primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    );
                  }
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(d['month'], style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
          ],
        );
      }).toList(),
    );
  }
}

/// A high-performance CustomPainter that draws a beautiful Donut/Pie Chart natively.
class _DonutChartPainter extends CustomPainter {
  final Map<String, int> data;
  final Map<String, Color> colors;

  _DonutChartPainter({required this.data, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    double total = data.values.fold(0, (sum, val) => sum + val).toDouble();
    if (total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2) - 10;
    
    double startRadian = -pi / 2; // Start at the top

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;

    for (var entry in data.entries) {
      if (entry.value == 0) continue;
      
      final sweepRadian = (entry.value / total) * 2 * pi;
      paint.color = colors[entry.key]!;
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startRadian,
        sweepRadian - 0.1, // Slight gap between segments
        false,
        paint,
      );
      
      startRadian += sweepRadian;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _StaggeredFadeIn extends StatefulWidget {
  final Widget child; final int index;
  const _StaggeredFadeIn({required this.child, required this.index});
  @override
  State<_StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<_StaggeredFadeIn> with SingleTickerProviderStateMixin {
  late AnimationController _controller; late Animation<double> _fadeAnimation; late Animation<Offset> _slideAnimation;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    Future.delayed(Duration(milliseconds: 75 * widget.index), () { if (mounted) _controller.forward(); });
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _fadeAnimation, child: SlideTransition(position: _slideAnimation, child: widget.child));
}