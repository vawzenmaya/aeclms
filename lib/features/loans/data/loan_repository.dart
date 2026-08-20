// lib/features/loans/data/loan_repository.dart

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/loan_calculations.dart';

class GuarantorOption {
  final String id;
  final String fullName;
  const GuarantorOption({required this.id, required this.fullName});
}

class LoanRepository {
  LoanRepository(this._client);
  final SupabaseClient _client;

  Future<LoanSettings> fetchLoanSettings(String communityId) async {
    final row = await _client
        .from('loan_settings')
        .select()
        .eq('community_id', communityId)
        .maybeSingle();
    if (row == null) return LoanSettings.fallback;
    return LoanSettings.fromMap(row);
  }

  Future<List<GuarantorOption>> fetchPossibleGuarantors({
    required String communityId,
    required String excludeProfileId,
  }) async {
    final rows = await _client
        .from('profiles')
        .select('id, full_name')
        .eq('community_id', communityId)
        .neq('id', excludeProfileId)
        .order('full_name');

    return (rows as List)
        .map((r) => GuarantorOption(id: r['id'] as String, fullName: r['full_name'] as String))
        .toList();
  }

  Future<String> _templateIdFor(String loanType) async {
    final rows = await _client
        .from('workflow_templates')
        .select('id')
        .eq('loan_type', loanType)
        .eq('is_active', true)
        .limit(1);
    if (rows.isEmpty) {
      throw Exception(
          'No active workflow template found for loan type "$loanType". '
          'Check the workflow_templates table in Supabase.');
    }
    return rows.first['id'] as String;
  }

  /// Fetches all historical actions/comments made on a specific loan
  Future<List<Map<String, dynamic>>> fetchStageActions(String loanId) async {
    final rows = await _client
        .from('loan_stage_actions')
        .select('*, profiles!actor_id(full_name)')
        .eq('loan_id', loanId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// NEW: Fetches historical repayments and the amortization schedule for a specific loan.
  /// This is critical for the Top-up / Refinancing Engine to accurately determine
  /// the remaining balance and structure the new future installments without altering the past.
  Future<Map<String, dynamic>> fetchLoanHistoryForRefinance(String loanId) async {
    final response = await _client
        .from('loans')
        .select('''
          amount_requested,
          duration_months,
          repayments(amount, created_at),
          loan_amortization_schedule(period_number, balance, installment, interest, principal)
        ''')
        .eq('id', loanId)
        .single();
    return response;
  }

  /// Creates the loan row as a draft (or updates it if [existingLoanId] is given).
  Future<String> saveDraft({
    String? existingLoanId,
    required String applicantId,
    required String communityId,
    required String loanType, // 'new' | 'topup'
    required String loanCategory, // 'emergency' | 'normal'
    required String category, // 'member' | 'non_member'
    required String fullName,
    required String email,
    required String phone,
    String? employeeNumber,
    required double amountRequested,
    required String amountInWords,
    required String purpose,
    double? savingsBalance, 
    String? securityDescription,
    double? securityEstimatedValue,
    required int durationMonths, 
    required DateTime initialRepaymentDate, 
    required DateTime expectedEndDate,
    required double netPay,
    String? guarantorId,
    required String bankAccountHolderName,
    required String bankName,
    required String bankAccountNumber,
    String? bankSortCode,
    required String bankSwiftCode,
    required bool bankDetailsConfirmed,
    String? parentLoanId,
  }) async {
    final payload = {
      'applicant_id': applicantId,
      'community_id': communityId,
      'loan_type': loanType,
      'loan_category': loanCategory,
      'category': category,
      'full_name': fullName,
      'email': email,
      'phone': phone,
      'employee_number': employeeNumber,
      'amount_requested': amountRequested,
      'amount_in_words': amountInWords,
      'purpose': purpose,
      'savings_balance': savingsBalance, 
      'security_description': securityDescription,
      'security_estimated_value': securityEstimatedValue,
      'duration_months': durationMonths, 
      'initial_repayment_date': initialRepaymentDate.toIso8601String().split('T').first, 
      'expected_end_date': expectedEndDate.toIso8601String().split('T').first,
      'net_pay': netPay,
      'guarantor_id': guarantorId,
      'bank_account_holder_name': bankAccountHolderName,
      'bank_name': bankName,
      'bank_account_number': bankAccountNumber,
      'bank_sort_code': bankSortCode,
      'bank_swift_code': bankSwiftCode,
      'bank_details_confirmed': bankDetailsConfirmed,
      if (parentLoanId != null) 'parent_loan_id': parentLoanId,
    };

    if (existingLoanId != null) {
      final rows = await _client
          .from('loans')
          .update(payload)
          .eq('id', existingLoanId)
          .select('id');
      if (rows.isEmpty) {
        throw Exception(
            'Update ran but returned no row back — this usually means a Row Level '
            'Security policy is hiding the loan from you right after the update. '
            'Loan id: $existingLoanId');
      }
      return rows.first['id'] as String;
    } else {
      payload['template_id'] = await _templateIdFor(loanType);
      final rows = await _client.from('loans').insert(payload).select('id');
      if (rows.isEmpty) {
        throw Exception(
            'Insert ran but returned no row back — this usually means a Row Level '
            'Security policy is hiding the new loan from you right after creating it.');
      }
      return rows.first['id'] as String;
    }
  }

  Future<void> submit(String loanId, {required bool hasGuarantor}) async {
    await _client
        .from('loans')
        .update({'status': hasGuarantor ? 'awaiting_guarantor' : 'in_review'})
        .eq('id', loanId);
  }

  Future<Map<String, dynamic>> fetchLoan(String loanId) async {
    return await _client.from('loans').select().eq('id', loanId).single();
  }

  Future<List<Map<String, dynamic>>> fetchVisibleLoans() async {
    final rows = await _client.from('loans').select().order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Set<String>> fetchMyStageAssignments({
    required String profileId,
    required String communityId,
  }) async {
    final roleRows = await _client
        .from('user_roles')
        .select('role_id')
        .eq('profile_id', profileId)
        .eq('community_id', communityId)
        .eq('is_active', true);
    final roleIds = (roleRows as List).map((r) => r['role_id']).toList();
    if (roleIds.isEmpty) return {};

    final stageRows =
        await _client.from('workflow_stages').select('template_id, stage_order').inFilter('role_id', roleIds);
    return (stageRows as List).map((s) => '${s['template_id']}:${s['stage_order']}').toSet();
  }

  Future<Map<String, dynamic>> fetchCurrentStage(Map<String, dynamic> loan) async {
    return await _client
        .from('workflow_stages')
        .select()
        .eq('template_id', loan['template_id'])
        .eq('stage_order', loan['current_stage_order'])
        .single();
  }

  Future<void> deleteDraft(String loanId) async {
    final response = await _client
        .from('loans')
        .delete()
        .eq('id', loanId)
        .inFilter('status', ['draft', 'returned_to_applicant'])
        .select('id');
        
    if (response.isEmpty) {
      throw Exception(
        'Could not delete application. It may have already been submitted, '
        'or you do not have permission to delete it.'
      );
    }
  }

  Future<List<Map<String, dynamic>>> fetchAllStages(String templateId) async {
    final rows = await _client
        .from('workflow_stages')
        .select()
        .eq('template_id', templateId)
        .order('stage_order');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> respondAsGuarantor(String loanId, {required bool confirm, String? comment}) async {
    await _client.rpc('guarantor_respond', params: {
      'p_loan_id': loanId,
      'p_confirm': confirm,
      'p_comment': comment,
    });
  }

  /// Records an approve/reject action at the loan's current stage.
  /// NEW: Added [proofDocumentUrl] to support uploading proof of disbursement.
  Future<void> recordStageAction({
    required String loanId,
    required String stageId,
    required String actorId,
    required String action, 
    String? comment,
    DateTime? firstDeductionDate,
    String? disbursementMode, 
    String? chequeNumber,     
    String? proofDocumentUrl, // <--- NEW PARAMETER
  }) async {
    await _client.from('loan_stage_actions').insert({
      'loan_id': loanId,
      'stage_id': stageId,
      'actor_id': actorId,
      'action': action,
      'comment': comment,
      if (firstDeductionDate != null)
        'first_deduction_date': firstDeductionDate.toIso8601String().split('T').first,
      if (disbursementMode != null) 'disbursement_mode': disbursementMode,
      if (chequeNumber != null && chequeNumber.trim().isNotEmpty) 'cheque_number': chequeNumber,
      if (proofDocumentUrl != null) 'proof_document_url': proofDocumentUrl, // <--- NEW DB ENTRY
    });
  }
}