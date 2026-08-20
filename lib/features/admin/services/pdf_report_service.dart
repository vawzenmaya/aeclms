// lib/features/admin/services/pdf_report_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart'; 
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

class PdfReportService {
  static const _primaryColor = PdfColor.fromInt(0xFF1E3A8A); 
  static const _accentColor = PdfColor.fromInt(0xFF58B982); 
  static const _greyLight = PdfColor.fromInt(0xFFF3F4F6);
  static const _textDark = PdfColor.fromInt(0xFF1F2937);

  // ===========================================================================
  // 1. MASTER SCHEDULE
  // ===========================================================================

  static Future<void> generateMasterSchedule({
    required String reportMonth,
    required List<Map<String, dynamic>> loans,
    required String filterStatus,
    required DateTime? startDate,
    required DateTime? endDate,
    required double totalInterestEarned,
    required double totalProcessingFeesEarned,
  }) async {
    final params = {
      'reportMonth': reportMonth,
      'loans': loans,
      'filterStatus': filterStatus,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'totalInterestEarned': totalInterestEarned,
      'totalProcessingFeesEarned': totalProcessingFeesEarned,
    };

    final Uint8List pdfBytes = await compute(_buildMasterScheduleTask, params);

    // BYPASS PRINT DIALOG: Save to temp folder and open directly
    final output = await getTemporaryDirectory();
    final file = File('${output.path}/AEC_Loan_Schedule_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(pdfBytes);
    await OpenFile.open(file.path);
  }

  /// THIS RUNS ON A BACKGROUND CPU CORE
  static Future<Uint8List> _buildMasterScheduleTask(Map<String, dynamic> params) async {
    final reportMonth = params['reportMonth'] as String;
    final loans = params['loans'] as List<Map<String, dynamic>>;
    final filterStatus = params['filterStatus'] as String;
    final totalInterestEarned = params['totalInterestEarned'] as double;
    final totalProcessingFeesEarned = params['totalProcessingFeesEarned'] as double;
    
    final startDateStr = params['startDate'] as String?;
    final endDateStr = params['endDate'] as String?;
    final startDate = startDateStr != null ? DateTime.parse(startDateStr) : null;
    final endDate = endDateStr != null ? DateTime.parse(endDateStr) : null;

    final pdf = pw.Document();
    final currency = NumberFormat("#,##0", "en_US");

    final double totalAmount = loans.fold(0.0, (sum, l) => sum + ((l['approved_amount'] as num?)?.toDouble() ?? 0.0));
    final double totalInstallments = loans.fold(0.0, (sum, l) => sum + ((l['monthly_installment'] as num?)?.toDouble() ?? 0.0));

    final dateRangeStr = (startDate != null && endDate != null)
        ? '${DateFormat('dd MMM yyyy').format(startDate)} to ${DateFormat('dd MMM yyyy').format(endDate)}'
        : reportMonth;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape, 
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('ATOMIC ENERGY COUNCIL INVESTMENT CLUB', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _primaryColor)),
                  pw.SizedBox(height: 4),
                  pw.Text('MASTER LOAN SCHEDULE & FINANCIAL REPORT', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: _textDark, letterSpacing: 1.2)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Period: $dateRangeStr', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _primaryColor)),
                  pw.Text('Filter Applied: $filterStatus Loans', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  pw.SizedBox(height: 4),
                  pw.Text('Generated: ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 16),

          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(color: PdfColors.green50, borderRadius: pw.BorderRadius.circular(8), border: pw.Border.all(color: _accentColor)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem('Interest Earned (Period)', 'UGX ${currency.format(totalInterestEarned)}', isAccent: true),
                _buildSummaryItem('Processing Fees Earned', 'UGX ${currency.format(totalProcessingFeesEarned)}', isAccent: true),
                _buildSummaryItem('Total Portfolio Disbursed', 'UGX ${currency.format(totalAmount)}'),
              ],
            ),
          ),

          pw.SizedBox(height: 16),

          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(color: _greyLight, borderRadius: pw.BorderRadius.circular(8), border: pw.Border.all(color: PdfColors.grey300)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem('Total Records', loans.length.toString()),
                _buildSummaryItem('Total Disbursed (UGX)', currency.format(totalAmount)),
                _buildSummaryItem('Expected Monthly Return (UGX)', currency.format(totalInstallments)),
              ],
            ),
          ),

          pw.SizedBox(height: 20),

          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: _primaryColor),
            cellStyle: const pw.TextStyle(fontSize: 9, color: _textDark),
            cellAlignments: {
              0: pw.Alignment.centerLeft,  
              1: pw.Alignment.centerLeft,  
              2: pw.Alignment.centerRight, 
              3: pw.Alignment.centerRight, // Processing Fee
              4: pw.Alignment.centerRight, // Installment
              5: pw.Alignment.center,      
              6: pw.Alignment.center,      
              7: pw.Alignment.center,      
              8: pw.Alignment.center,      
            },
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            headers: [
              'No.', 
              'Name', 
              'Approved Amount\n(UGX)', 
              'Processing\nFee (UGX)', 
              'Monthly Installment\n(UGX)', 
              'Total\nMonths', 
              'Remaining\nMonths', 
              'Clearance\nMonth', 
              'Status'
            ],
            data: [
              ...List<List<String>>.generate(loans.length, (index) {
                final l = loans[index];
                final approvedAmount = (l['approved_amount'] as num?)?.toDouble() ?? 0.0;
                final processingFee = (l['processing_fee'] as num?)?.toDouble() ?? (approvedAmount * 0.005);

                return [
                  (index + 1).toString(),
                  l['name'] ?? 'Unknown',
                  currency.format(approvedAmount),
                  currency.format(processingFee),
                  currency.format(l['monthly_installment'] ?? 0),
                  (l['total_months'] ?? 0).toString(),
                  (l['remaining_months'] ?? 0).toString(),
                  l['clearance_month'] ?? '-',
                  l['status'] ?? 'Running',
                ];
              }),
              [
                '', 
                'GRAND TOTAL', 
                currency.format(totalAmount), 
                currency.format(totalProcessingFeesEarned), 
                currency.format(totalInstallments), 
                '-', 
                '-', 
                '-', 
                '-'
              ]
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ===========================================================================
  // 2. EXCEL (CSV) EXPORT
  // ===========================================================================

  static Future<void> exportMasterScheduleToExcel({
    required List<Map<String, dynamic>> loans,
    required double totalInterestEarned,
    required double totalProcessingFeesEarned,
  }) async {
    final params = {
      'loans': loans,
      'totalInterestEarned': totalInterestEarned,
      'totalProcessingFeesEarned': totalProcessingFeesEarned,
      'timestamp': DateTime.now().toIso8601String(),
    };

    final String csvData = await compute(_buildCsvTask, params);

    final output = await getTemporaryDirectory();
    final file = File('${output.path}/AEC_Loan_Report_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(csvData);

    await OpenFile.open(file.path);
  }

  /// THIS RUNS ON A BACKGROUND CPU CORE
  static String _buildCsvTask(Map<String, dynamic> params) {
    final loans = params['loans'] as List<Map<String, dynamic>>;
    final totalInterestEarned = params['totalInterestEarned'] as double;
    final totalProcessingFeesEarned = params['totalProcessingFeesEarned'] as double;
    final timestamp = DateTime.parse(params['timestamp'] as String);

    List<List<dynamic>> rows = [];
    rows.add(['ATOMIC ENERGY COUNCIL INVESTMENT CLUB']);
    rows.add(['MASTER LOAN SCHEDULE & FINANCIAL REPORT']);
    rows.add(['Generated On', DateFormat('yyyy-MM-dd HH:mm').format(timestamp)]);
    rows.add(['Total Interest Earned (Period)', totalInterestEarned]);
    rows.add(['Total Processing Fees Earned', totalProcessingFeesEarned]);
    rows.add([]); 

    rows.add([
      'No.', 
      'Applicant Name', 
      'Approved Amount (UGX)', 
      'Processing Fee (UGX)', 
      'Monthly Installment (UGX)', 
      'Total Months', 
      'Remaining Months', 
      'Clearance Month', 
      'Status'
    ]);

    for (int i = 0; i < loans.length; i++) {
      final l = loans[i];
      final approvedAmount = (l['approved_amount'] as num?)?.toDouble() ?? 0.0;
      
      final processingFee = (l['processing_fee'] as num?)?.toDouble() ?? (approvedAmount * 0.005);

      rows.add([
        i + 1,
        l['name'] ?? 'Unknown',
        approvedAmount,
        processingFee, 
        l['monthly_installment'] ?? 0,
        l['total_months'] ?? 0,
        l['remaining_months'] ?? 0,
        l['clearance_month'] ?? '-',
        l['status'] ?? 'Running',
      ]);
    }

    return const ListToCsvConverter().convert(rows);
  }

  // ===========================================================================
  // 3. INDIVIDUAL AMORTIZATION
  // ===========================================================================

  static Future<void> generateAmortizationSchedule({
    required String applicantName,
    required double loanAmount,
    required double interestRate,
    required int periodMonths,
    required double monthlyInstallment,
    required double netPay,
    required List<Map<String, dynamic>> scheduleRows,
  }) async {
    final params = {
      'applicantName': applicantName,
      'loanAmount': loanAmount,
      'interestRate': interestRate,
      'periodMonths': periodMonths,
      'monthlyInstallment': monthlyInstallment,
      'netPay': netPay,
      'scheduleRows': scheduleRows,
    };

    final Uint8List pdfBytes = await compute(_buildAmortizationTask, params);

    // BYPASS PRINT DIALOG: Save to temp folder and open directly
    final output = await getTemporaryDirectory();
    final file = File('${output.path}/Amortization_${applicantName.replaceAll(' ', '_')}.pdf');
    await file.writeAsBytes(pdfBytes);
    await OpenFile.open(file.path);
  }

  /// THIS RUNS ON A BACKGROUND CPU CORE
  static Future<Uint8List> _buildAmortizationTask(Map<String, dynamic> params) async {
    final applicantName = params['applicantName'] as String;
    final loanAmount = params['loanAmount'] as double;
    final interestRate = params['interestRate'] as double;
    final periodMonths = params['periodMonths'] as int;
    final monthlyInstallment = params['monthlyInstallment'] as double;
    final netPay = params['netPay'] as double;
    final scheduleRows = params['scheduleRows'] as List<Map<String, dynamic>>;

    final pdf = pw.Document();
    final currency = NumberFormat("#,##0", "en_US");

    double ratio = netPay > 0 ? (monthlyInstallment / netPay) * 100 : 0.0;
    double totalInstallment = scheduleRows.fold(0, (sum, row) => sum + ((row['installment'] as num?)?.toDouble() ?? 0.0));
    double totalInterest = scheduleRows.fold(0, (sum, row) => sum + ((row['interest'] as num?)?.toDouble() ?? 0.0));
    double totalPrincipal = scheduleRows.fold(0, (sum, row) => sum + ((row['principal'] as num?)?.toDouble() ?? 0.0));

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

    tableData.add(['TOTAL', currency.format(totalInstallment), currency.format(totalInterest), currency.format(totalPrincipal), '-']);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text('ATOMIC ENERGY COUNCIL INVESTMENT CLUB', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _primaryColor)),
              pw.SizedBox(height: 4),
              pw.Text('INDIVIDUAL AMORTIZATION SCHEDULE', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _textDark, letterSpacing: 1.2)),
              pw.SizedBox(height: 8),
              pw.Text('Generated on: ${DateFormat('MMMM dd, yyyy').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
            ],
          ),
          pw.SizedBox(height: 24),

          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(color: _greyLight, border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow('Applicant Name:', applicantName),
                    pw.SizedBox(height: 8),
                    _buildDetailRow('Principal Loan Amount:', 'UGX ${currency.format(loanAmount)}'),
                    pw.SizedBox(height: 8),
                    _buildDetailRow('Interest Rate (Annual):', '${interestRate.toStringAsFixed(1)}%'),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    _buildDetailRow('Repayment Period:', '$periodMonths Months'),
                    pw.SizedBox(height: 8),
                    _buildDetailRow('Monthly Net Pay:', 'UGX ${currency.format(netPay)}'),
                    pw.SizedBox(height: 8),
                    _buildDetailRow('Monthly Installment:', 'UGX ${currency.format(monthlyInstallment)}'),
                    pw.SizedBox(height: 8),
                    pw.Row(
                      children: [
                        pw.Text('DTI Ratio (Inst/NetPay): ', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        pw.Text('${ratio.toStringAsFixed(1)}%', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: ratio > 30 ? PdfColors.red : _accentColor)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 24),

          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: _primaryColor),
            cellStyle: const pw.TextStyle(fontSize: 9, color: _textDark),
            cellAlignments: {
              0: pw.Alignment.center, 1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight,
            },
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            headers: ['Month / Period', 'Total Installment (UGX)', 'Interest Paid (UGX)', 'Principal Paid (UGX)', 'Remaining Balance (UGX)'],
            data: tableData, 
          ),
          
          pw.SizedBox(height: 40),
          
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(width: 150, height: 1, color: PdfColors.grey400),
                  pw.SizedBox(height: 8),
                  pw.Text('Applicant Signature', style: const pw.TextStyle(fontSize: 10)),
                ]
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(width: 150, height: 1, color: PdfColors.grey400),
                  pw.SizedBox(height: 8),
                  pw.Text('Authorized Approver', style: const pw.TextStyle(fontSize: 10)),
                ]
              ),
            ]
          )
        ],
      ),
    );

    return pdf.save();
  }

  // ===========================================================================
  // WIDGET HELPERS
  // ===========================================================================

  static pw.Widget _buildSummaryItem(String label, String value, {bool isAccent = false}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 4),
        pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: isAccent ? _accentColor : _primaryColor)),
      ],
    );
  }

  static pw.Widget _buildDetailRow(String label, String value) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(width: 8),
        pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _textDark)),
      ],
    );
  }
}

class ListToCsvConverter {
  const ListToCsvConverter();

  String convert(List<List<dynamic>> rows) {
    return rows.map((row) {
      return row.map((cell) {
        if (cell == null) return '';
        String text = cell.toString();
        if (text.contains(',') || text.contains('"') || text.contains('\n')) {
          return '"${text.replaceAll('"', '""')}"';
        }
        return text;
      }).join(',');
    }).join('\n');
  }
}