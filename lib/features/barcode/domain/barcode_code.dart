/// A validated retail barcode (GTIN): EAN-8, UPC-A (12), EAN-13, or GTIN-14.
///
/// Manual entry is the universal path (the web build has no camera scanner),
/// which makes this the trust boundary: every code is checksum-validated
/// before a network request is spent on it.
class BarcodeCode {
  const BarcodeCode._(this.value);

  /// The normalized digit string exactly as it will appear in the API path.
  final String value;

  static const _lengths = {8, 12, 13, 14};

  /// Parses user (or scanner) input into a valid code, or null. Spaces and
  /// hyphens — how codes are printed under the bars — are stripped first.
  static BarcodeCode? tryParse(String input) {
    final digits = input.replaceAll(RegExp(r'[\s-]'), '');
    if (digits.isEmpty || !RegExp(r'^\d+$').hasMatch(digits)) return null;
    if (!_lengths.contains(digits.length)) return null;
    if (!_checksumValid(digits)) return null;
    return BarcodeCode._(digits);
  }

  /// Standard GTIN mod-10: weights alternate 3,1,3,1… starting with 3 on the
  /// digit nearest the check digit. Holds for every GTIN length.
  static bool _checksumValid(String digits) {
    final check = int.parse(digits[digits.length - 1]);
    var sum = 0;
    var weight = 3;
    for (var i = digits.length - 2; i >= 0; i--) {
      sum += int.parse(digits[i]) * weight;
      weight = weight == 3 ? 1 : 3;
    }
    return (10 - sum % 10) % 10 == check;
  }

  @override
  bool operator ==(Object other) => other is BarcodeCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
