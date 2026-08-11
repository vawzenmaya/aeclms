// lib/features/admin/presentation/report_generation_screen.dart

// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/custom_loader.dart';
import '../services/pdf_report_service.dart';

class ReportGenerationScreen extends StatefulWidget {
  const ReportGenerationScreen({super.key});

  @override
  State<ReportGenerationScreen> createState() => _ReportGenerationScreenState();
}

class _ReportGenerationScreenState extends State<ReportGenerationScreen> {
  // Master Schedule State
  String _selectedStatus = 'All';
  final String _selectedMonth = 'July 2026';
  bool _isGeneratingMaster = false;
  final List<String> _statusOptions = ['All', 'Running', 'Cleared'];

  // Individual Amortization State
  bool _isLoadingLoans = true;
  bool _isGeneratingAmortization = false;
  List<Map<String, dynamic>> _activeLoans = [];
  String? _selectedLoanId;

final TextEditingController _netPayCtrl = TextEditingController(text: '5000000'); // Defaulting to 5M as per your excel

  @override
  void dispose() {
    _netPayCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchActiveLoans();
  }

  Future<void> _fetchActiveLoans() async {
    try {
      // Fetch loans to populate the dropdown. We join with profiles to get the applicant's name.
      final response = await Supabase.instance.client
          .from('loans')
          .select('id, amount_requested, status, profiles!loans_applicant_id_fkey(full_name)')
          .neq('status', 'draft') // exclude drafts
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
  
  Future<void> _handleGenerateMasterSchedule() async {
    setState(() => _isGeneratingMaster = true);
    
    try {
      // 1. Fetch real data from Supabase
      final response = await Supabase.instance.client
          .from('loans')
          .select('*, profiles!loans_applicant_id_fkey(full_name)')
          .neq('status', 'draft') // Exclude draft applications
          .order('created_at', ascending: false);

      final rawLoans = List<Map<String, dynamic>>.from(response);
      final List<Map<String, dynamic>> formattedData = [];
      
      // 2. Filter and Map the data
      for (var loan in rawLoans) {
        final dbStatus = (loan['status'] as String? ?? '').toLowerCase();
        
        // Map DB status to Report Status
        String reportStatus = 'Pending';
        if (dbStatus == 'approved' || dbStatus == 'active') {
          reportStatus = 'Running';
        } else if (dbStatus == 'cleared') reportStatus = 'Cleared';
        else if (dbStatus == 'rejected') reportStatus = 'Rejected';
        
        // Apply dropdown filter (Skip if it doesn't match the selected filter)
        if (_selectedStatus == 'Running' && reportStatus != 'Running') continue;
        if (_selectedStatus == 'Cleared' && reportStatus != 'Cleared') continue;
        // If _selectedStatus is 'All', we let everything through.

        final amount = (loan['amount_requested'] as num?)?.toDouble() ?? 0.0;
        
        // Dynamic EMI calculation fallback (in case it's not saved in your DB yet)
        double emi = 0;
        if (amount > 0) {
            double monthlyRate = (8.0 / 100) / 12; // 8% standard
            emi = (amount * monthlyRate * pow(1 + monthlyRate, 60)) / (pow(1 + monthlyRate, 60) - 1);
        }

        formattedData.add({
          'name': loan['profiles']?['full_name'] ?? 'Unknown Applicant',
          'approved_amount': loan['amount_approved'] ?? amount, 
          'monthly_installment': loan['monthly_installment'] ?? emi, 
          'total_months': loan['duration_months'] ?? 60,
          'remaining_months': loan['remaining_months'] ?? 60, // You can update this once a Repayments module is built
          'clearance_month': loan['clearance_month'] ?? '-',
          'status': reportStatus,
        });
      }

      if (formattedData.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No loans found for this filter.')),
          );
        }
        return;
      }

      // 3. Generate the PDF
      await PdfReportService.generateMasterSchedule(
        reportMonth: _selectedMonth,
        loans: formattedData,
        filterStatus: _selectedStatus,
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

  Future<void> _handleGenerateAmortization() async {
    if (_selectedLoanId == null) return;
    setState(() => _isGeneratingAmortization = true);

    try {
      final selectedLoan = _activeLoans.firstWhere((l) => l['id'] == _selectedLoanId);
      final applicantName = selectedLoan['profiles']?['full_name'] ?? 'Unknown Applicant';
      final loanAmount = (selectedLoan['amount_requested'] as num?)?.toDouble() ?? 0.0;
      
      // Parse the Net Pay from the text field
      final netPay = double.tryParse(_netPayCtrl.text.replaceAll(',', '')) ?? 0.0;
      
      final periodMonths = 60; 
      final interestRate = 8.0; 

      // --- MATHEMATICAL AMORTIZATION GENERATOR ---
      double monthlyRate = (interestRate / 100) / 12;
      double emi = 0;
      List<Map<String, dynamic>> scheduleRows = [];
      
      if (monthlyRate > 0 && periodMonths > 0 && loanAmount > 0) {
        emi = (loanAmount * monthlyRate * pow(1 + monthlyRate, periodMonths)) / (pow(1 + monthlyRate, periodMonths) - 1);
        double balance = loanAmount;
        
        for (int i = 1; i <= periodMonths; i++) {
          double interest = balance * monthlyRate;
          double principal = emi - interest;
          balance -= principal;
          
          if (balance < 0) balance = 0; 
          
          scheduleRows.add({
            'period': i,
            'installment': emi,
            'interest': interest,
            'principal': principal,
            'balance': balance,
          });
        }
      }

      await PdfReportService.generateAmortizationSchedule(
        applicantName: applicantName,
        loanAmount: loanAmount,
        interestRate: interestRate,
        periodMonths: periodMonths,
        monthlyInstallment: emi,
        netPay: netPay, // PASSING IT HERE
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports Center', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5)),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ----------------------------------------------------
          // Master Schedule Card
          // ----------------------------------------------------
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
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
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Master Loan Schedule', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                          SizedBox(height: 4),
                          Text('Generate summary of all system loans', style: TextStyle(fontSize: 13, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider(height: 1)),
                
                Text('Filters', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
                const SizedBox(height: 12),
                
                DropdownButtonFormField<String>(
                  initialValue: _selectedStatus,
                  decoration: InputDecoration(
                    labelText: 'Loan Status',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  items: _statusOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (val) => setState(() => _selectedStatus = val!),
                ),
                const SizedBox(height: 16),

                // Text('Applicant\'s Net Pay (UGX)', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
                // const SizedBox(height: 12),
                // TextFormField(
                //   controller: _netPayCtrl,
                //   keyboardType: TextInputType.number,
                //   decoration: InputDecoration(
                //     border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                //     contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                //     prefixIcon: const Icon(Icons.payments_outlined),
                //   ),
                // ),
                
                // const SizedBox(height: 24),
                
                // TextFormField(
                //   initialValue: _selectedMonth,
                //   decoration: InputDecoration(
                //     labelText: 'Report Month',
                //     border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                //     contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                //     prefixIcon: const Icon(Icons.calendar_month_rounded),
                //   ),
                //   onChanged: (val) => _selectedMonth = val,
                // ),
                
                // const SizedBox(height: 24),
                
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isGeneratingMaster ? null : _handleGenerateMasterSchedule,
                    icon: _isGeneratingMaster 
                        ? const CustomLoader(size: 20, color: Colors.white) 
                        : const Icon(Icons.picture_as_pdf_rounded),
                    label: Text(_isGeneratingMaster ? 'Generating...' : 'Download PDF', style: const TextStyle(fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFFD9534F),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
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
              color: Theme.of(context).cardTheme.color,
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
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Individual Amortization', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                          SizedBox(height: 4),
                          Text('Detailed payment schedule per user', style: TextStyle(fontSize: 13, color: Colors.grey)),
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
                            child: const Text('No active loans found in the system.', style: TextStyle(color: Colors.grey)),
                          )
                        : DropdownButtonFormField<String>(
                            initialValue: _selectedLoanId,
                            hint: const Text('Choose a loan...'),
                            isExpanded: true, // Prevents text overflow errors
                            decoration: InputDecoration(
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            ),
                            items: _activeLoans.map((loan) {
                              final name = loan['profiles']?['full_name'] ?? 'Unknown';
                              final amount = loan['amount_requested']?.toString() ?? '0';
                              return DropdownMenuItem<String>(
                                value: loan['id'].toString(),
                                child: Text('$name (UGX $amount)', style: const TextStyle(fontWeight: FontWeight.w600)),
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
    );
  }
}