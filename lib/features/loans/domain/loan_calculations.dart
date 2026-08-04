// lib/features/loans/domain/loan_calculations.dart
//
// Mirrors the SQL functions calc_pmt() / calc_flat_installment() so the
// application form can show a live preview as the applicant types.
// The database recalculates everything authoritatively on save — this
// is purely for instant UI feedback, never the value actually stored.

class LoanSettings {
  final double annualInterestRate;
  final double processingFeeRate;
  final double maxDebtToIncomeRatio;
  final double emergencyFlatInterestRate;
  final int emergencyMaxTermMonths;
  final int normalMaxTermMonths;

  const LoanSettings({
    required this.annualInterestRate,
    required this.processingFeeRate,
    required this.maxDebtToIncomeRatio,
    required this.emergencyFlatInterestRate,
    required this.emergencyMaxTermMonths,
    required this.normalMaxTermMonths,
  });

  factory LoanSettings.fromMap(Map<String, dynamic> map) => LoanSettings(
        annualInterestRate: (map['annual_interest_rate'] as num).toDouble(),
        processingFeeRate: (map['processing_fee_rate'] as num).toDouble(),
        maxDebtToIncomeRatio: (map['max_debt_to_income_ratio'] as num).toDouble(),
        emergencyFlatInterestRate: (map['emergency_flat_interest_rate'] as num).toDouble(),
        emergencyMaxTermMonths: map['emergency_max_term_months'] as int,
        normalMaxTermMonths: map['normal_max_term_months'] as int,
      );

  /// Sensible fallback if a community hasn't configured loan_settings yet.
  static const fallback = LoanSettings(
    annualInterestRate: 10.0,
    processingFeeRate: 0.005,
    maxDebtToIncomeRatio: 0.20,
    emergencyFlatInterestRate: 4.0,
    emergencyMaxTermMonths: 2,
    normalMaxTermMonths: 60,
  );
}

class LoanPreview {
  final double interestRate;
  final String interestMethod; // 'flat' | 'reducing_balance'
  final double? installmentAmount;
  final double processingFee;
  final double? debtToIncomeRatio;
  final bool dtiExceeded;
  final int maxTermMonths;
  final bool termExceeded;

  const LoanPreview({
    required this.interestRate,
    required this.interestMethod,
    required this.installmentAmount,
    required this.processingFee,
    required this.debtToIncomeRatio,
    required this.dtiExceeded,
    required this.maxTermMonths,
    required this.termExceeded,
  });
}

class LoanCalculations {
  /// Mirrors calc_pmt(): reducing-balance monthly installment.
  static double? calcPmt(double principal, double annualRatePct, int? nper) {
    if (nper == null || nper <= 0) return null;
    final monthlyRate = (annualRatePct / 100) / 12;
    if (monthlyRate == 0) return _round2(principal / nper);
    final installment = principal * monthlyRate / (1 - _pow(1 + monthlyRate, -nper));
    return _round2(installment);
  }

  /// Mirrors calc_flat_installment(): one-time flat interest, spread evenly.
  static double? calcFlatInstallment(double principal, double flatRatePct, int? nper) {
    if (nper == null || nper <= 0) return null;
    return _round2((principal + principal * (flatRatePct / 100)) / nper);
  }

  static LoanPreview preview({
    required LoanSettings settings,
    required String loanCategory, // 'emergency' | 'normal'
    required double amountRequested,
    required int? termMonths,
    required double? netPay,
  }) {
    final maxTerm = loanCategory == 'emergency'
        ? settings.emergencyMaxTermMonths
        : settings.normalMaxTermMonths;

    final interestRate =
        loanCategory == 'emergency' ? settings.emergencyFlatInterestRate : settings.annualInterestRate;
    final interestMethod = loanCategory == 'emergency' ? 'flat' : 'reducing_balance';

    final installment = loanCategory == 'emergency'
        ? calcFlatInstallment(amountRequested, interestRate, termMonths)
        : calcPmt(amountRequested, interestRate, termMonths);

    final processingFee = _round2(amountRequested * settings.processingFeeRate);

    double? dti;
    bool dtiExceeded = false;
    if (netPay != null && netPay > 0 && installment != null) {
      dti = _round4(installment / netPay);
      dtiExceeded = dti > settings.maxDebtToIncomeRatio;
    }

    return LoanPreview(
      interestRate: interestRate,
      interestMethod: interestMethod,
      installmentAmount: installment,
      processingFee: processingFee,
      debtToIncomeRatio: dti,
      dtiExceeded: dtiExceeded,
      maxTermMonths: maxTerm,
      termExceeded: termMonths != null && termMonths > maxTerm,
    );
  }

  static double _pow(double base, num exponent) {
    // dart:math's pow returns num; keep this file dependency-free & explicit.
    double result = 1.0;
    final isNegative = exponent < 0;
    final n = isNegative ? -exponent : exponent;
    for (int i = 0; i < n; i++) {
      result *= base;
    }
    return isNegative ? 1 / result : result;
  }

  static double _round2(double v) => (v * 100).round() / 100;
  static double _round4(double v) => (v * 10000).round() / 10000;
}
