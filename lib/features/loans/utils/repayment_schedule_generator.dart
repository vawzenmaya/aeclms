// lib/features/loans/utils/repayment_schedule_generator.dart

import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

class RepaymentScheduleGenerator {
  static Future<void> generateAndUpload({
    required String loanId,
    required String applicantName,
    required double loanAmount,
    required double interestRate,
    required int periodMonths,
    required double monthlyInstallment,
    required double netPay,
    required String uploadedBy,
  }) async {
    final pdf = pw.Document();
    final currency = NumberFormat("#,##0", "en_US");

    // --- CALCULATIONS ---
    double ratio = monthlyInstallment > 0 ? (netPay / monthlyInstallment) * 100 : 0.0;
    
    double monthlyRate = (interestRate / 100) / 12;
    double balance = loanAmount;
    
    double totalInstallment = 0;
    double totalInterest = 0;
    double totalPrincipal = 0;

    List<List<String>> tableData = [];

    // Generate the mathematical amortization rows
    if (monthlyRate > 0 && periodMonths > 0 && loanAmount > 0) {
      for (int i = 1; i <= periodMonths; i++) {
        double interest = balance * monthlyRate;
        double principal = monthlyInstallment - interest;
        balance -= principal;
        
        if (balance < 0) balance = 0; // Prevent negative floating point rounding issues
        
        totalInstallment += monthlyInstallment;
        totalInterest += interest;
        totalPrincipal += principal;
        
        tableData.add([
          i.toString(),
          currency.format(monthlyInstallment),
          currency.format(interest),
          currency.format(principal),
          currency.format(balance),
        ]);
      }
    }

    // Append the final Totals Row
    tableData.add([
      'TOTAL',
      currency.format(totalInstallment),
      currency.format(totalInterest),
      currency.format(totalPrincipal),
      '-',
    ]);

    // --- DESIGN THE PDF ---
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // Header Section
          pw.Text('AMORTIZATION SCHEDULE', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
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
            headerDecoration: const pw.BoxDecoration(color: PdfColors.green900),
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
            data: tableData, 
          ),
        ],
      ),
    );

    // --- UPLOAD PROCESS ---
    final Uint8List bytes = await pdf.save();
    final supabase = Supabase.instance.client;
    
    final fileName = 'repayment_schedule_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final filePath = '$loanId/$fileName';

    await supabase.storage.from('loan-documents').uploadBinary(
      filePath,
      bytes,
      fileOptions: const FileOptions(contentType: 'application/pdf', upsert: true),
    );

    await supabase.from('loan_documents')
        .delete()
        .eq('loan_id', loanId)
        .eq('doc_type', 'Repayment Schedule');

    // FIXED: Save the filePath so the UI can generate clean signed URLs!
    await supabase.from('loan_documents').insert({
      'loan_id': loanId,
      'doc_type': 'Repayment Schedule', 
      'storage_path': filePath, 
      'uploaded_by': uploadedBy,
    });
  }
}