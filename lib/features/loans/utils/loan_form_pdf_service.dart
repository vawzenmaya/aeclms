// lib/features/loans/utils/loan_form_pdf_service.dart

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class LoanFormPdfService {
  /// 1. Generates the Initial Application Form (Printable before reviews)
  static Future<void> generateInitialApplicationForm({
    required Map<String, dynamic> loan,
  }) async {
    final pdf = pw.Document();
    final currency = NumberFormat("#,##0", "en_US");
    
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('AEC SACCO', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                  pw.SizedBox(height: 4),
                  pw.Text('LOAN APPLICATION FORM', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Text('Status: ${loan['status']?.toString().toUpperCase()}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
            ],
          ),
          pw.Divider(thickness: 2, color: PdfColors.green900),
          pw.SizedBox(height: 16),
          
          _buildSectionHeader('1. Applicant Profile'),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            children: [
              _buildTableRow('Full Name', loan['full_name'] ?? '-'),
              _buildTableRow('Email', loan['email'] ?? '-'),
              _buildTableRow('Phone', loan['phone'] ?? '-'),
              _buildTableRow('Employee / ID No.', loan['employee_number'] ?? '-'),
              _buildTableRow('Monthly Net Pay', 'UGX ${currency.format(loan['net_pay'] ?? 0)}'),
            ],
          ),
          
          pw.SizedBox(height: 16),
          _buildSectionHeader('2. Loan Particulars'),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            children: [
              _buildTableRow('Loan Category', (loan['loan_category'] == 'emergency' ? 'Emergency' : 'Normal')),
              _buildTableRow('Application Type', (loan['loan_type'] == 'topup' ? 'Top-up' : 'New Loan')),
              _buildTableRow('Amount Requested', 'UGX ${currency.format(loan['amount_requested'] ?? 0)}'),
              _buildTableRow('Amount in Words', loan['amount_in_words'] ?? '-'),
              _buildTableRow('Purpose', loan['purpose'] ?? '-'),
              _buildTableRow('Duration', '${loan['duration_months'] ?? '-'} Months'),
              _buildTableRow('Initial Repayment Date', loan['initial_repayment_date'] ?? '-'),
              _buildTableRow('Expected End Date', loan['expected_end_date'] ?? '-'),
            ],
          ),

          pw.SizedBox(height: 16),
          _buildSectionHeader('3. Collateral & Disbursement Details'),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            children: [
              _buildTableRow('Savings Balance', 'UGX ${currency.format(loan['savings_balance'] ?? 0)}'),
              _buildTableRow('Bank Name', loan['bank_name'] ?? '-'),
              _buildTableRow('Account Name', loan['bank_account_holder_name'] ?? '-'),
              _buildTableRow('Account Number', loan['bank_account_number'] ?? '-'),
            ],
          ),
          
          pw.SizedBox(height: 32),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(width: 150, child: pw.Divider(color: PdfColors.black)),
                  pw.Text('Applicant Signature', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(width: 150, child: pw.Divider(color: PdfColors.black)),
                  pw.Text('Date', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Loan_Application_${loan['full_name']?.replaceAll(' ', '_')}.pdf',
    );
  }

  /// 2. Generates the Final Executed Loan Form (Includes all approvals, comments, and disbursement data)
  static Future<void> generateFinalExecutionForm({
    required Map<String, dynamic> loan,
    required List<Map<String, dynamic>> stages,
    required List<Map<String, dynamic>> actions,
  }) async {
    final pdf = pw.Document();
    final currency = NumberFormat("#,##0", "en_US");

    final disbursementAction = actions.cast<Map<String, dynamic>?>().firstWhere(
      (a) => a?['disbursement_mode'] != null,
      orElse: () => null,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('AEC SACCO', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                  pw.SizedBox(height: 4),
                  pw.Text('FINAL LOAN EXECUTION & DISBURSEMENT CERTIFICATE', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.green900)),
                child: pw.Text('DISBURSED', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
              ),
            ],
          ),
          pw.Divider(thickness: 2, color: PdfColors.green900),
          pw.SizedBox(height: 16),

          _buildSectionHeader('Loan Summary'),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            children: [
              _buildTableRow('Borrower Name', loan['full_name'] ?? '-'),
              _buildTableRow('Approved Amount', 'UGX ${currency.format(loan['amount_requested'] ?? 0)}'),
              _buildTableRow('Monthly Installment', 'UGX ${currency.format(loan['installment_amount'] ?? 0)}'),
              _buildTableRow('Duration', '${loan['duration_months'] ?? '-'} Months'),
              if (disbursementAction != null) ...[
                _buildTableRow('Disbursement Mode', disbursementAction['disbursement_mode'] ?? '-'),
                if (disbursementAction['cheque_number'] != null)
                  _buildTableRow('Cheque Number', disbursementAction['cheque_number']),
                _buildTableRow('Disbursement Date', disbursementAction['created_at'] != null ? DateFormat('MMM d, yyyy').format(DateTime.parse(disbursementAction['created_at'])) : '-'),
              ],
            ],
          ),

          pw.SizedBox(height: 16),
          _buildSectionHeader('Workflow Approval Audit Trail & Signatures'),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.green900),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headers: ['Stage Name', 'Approver / Actor', 'Action', 'Remarks / Signature Comment', 'Date'],
            data: stages.map((stage) {
              final action = actions.cast<Map<String, dynamic>?>().firstWhere(
                (a) => a?['stage_id'] == stage['id'],
                orElse: () => null,
              );
              return [
                stage['stage_name'] ?? 'Stage',
                action?['profiles']?['full_name'] ?? 'Pending / Not Reached',
                action?['action']?.toString().toUpperCase() ?? 'PENDING',
                action?['comment'] ?? '-',
                action?['created_at'] != null ? DateFormat('MMM d, yyyy').format(DateTime.parse(action!['created_at'])) : '-',
              ];
            }).toList(),
          ),

          pw.SizedBox(height: 32),
          pw.Text('This document serves as an immutable official record of the credit committee clearance and fund disbursement.', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600), textAlign: pw.TextAlign.center),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Final_Execution_Certificate_${loan['full_name']?.replaceAll(' ', '_')}.pdf',
    );
  }

  static pw.Widget _buildSectionHeader(String title) {
    return pw.Text(title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green800));
  }

  static pw.TableRow _buildTableRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(value, style: const pw.TextStyle(fontSize: 9))),
      ],
    );
  }
}