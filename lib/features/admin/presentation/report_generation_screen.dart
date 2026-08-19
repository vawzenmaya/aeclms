// lib/features/admin/presentation/report_generation_screen.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/widgets/custom_loader.dart';
import '../services/pdf_report_service.dart';

class ReportGenerationScreen extends StatefulWidget {
  const ReportGenerationScreen({super.key});

  @override
  State<ReportGenerationScreen> createState() => _ReportGenerationScreenState();
}

class _ReportGenerationScreenState extends State<ReportGenerationScreen> {
  // Master Schedule & Analytics State
  String _selectedStatus = 'All';
  final String _selectedMonth = DateFormat('MMMM yyyy').format(DateTime.now());
  bool _isGeneratingMaster = false;
  bool _isExportingExcel = false;
  final List<String> _statusOptions = ['All', 'Running', 'Cleared'];

  // Date Range Filtering
  DateTime? _startDate;
  DateTime? _endDate;

  // Individual Amortization State
  bool _isLoadingLoans = true;
  bool _isGeneratingAmortization = false;
  List<Map<String, dynamic>> _activeLoans = [];
  String? _selectedLoanId;

  @override
  void initState() {
    super.initState();
    _fetchActiveLoans();
  }

  Future<void> _fetchActiveLoans() async {
    try {
      final response = await Supabase.instance.client
          .from('loans')
          .select('id, amount_requested, status, profiles!loans_applicant_id_fkey(full_name)')
          .neq('status', 'draft')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _activeLoans = List<Map<String, dynamic>>.from(response);
          _isLoadingLoans = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load loans: $e')));
        setState(() => _isLoadingLoans = false);
      }
    }
  }

  // Helper to pick date ranges
  Future<void> _selectDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  // Core processing method for fetching and filtering loan metrics and records
  Future<Map<String, dynamic>> _fetchFilteredReportData() async {
    final response = await Supabase.instance.client
        .from('loans')
        .select('*, profiles!loans_applicant_id_fkey(full_name), repayments(amount, created_at), loan_amortization_schedule(interest, due_date)')
        .neq('status', 'draft')
        .order('created_at', ascending: false);

    final rawLoans = List<Map<String, dynamic>>.from(response);
    final List<Map<String, dynamic>> formattedData = [];
    
    double totalInterestEarned = 0.0;
    double totalProcessingFeesEarned = 0.0;

    for (var loan in rawLoans) {
      final createdAtStr = loan['created_at'];
      if (createdAtStr == null) continue;
      final createdAt = DateTime.parse(createdAtStr);

      // Apply Date Range Filter if active
      if (_startDate != null && createdAt.isBefore(_startDate!)) continue;
      if (_endDate != null && createdAt.isAfter(_endDate!.add(const Duration(days: 1)))) continue;

      final dbStatus = (loan['status'] as String? ?? '').toLowerCase();
      
      String reportStatus = 'Pending';
      if (['approved', 'active', 'disbursed', 'completed'].contains(dbStatus)) {
        reportStatus = 'Running';
      } else if (dbStatus == 'cleared') {
        reportStatus = 'Cleared';
      } else if (dbStatus == 'rejected') {
        reportStatus = 'Rejected';
      }
      
      if (_selectedStatus == 'Running' && reportStatus != 'Running') continue;
      if (_selectedStatus == 'Cleared' && reportStatus != 'Cleared') continue;

      final amount = (loan['amount_requested'] as num?)?.toDouble() ?? 0.0;
      final emi = (loan['installment_amount'] as num?)?.toDouble() ?? 0.0;
      final totalMonths = loan['duration_months'] as int? ?? 0;
      
      // Calculate Processing Fee (0.5% of requested amount)
      totalProcessingFeesEarned += (amount * 0.005);

      // Calculate Interest Earned within selected period from amortization schedule or repayments
      final schedule = (loan['loan_amortization_schedule'] as List?) ?? [];
      for (var sched in schedule) {
        final dueDateStr = sched['due_date'];
        if (dueDateStr != null) {
          final dueDate = DateTime.parse(dueDateStr);
          // If within range (or no range set), accumulate interest
          bool inRange = true;
          if (_startDate != null && dueDate.isBefore(_startDate!)) inRange = false;
          if (_endDate != null && dueDate.isAfter(_endDate!.add(const Duration(days: 1)))) inRange = false;

          if (inRange) {
            totalInterestEarned += (sched['interest'] as num?)?.toDouble() ?? 0.0;
          }
        }
      }

      final repayments = (loan['repayments'] as List?) ?? [];
      final monthsPaid = repayments.length;
      final remainingMonths = max(0, totalMonths - monthsPaid);

      formattedData.add({
        'name': loan['profiles']?['full_name'] ?? 'Unknown Applicant',
        'approved_amount': loan['amount_approved'] ?? amount, 
        'monthly_installment': emi, 
        'total_months': totalMonths,
        'remaining_months': remainingMonths,
        'clearance_month': loan['expected_end_date'] != null 
            ? DateFormat('MMM yyyy').format(DateTime.parse(loan['expected_end_date'])) 
            : '-',
        'status': reportStatus,
      });
    }

    return {
      'loans': formattedData,
      'interestEarned': totalInterestEarned,
      'feesEarned': totalProcessingFeesEarned,
    };
  }

  Future<void> _handleGenerateMasterSchedule() async {
    setState(() => _isGeneratingMaster = true);
    
    try {
      final reportData = await _fetchFilteredReportData();
      final loans = reportData['loans'] as List<Map<String, dynamic>>;

      if (loans.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No loans found for this filter and period.')),
          );
        }
        return;
      }

      await PdfReportService.generateMasterSchedule(
        reportMonth: _selectedMonth,
        loans: loans,
        filterStatus: _selectedStatus,
        startDate: _startDate,
        endDate: _endDate,
        totalInterestEarned: reportData['interestEarned'],
        totalProcessingFeesEarned: reportData['feesEarned'],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate PDF: $e'), backgroundColor: const Color(0xFFD9534F)),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingMaster = false);
    }
  }

  Future<void> _handleExportExcel() async {
    setState(() => _isExportingExcel = true);
    
    try {
      final reportData = await _fetchFilteredReportData();
      final loans = reportData['loans'] as List<Map<String, dynamic>>;

      if (loans.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No data available to export for this period.')),
          );
        }
        return;
      }

      await PdfReportService.exportMasterScheduleToExcel(
        loans: loans,
        totalInterestEarned: reportData['interestEarned'],
        totalProcessingFeesEarned: reportData['feesEarned'],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export Excel: $e'), backgroundColor: const Color(0xFFD9534F)),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingExcel = false);
    }
  }

  Future<void> _handleGenerateAmortization() async {
    if (_selectedLoanId == null) return;
    setState(() => _isGeneratingAmortization = true);

    try {
      final supabase = Supabase.instance.client;
      
      final loanResponse = await supabase
          .from('loans')
          .select('*, profiles!loans_applicant_id_fkey(full_name)')
          .eq('id', _selectedLoanId!)
          .single();

      final applicantName = loanResponse['profiles']?['full_name'] ?? 'Unknown Applicant';
      final loanAmount = (loanResponse['amount_requested'] as num?)?.toDouble() ?? 0.0;
      final netPay = (loanResponse['net_pay'] as num?)?.toDouble() ?? 0.0;
      final periodMonths = loanResponse['duration_months'] as int? ?? 60;
      final interestRate = (loanResponse['interest_rate'] as num?)?.toDouble() ?? 8.0;
      final emi = (loanResponse['installment_amount'] as num?)?.toDouble() ?? 0.0;

      final scheduleResponse = await supabase
          .from('loan_amortization_schedule')
          .select('*')
          .eq('loan_id', _selectedLoanId!)
          .order('period_number', ascending: true);
          
      List<Map<String, dynamic>> scheduleRows = [];
      
      for (var row in scheduleResponse) {
        scheduleRows.add({
          'period': row['period_number'],
          'installment': row['installment'],
          'interest': row['interest'],
          'principal': row['principal'],
          'balance': row['balance'],
        });
      }

      await PdfReportService.generateAmortizationSchedule(
        applicantName: applicantName,
        loanAmount: loanAmount,
        interestRate: interestRate,
        periodMonths: periodMonths,
        monthlyInstallment: emi,
        netPay: netPay,
        scheduleRows: scheduleRows,
      );

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate PDF: $e'), backgroundColor: const Color(0xFFD9534F)));
      }
    } finally {
      if (mounted) setState(() => _isGeneratingAmortization = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currency = NumberFormat("#,##0", "en_US");

    final dateRangeDisplay = (_startDate != null && _endDate != null)
        ? '${DateFormat('MMM dd, yyyy').format(_startDate!)} — ${DateFormat('MMM dd, yyyy').format(_endDate!)}'
        : 'All Time (No Period Filter)';

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        title: Text(
          'Reports Center', 
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5, color: scheme.onSurface),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // ----------------------------------------------------
              // Master Schedule & Financial Analytics Card
              // ----------------------------------------------------
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: const Color(0xFFD9534F).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.table_view_rounded, size: 28, color: Color(0xFFD9534F)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Master Schedule & Financials', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: scheme.onSurface)),
                              const SizedBox(height: 4),
                              Text('Export portfolio reports & view period earnings', style: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.6))),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider(height: 1)),
                    
                    // Period Selection Tile
                    Text('Consideration Period', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _selectDateRange(context),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.date_range_rounded, size: 20, color: scheme.primary),
                                const SizedBox(width: 12),
                                Text(dateRangeDisplay, style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface, fontSize: 14)),
                              ],
                            ),
                            if (_startDate != null)
                              IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () => setState(() { _startDate = null; _endDate = null; }),
                                tooltip: 'Clear Period',
                              )
                            else
                              Icon(Icons.chevron_right_rounded, color: scheme.onSurface.withValues(alpha: 0.4)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Text('Status Filter', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedStatus,
                      dropdownColor: scheme.surface,
                      decoration: InputDecoration(
                        labelText: 'Loan Status',
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      items: _statusOptions.map((s) => DropdownMenuItem(
                        value: s, 
                        child: Text(s, style: TextStyle(color: scheme.onSurface)),
                      )).toList(),
                      onChanged: (val) => setState(() => _selectedStatus = val!),
                    ),
                    const SizedBox(height: 24),

                    // Action Buttons (PDF & Excel)
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isGeneratingMaster ? null : _handleGenerateMasterSchedule,
                            icon: _isGeneratingMaster 
                                ? const CustomLoader(size: 18, color: Colors.white) 
                                : const Icon(Icons.picture_as_pdf_rounded, size: 18),
                            label: Text(_isGeneratingMaster ? 'Building...' : 'PDF Report', style: const TextStyle(fontWeight: FontWeight.w700)),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: const Color(0xFFD9534F),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isExportingExcel ? null : _handleExportExcel,
                            icon: _isExportingExcel 
                                ? const CustomLoader(size: 18, color: Colors.white) 
                                : const Icon(Icons.table_chart_rounded, size: 18),
                            label: Text(_isExportingExcel ? 'Exporting...' : 'Excel (CSV)', style: const TextStyle(fontWeight: FontWeight.w700)),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: const Color(0xFF58B982),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // ----------------------------------------------------
              // Individual Amortization Report Card
              // ----------------------------------------------------
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: const Color(0xFF4A90E2).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.person_search_rounded, size: 28, color: Color(0xFF4A90E2)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Individual Amortization', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: scheme.onSurface)),
                              const SizedBox(height: 4),
                              Text('Detailed payment schedule per user', style: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.6))),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider(height: 1)),
                    
                    Text('Select Applicant', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
                    const SizedBox(height: 12),
                    
                    _isLoadingLoans
                        ? const Center(child: CircularProgressIndicator())
                        : _activeLoans.isEmpty
                            ? Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(12)),
                                child: Text('No active loans found in the system.', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6))),
                              )
                            : DropdownButtonFormField<String>(
                                initialValue: _selectedLoanId,
                                hint: Text('Choose a loan...', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7))),
                                dropdownColor: scheme.surface,
                                isExpanded: true, 
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                ),
                                items: _activeLoans.map((loan) {
                                  final name = loan['profiles']?['full_name'] ?? 'Unknown';
                                  final amount = currency.format((loan['amount_requested'] as num?)?.toDouble() ?? 0);
                                  return DropdownMenuItem<String>(
                                    value: loan['id'].toString(),
                                    child: Text('$name (UGX $amount)', style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface)),
                                  );
                                }).toList(),
                                onChanged: (val) => setState(() => _selectedLoanId = val),
                              ),
                    
                    const SizedBox(height: 24),
                    
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: (_isGeneratingAmortization || _selectedLoanId == null) ? null : _handleGenerateAmortization,
                        icon: _isGeneratingAmortization 
                            ? const CustomLoader(size: 20, color: Colors.white) 
                            : const Icon(Icons.analytics_rounded),
                        label: Text(_isGeneratingAmortization ? 'Calculating...' : 'Generate Schedule', style: const TextStyle(fontWeight: FontWeight.w700)),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: const Color(0xFF4A90E2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}