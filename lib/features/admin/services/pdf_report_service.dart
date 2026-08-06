// lib/features/admin/services/pdf_report_service.dart

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

class PdfReportService {
  /// Generates the Master Loan Schedule (All Loans, Cleared, or Running)
  static Future<void> generateMasterSchedule({
    required String reportMonth,
    required List<Map<String, dynamic>> loans,
    required String filterStatus, // 'All', 'Cleared', 'Running'
  }) async {
    final pdf = pw.Document();
    
    // Formatting currency
    final currency = NumberFormat("#,##0", "en_US");

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape, // Landscape handles the 8 columns better
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // Header Section
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('AEC LOAN SCHEDULE', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                  pw.SizedBox(height: 4),
                  pw.Text('Report Month: $reportMonth', style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
                  pw.Text('Filter: $filterStatus Loans', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600)),
                ],
              ),
              pw.Text(
                'Generated: ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey500),
              ),
            ],
          ),
          
          pw.SizedBox(height: 24),

          // Data Table
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {
              0: pw.Alignment.centerLeft,   // No.
              1: pw.Alignment.centerLeft,   // Name
              2: pw.Alignment.centerRight,  // Approved Amount
              3: pw.Alignment.centerRight,  // Monthly Installment
              4: pw.Alignment.center,       // Number of months
              5: pw.Alignment.center,       // Remaining months
              6: pw.Alignment.center,       // Last month of clearance
              7: pw.Alignment.center,       // Status
            },
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            headers: [
              'No.', 
              'Name', 
              'Approved Amount\n(UGX)', 
              'Monthly Installment\n(UGX)', 
              'Total\nMonths', 
              'Remaining\nMonths', 
              'Clearance\nMonth', 
              'Status'
            ],
            data: List<List<String>>.generate(
              loans.length,
              (index) {
                final l = loans[index];
                return [
                  (index + 1).toString(),
                  l['name'] ?? 'Unknown',
                  currency.format(l['approved_amount'] ?? 0),
                  currency.format(l['monthly_installment'] ?? 0),
                  (l['total_months'] ?? 0).toString(),
                  (l['remaining_months'] ?? 0).toString(),
                  l['clearance_month'] ?? '-',
                  l['status'] ?? 'Running',
                ];
              },
            ),
          ),
        ],
      ),
    );

    // This triggers the native print/share/save PDF dialog on iOS and Android!
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'AEC_Loan_Schedule_$reportMonth.pdf',
    );
  }
}