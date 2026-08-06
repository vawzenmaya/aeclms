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

  /// Creates the loan row as a draft (or updates it if [existingLoanId] is given).
  /// Returns the loan id. The database computes installment/fee/DTI server-side —
  /// call [fetchLoan] after this if you need the authoritative computed values.
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
    String? securityDescription,
    double? securityEstimatedValue,
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
      'security_description': securityDescription,
      'security_estimated_value': securityEstimatedValue,
      'expected_end_date': expectedEndDate.toIso8601String().split('T').first,
      'net_pay': netPay,
      'guarantor_id': guarantorId,
      'bank_account_holder_name': bankAccountHolderName,
      'bank_name': bankName,
      'bank_account_number': bankAccountNumber,
      'bank_sort_code': bankSortCode,
      'bank_swift_code': bankSwiftCode,
      'bank_details_confirmed': bankDetailsConfirmed,
      'parent_loan_id': ?parentLoanId,
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

  /// Flips a draft/returned loan into the submission pipeline.
  /// The database trigger decides whether that means "awaiting_guarantor"
  /// or straight to "in_review", based on whether guarantor_id is set.
  Future<void> submit(String loanId, {required bool hasGuarantor}) async {
    await _client
        .from('loans')
        .update({'status': hasGuarantor ? 'awaiting_guarantor' : 'in_review'})
        .eq('id', loanId);
  }

  Future<Map<String, dynamic>> fetchLoan(String loanId) async {
    return await _client.from('loans').select().eq('id', loanId).single();
  }

  /// Every loan the current user is allowed to see (RLS already limits this
  /// to: their own applications, loans awaiting their approval, loans they've
  /// acted on before, and loans they're the guarantor for).
  Future<List<Map<String, dynamic>>> fetchVisibleLoans() async {
    final rows = await _client.from('loans').select().order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// (template_id, stage_order) pairs that belong to any role the current
  /// user holds — used to work out which in_review loans are actually
  /// awaiting THEIR action right now, vs just visible to them for other
  /// reasons (applicant, past actor, guarantor).
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

  /// Fetches the workflow_stages row matching a loan's current stage —
  /// tells you the stage's id (needed to record an action), its name, and
  /// whether it's the disbursement stage.
  Future<Map<String, dynamic>> fetchCurrentStage(Map<String, dynamic> loan) async {
    return await _client
        .from('workflow_stages')
        .select()
        .eq('template_id', loan['template_id'])
        .eq('stage_order', loan['current_stage_order'])
        .single();
  }

  /// Deletes a draft or returned application. 
  /// Uses .select() to verify the row was actually deleted by RLS.
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

  /// The full ordered list of stages for a loan's workflow, for the tracker UI.
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
  /// [firstDeductionDate] is required only when approving the final
  /// (disbursement) stage.
  Future<void> recordStageAction({
    required String loanId,
    required String stageId,
    required String actorId,
    required String action, // 'approved' | 'rejected'
    String? comment,
    DateTime? firstDeductionDate,
  }) async {
    await _client.from('loan_stage_actions').insert({
      'loan_id': loanId,
      'stage_id': stageId,
      'actor_id': actorId,
      'action': action,
      'comment': comment,
      if (firstDeductionDate != null)
        'first_deduction_date': firstDeductionDate.toIso8601String().split('T').first,
    });
  }
}
