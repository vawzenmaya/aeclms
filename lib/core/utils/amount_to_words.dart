// lib/core/utils/amount_to_words.dart
//
// Converts a numeric amount into words, e.g. 20000000 -> "Twenty Million Shillings Only"
// Used to auto-fill the "Amount in words" field as the applicant types the amount.
// No external package needed — small, dependency-free, and easy to adjust for currency wording.

class AmountToWords {
  static const _ones = [
    '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
    'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
    'Seventeen', 'Eighteen', 'Nineteen'
  ];
  static const _tens = [
    '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'
  ];

  /// Convert a whole-number amount to words. [currency] defaults to "Shillings"
  /// — change to whatever your community's currency wording should be.
  static String convert(num amount, {String currency = 'Shillings'}) {
    final whole = amount.truncate();
    if (whole == 0) return 'Zero $currency Only';

    final parts = <String>[];
    var remaining = whole;

    const scales = [
      [1000000000, 'Billion'],
      [1000000, 'Million'],
      [1000, 'Thousand'],
    ];

    for (final scale in scales) {
      final divisor = scale[0] as int;
      final label = scale[1] as String;
      if (remaining >= divisor) {
        final chunk = remaining ~/ divisor;
        parts.add('${_threeDigits(chunk)} $label');
        remaining %= divisor;
      }
    }

    if (remaining > 0) {
      parts.add(_threeDigits(remaining));
    }

    return '${parts.join(' ')} $currency Only'.trim();
  }

  static String _threeDigits(int n) {
    final buffer = <String>[];
    if (n >= 100) {
      buffer.add('${_ones[n ~/ 100]} Hundred');
      n %= 100;
    }
    if (n >= 20) {
      buffer.add(_tens[n ~/ 10]);
      if (n % 10 != 0) buffer.add(_ones[n % 10]);
    } else if (n > 0) {
      buffer.add(_ones[n]);
    }
    return buffer.join(' ');
  }
}

// Usage in the application form, wired to the amount TextField's onChanged:
//
// TextEditingController amountCtrl = TextEditingController();
// TextEditingController amountInWordsCtrl = TextEditingController();
//
// amountCtrl.addListener(() {
//   final value = num.tryParse(amountCtrl.text.replaceAll(',', ''));
//   amountInWordsCtrl.text = value != null ? AmountToWords.convert(value) : '';
// });
//
// The words field stays editable, so the applicant (or committee) can adjust it
// if the auto-generated wording ever needs a tweak.
