// lib/features/loans/utils/repayment_schedule_generator.dart

import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

class RepaymentScheduleGenerator {
  static Future<void> generateAndUpload({
    required String loanId,
    required String applicantName,
    required double loanAmount, // The New Total Amount
    required double interestRate,
    required int periodMonths, // The Additional Months for Top-Ups, or Total Months for New
    required double monthlyInstallment,
    required double netPay,
    required String uploadedBy,
  }) async {
    final supabase = Supabase.instance.client;
    final pdf = pw.Document();
    final currency = NumberFormat("#,##0", "en_US");

    // -------------------------------------------------------------------------
    // 1. REFINANCING & TOP-UP MATHEMATICS (Protected by try-catch for RLS)
    // -------------------------------------------------------------------------
    
    int monthsPaid = 0;
    List<Map<String, dynamic>> historicalRows = [];
    int startPeriod = 1;
    int periodsToAmortize = periodMonths;
    double activeInstallment = monthlyInstallment;
    double principalToAmortize = loanAmount;
    double monthlyRate = (interestRate / 100) / 12;

    try {
      // Check if this loan has historical payments
      final repaymentsRes = await supabase.from('repayments').select('amount').eq('loan_id', loanId);
      monthsPaid = repaymentsRes.length;

      final existingSchedule = await supabase.from('loan_amortization_schedule')
          .select()
          .eq('loan_id', loanId)
          .order('period_number');
          
      final scheduleList = List<Map<String, dynamic>>.from(existingSchedule);

      if (monthsPaid > 0 && scheduleList.isNotEmpty) {
        // It is a Top-Up! Preserve the past.
        historicalRows = scheduleList.where((r) => (r['period_number'] as int) <= monthsPaid).toList();
        
        int originalDuration = scheduleList.length;
        
        // The remaining periods = (Original Duration - Paid) + Additional Requested Months
        periodsToAmortize = (originalDuration - monthsPaid) + periodMonths;
        startPeriod = monthsPaid + 1;

        // Find Outstanding Balance
        double outstandingBalance = 0;
        if (historicalRows.isNotEmpty) {
          outstandingBalance = (historicalRows.last['balance'] as num).toDouble();
        }

        // Calculate Top-up Processing Fee: (New Loan Amount - Outstanding Balance) * 0.005
        double newProcessingFee = (loanAmount - outstandingBalance) * 0.005;
        if (newProcessingFee < 0) newProcessingFee = 0;

        // Recalculate true EMI for the new balance over the new remaining period
        if (monthlyRate > 0 && periodsToAmortize > 0) {
          activeInstallment = (principalToAmortize * monthlyRate) / (1 - pow(1 + monthlyRate, -periodsToAmortize));
        } else if (periodsToAmortize > 0) {
          activeInstallment = principalToAmortize / periodsToAmortize;
        }

        // Try to update the loan record with the true combined duration, EMI, and Custom Processing Fee
        try {
          await supabase.from('loans').update({
            'duration_months': monthsPaid + periodsToAmortize,
            'installment_amount': activeInstallment,
            'processing_fee': newProcessingFee,
          }).eq('id', loanId);
        } catch(e) {
          debugPrint('Silent DB Update Blocked by RLS: $e');
        }
        
      } else {
        // It is a completely New Loan. Just calculate standard EMI to be safe.
        if (monthlyRate > 0 && periodsToAmortize > 0) {
          activeInstallment = (principalToAmortize * monthlyRate) / (1 - pow(1 + monthlyRate, -periodsToAmortize));
        } else if (periodsToAmortize > 0) {
          activeInstallment = principalToAmortize / periodsToAmortize;
        }
      }
    } catch(e) {
      debugPrint('Failed to read historical records, falling back to standard math: $e');
      if (monthlyRate > 0 && periodsToAmortize > 0) {
        activeInstallment = (principalToAmortize * monthlyRate) / (1 - pow(1 + monthlyRate, -periodsToAmortize));
      } else if (periodsToAmortize > 0) {
        activeInstallment = principalToAmortize / periodsToAmortize;
      }
    }

    // -------------------------------------------------------------------------
    // 2. GENERATE SCHEDULE ROWS (Past + Future)
    // -------------------------------------------------------------------------
    
    List<List<String>> pdfTableData = [];
    List<Map<String, dynamic>> dbScheduleRows = [];
    
    double totalInstallment = 0;
    double totalInterest = 0;
    double totalPrincipal = 0;

    // A. Inject Historical Rows
    for (var row in historicalRows) {
      pdfTableData.add([
        row['period_number'].toString(),
        currency.format(row['installment']),
        currency.format(row['interest']),
        currency.format(row['principal']),
        currency.format(row['balance']),
      ]);
      totalInstallment += (row['installment'] as num).toDouble();
      totalInterest += (row['interest'] as num).toDouble();
      totalPrincipal += (row['principal'] as num).toDouble();
    }

    // B. Calculate & Inject Future Rows
    double balance = principalToAmortize; 
    for (int i = startPeriod; i < startPeriod + periodsToAmortize; i++) {
      double interest = balance * monthlyRate;
      double principal = activeInstallment - interest;
      balance -= principal;
      if (balance < 0) balance = 0; // Prevent floating point negatives

      pdfTableData.add([
        i.toString(),
        currency.format(activeInstallment),
        currency.format(interest),
        currency.format(principal),
        currency.format(balance),
      ]);

      dbScheduleRows.add({
        'loan_id': loanId,
        'period_number': i,
        'installment': activeInstallment,
        'interest': interest,
        'principal': principal,
        'balance': balance,
      });

      totalInstallment += activeInstallment;
      totalInterest += interest;
      totalPrincipal += principal;
    }

    // Append Totals to PDF
    pdfTableData.add([
      'TOTAL',
      currency.format(totalInstallment),
      currency.format(totalInterest),
      currency.format(totalPrincipal),
      '-',
    ]);

    // -------------------------------------------------------------------------
    // 3. UPDATE DATABASE AMORTIZATION SCHEDULE
    // -------------------------------------------------------------------------
    try {
      if (dbScheduleRows.isNotEmpty) {
        // Attempt to wipe old future rows and replace them
        await supabase.from('loan_amortization_schedule')
            .delete()
            .eq('loan_id', loanId)
            .gte('period_number', startPeriod);
        
        await supabase.from('loan_amortization_schedule')
            .insert(dbScheduleRows);
      }
    } catch(e) {
      debugPrint('Schedule DB write blocked by RLS - proceeding with PDF generation: $e');
    }

    // -------------------------------------------------------------------------
    // 4. DESIGN AND UPLOAD PDF
    // -------------------------------------------------------------------------
    double ratio = activeInstallment > 0 ? (activeInstallment / netPay) * 100 : 0.0;
    int displayDuration = monthsPaid + periodsToAmortize;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text('AMORTIZATION SCHEDULE', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
          pw.SizedBox(height: 16),
          
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
                    pw.Text('Target Principal: UGX ${currency.format(principalToAmortize)}'),
                    pw.SizedBox(height: 4),
                    pw.Text('Interest Rate: ${interestRate.toStringAsFixed(1)}%'),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Total Duration: $displayDuration Months', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Net Pay: UGX ${currency.format(netPay)}'),
                    pw.SizedBox(height: 4),
                    pw.Text('Active Installment: UGX ${currency.format(activeInstallment)}'),
                    pw.SizedBox(height: 4),
                    pw.Text('Ratio (Inst/NetPay.): ${ratio.toStringAsFixed(2)}%', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: ratio > 40 ? PdfColors.red700 : PdfColors.green700)),
                  ],
                ),
              ],
            ),
          ),
          
          pw.SizedBox(height: 24),

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
            data: pdfTableData, 
          ),
        ],
      ),
    );

    final Uint8List bytes = await pdf.save();
    
    final fileName = 'repayment_schedule_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final filePath = '$loanId/$fileName';

    try {
      await supabase.storage.from('loan-documents').uploadBinary(
        filePath,
        bytes,
        fileOptions: const FileOptions(contentType: 'application/pdf', upsert: true),
      );

      await supabase.from('loan_documents')
          .delete()
          .eq('loan_id', loanId)
          .eq('doc_type', 'Repayment Schedule');

      await supabase.from('loan_documents').insert({
        'loan_id': loanId,
        'doc_type': 'Repayment Schedule', 
        'storage_path': filePath, 
        'uploaded_by': uploadedBy,
      });
    } catch(e) {
      debugPrint('Failed to upload PDF schedule: $e');
    }
  }
}