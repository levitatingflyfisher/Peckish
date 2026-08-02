/// ADR-0010's normalization law: barcodes are stored and queried as digit
/// strings with leading zeros stripped, so a UPC-A and its zero-padded
/// EAN-13/GTIN-14 forms collapse to one key ('00027000612323' →
/// '27000612323'). Checksum validation stays at the input boundary
/// ([BarcodeCode]); this only makes equivalent codes equal.
String normalizeBarcode(String digits) {
  final stripped = digits.replaceFirst(RegExp(r'^0+'), '');
  // All zeros would strip to nothing; keep one so the key stays a digit.
  return stripped.isEmpty ? '0' : stripped;
}
