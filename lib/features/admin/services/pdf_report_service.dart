// lib/features/admin/services/pdf_report_service.dart

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

  /// Generates the Individual Amortization Schedule
  static Future<void> generateAmortizationSchedule({
    required String applicantName,
    required double loanAmount,
    required double interestRate,
    required int periodMonths,
    required double monthlyInstallment,
    required double netPay, // NEW: Added Net Pay parameter
    required List<Map<String, dynamic>> scheduleRows, 
  }) async {
    final pdf = pw.Document();
    final currency = NumberFormat("#,##0", "en_US");

    // CALCULATIONS
    double ratio = (netPay / monthlyInstallment) * 100;
    double totalInstallment = scheduleRows.fold(0, (sum, row) => sum + row['installment']);
    double totalInterest = scheduleRows.fold(0, (sum, row) => sum + row['interest']);
    double totalPrincipal = scheduleRows.fold(0, (sum, row) => sum + row['principal']);

    // Build Table Data
    List<List<String>> tableData = List<List<String>>.generate(
      scheduleRows.length,
      (index) {
        final row = scheduleRows[index];
        return [
          row['period'].toString(),
          currency.format(row['installment'] ?? 0),
          currency.format(row['interest'] ?? 0),
          currency.format(row['principal'] ?? 0),
          currency.format(row['balance'] ?? 0),
        ];
      },
    );

    // Append the Totals Row at the bottom
    tableData.add([
      'TOTAL',
      currency.format(totalInstallment),
      currency.format(totalInterest),
      currency.format(totalPrincipal),
      '-',
    ]);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // Header Section
          pw.Text('AMORTIZATION SCHEDULE', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
          pw.SizedBox(height: 16),
          
          // Loan Summary Box
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Applicant: $applicantName', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Loan Amount: UGX ${currency.format(loanAmount)}'),
                    pw.SizedBox(height: 4),
                    pw.Text('Interest Rate: ${interestRate.toStringAsFixed(1)}%'),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Period: $periodMonths Months', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Net Pay: UGX ${currency.format(netPay)}'),
                    pw.SizedBox(height: 4),
                    pw.Text('Monthly Installment: UGX ${currency.format(monthlyInstallment)}'),
                    pw.SizedBox(height: 4),
                    pw.Text('Ratio (Net Pay/Inst.): ${ratio.toStringAsFixed(2)}%', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
                  ],
                ),
              ],
            ),
          ),
          
          pw.SizedBox(height: 24),

          // Amortization Table
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {
              0: pw.Alignment.center,       
              1: pw.Alignment.centerRight,  
              2: pw.Alignment.centerRight,  
              3: pw.Alignment.centerRight,  
              4: pw.Alignment.centerRight,  
            },
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            headers: ['Month', 'Installment (UGX)', 'Interest (UGX)', 'Principal (UGX)', 'Balance (UGX)'],
            data: tableData, // Passed the data containing the appended Totals row
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Amortization_${applicantName.replaceAll(' ', '_')}.pdf',
    );
  }
}