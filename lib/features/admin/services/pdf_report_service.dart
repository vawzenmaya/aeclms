// lib/features/admin/services/pdf_report_service.dart

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

class PdfReportService {
  static const _primaryColor = PdfColor.fromInt(0xFF1E3A8A); // Deep Corporate Blue
  static const _accentColor = PdfColor.fromInt(0xFF58B982); // Financial Green
  static const _greyLight = PdfColor.fromInt(0xFFF3F4F6);
  static const _textDark = PdfColor.fromInt(0xFF1F2937);

  /// Generates the Master Loan Schedule (All Loans, Cleared, or Running)
  static Future<void> generateMasterSchedule({
    required String reportMonth,
    required List<Map<String, dynamic>> loans,
    required String filterStatus, // 'All', 'Cleared', 'Running'
  }) async {
    final pdf = pw.Document();
    final currency = NumberFormat("#,##0", "en_US");

    // Calculate Totals for the Summary Box
    final double totalAmount = loans.fold(0.0, (sum, l) => sum + (l['approved_amount'] as num));
    final double totalInstallments = loans.fold(0.0, (sum, l) => sum + (l['monthly_installment'] as num));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape, 
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // HEADER SECTION
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'ATOMIC ENERGY COUNCIL INVESTMENT CLUB',
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _primaryColor),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'MASTER LOAN SCHEDULE',
                    style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: _textDark, letterSpacing: 1.2),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Report Month: $reportMonth',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _primaryColor),
                  ),
                  pw.Text(
                    'Filter Applied: $filterStatus Loans',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Generated: ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now())}',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
                  ),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 20),

          // SUMMARY METRICS BOX
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: _greyLight,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem('Total Records', loans.length.toString()),
                _buildSummaryItem('Total Disbursed (UGX)', currency.format(totalAmount)),
                _buildSummaryItem('Expected Monthly Return (UGX)', currency.format(totalInstallments)),
              ],
            ),
          ),

          pw.SizedBox(height: 24),

          // DATA TABLE
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: _primaryColor),
            cellStyle: const pw.TextStyle(fontSize: 9, color: _textDark),
            cellAlignments: {
              0: pw.Alignment.centerLeft,  // No.
              1: pw.Alignment.centerLeft,  // Name
              2: pw.Alignment.centerRight, // Approved Amount
              3: pw.Alignment.centerRight, // Monthly Installment
              4: pw.Alignment.center,      // Total Months
              5: pw.Alignment.center,      // Remaining Months
              6: pw.Alignment.center,      // Clearance Month
              7: pw.Alignment.center,      // Status
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
              'Status',
            ],
            data: [
              ...List<List<String>>.generate(loans.length, (index) {
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
              }),
              // Append Totals Row at the bottom of the table
              [
                '',
                'GRAND TOTAL',
                currency.format(totalAmount),
                currency.format(totalInstallments),
                '-',
                '-',
                '-',
                '-',
              ]
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'AEC_Loan_Schedule_${reportMonth.replaceAll(' ', '_')}.pdf',
    );
  }

  /// Generates the Individual Amortization Schedule
  static Future<void> generateAmortizationSchedule({
    required String applicantName,
    required double loanAmount,
    required double interestRate,
    required int periodMonths,
    required double monthlyInstallment,
    required double netPay,
    required List<Map<String, dynamic>> scheduleRows,
  }) async {
    final pdf = pw.Document();
    final currency = NumberFormat("#,##0", "en_US");

    // CALCULATIONS
    double ratio = netPay > 0 ? (monthlyInstallment / netPay) * 100 : 0.0;
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
          // HEADER SECTION
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'ATOMIC ENERGY COUNCIL INVESTMENT CLUB',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _primaryColor),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'INDIVIDUAL AMORTIZATION SCHEDULE',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _textDark, letterSpacing: 1.2),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Generated on: ${DateFormat('MMMM dd, yyyy').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
              ),
            ],
          ),
          pw.SizedBox(height: 24),

          // LOAN SUMMARY BOX
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: _greyLight,
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: pw.BorderRadius.circular(8),
            ),
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
                        pw.Text(
                          '${ratio.toStringAsFixed(1)}%',
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: ratio > 30 ? PdfColors.red : _accentColor),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 24),

          // AMORTIZATION TABLE
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: _primaryColor),
            cellStyle: const pw.TextStyle(fontSize: 9, color: _textDark),
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            headers: [
              'Month / Period',
              'Total Installment (UGX)',
              'Interest Paid (UGX)',
              'Principal Paid (UGX)',
              'Remaining Balance (UGX)',
            ],
            data: tableData, 
          ),
          
          pw.SizedBox(height: 40),
          
          // SIGNATURE BLOCK
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

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Amortization_${applicantName.replaceAll(' ', '_')}.pdf',
    );
  }

  // Helpers for formatting the header texts
  static pw.Widget _buildSummaryItem(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 4),
        pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _primaryColor)),
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