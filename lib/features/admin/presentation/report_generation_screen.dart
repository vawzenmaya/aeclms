// lib/features/admin/presentation/report_generation_screen.dart

import 'package:flutter/material.dart';
import '../../../core/widgets/custom_loader.dart';
import '../services/pdf_report_service.dart';

class ReportGenerationScreen extends StatefulWidget {
  const ReportGenerationScreen({super.key});

  @override
  State<ReportGenerationScreen> createState() => _ReportGenerationScreenState();
}

class _ReportGenerationScreenState extends State<ReportGenerationScreen> {
  String _selectedStatus = 'All';
  String _selectedMonth = 'July 2026'; // Placeholder - you can make this a date picker
  bool _isGenerating = false;

  final List<String> _statusOptions = ['All', 'Running', 'Cleared'];
  
  // You would replace this with actual Supabase fetching logic
  Future<void> _handleGenerateMasterSchedule() async {
    setState(() => _isGenerating = true);
    
    try {
      // TODO: Fetch this data from Supabase based on the filters.
      // This is mock data formatted to match your Excel sheet structure exactly.
      final mockData = [
        {
          'name': 'Joan Namatovu', 'approved_amount': 0, 'monthly_installment': 0,
          'total_months': 0, 'remaining_months': 0, 'clearance_month': 'Cleared', 'status': 'Cleared'
        },
        {
          'name': 'Geoffrey Muhanguzi', 'approved_amount': 25000000, 'monthly_installment': 1779929,
          'total_months': 15, 'remaining_months': 7, 'clearance_month': 'Feb 2027', 'status': 'Running'
        },
        {
          'name': 'Tomusange Eric', 'approved_amount': 19821379, 'monthly_installment': 1615139,
          'total_months': 13, 'remaining_months': 4, 'clearance_month': 'Nov 2026', 'status': 'Running'
        },
      ];
      
      // Filter the mock data just for demonstration
      final filteredData = _selectedStatus == 'All' 
          ? mockData 
          : mockData.where((d) => d['status'] == _selectedStatus).toList();

      await PdfReportService.generateMasterSchedule(
        reportMonth: _selectedMonth,
        loans: filteredData,
        filterStatus: _selectedStatus,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
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
          // Master Schedule Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFD9534F).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
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
                
                // Filters
                Text('Filters', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
                const SizedBox(height: 12),
                
                // Status Dropdown
                DropdownButtonFormField<String>(
                  value: _selectedStatus,
                  decoration: InputDecoration(
                    labelText: 'Loan Status',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  items: _statusOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (val) => setState(() => _selectedStatus = val!),
                ),
                const SizedBox(height: 16),
                
                // Month Input (Could be upgraded to a DatePicker)
                TextFormField(
                  initialValue: _selectedMonth,
                  decoration: InputDecoration(
                    labelText: 'Report Month',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    prefixIcon: const Icon(Icons.calendar_month_rounded),
                  ),
                  onChanged: (val) => _selectedMonth = val,
                ),
                
                const SizedBox(height: 24),
                
                // Generate Action
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isGenerating ? null : _handleGenerateMasterSchedule,
                    icon: _isGenerating 
                        ? const CustomLoader(size: 20, color: Colors.white) 
                        : const Icon(Icons.picture_as_pdf_rounded),
                    label: Text(_isGenerating ? 'Generating...' : 'Download PDF', style: const TextStyle(fontWeight: FontWeight.w700)),
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
          
          // Placeholder for Individual Amortization Report
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Individual Amortization Report', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                SizedBox(height: 8),
                Text('To generate an amortization schedule, navigate to the specific user\'s loan details page.', style: TextStyle(color: Colors.grey, height: 1.4)),
              ],
            ),
          )
        ],
      ),
    );
  }
}