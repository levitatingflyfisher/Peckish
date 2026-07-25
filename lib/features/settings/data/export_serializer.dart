import 'dart:convert';

import 'package:peckish/shared/extensions/datetime_ext.dart';

/// The date-stamped filename for a data export, e.g.
/// `peckish-export-2026-07-25.json`. Takes the date explicitly (not
/// `DateTime.now`) so tests are deterministic; the UI passes `DateTime.now()`.
String exportFileName(DateTime date) => 'peckish-export-${date.toDateDay()}.json';

/// The whole on-device dataset, ready to serialize to a portable JSON document
/// the user can keep or move. Pure: it holds domain objects and knows how to
/// (de)serialize itself, with value equality so an encode→decode round-trip is
/// testable. Dates serialize as ISO-8601 strings.
///
/// Sections are added as their features land (custom foods, diary entries,
/// saved meals, recipes, plans, grocery items); each addition extends
/// [_toMap]/[fromJson] and the round-trip tests in the same commit.
class PeckishExport {
  /// Peckish's WIRE schema counter — deliberately a hardcoded 1, NOT
  /// `AppDatabase.schemaVersion`. The drift version counts on-device
  /// migrations (column adds, index tweaks) that don't change this JSON
  /// shape; tying the wire counter to it would make every routine DB
  /// migration reject older installs from restoring newer backups for no
  /// reason. Bump this only when the exported JSON itself changes
  /// incompatibly (SANCTUARY-BRIEF §2.8 — additive keys never require a
  /// bump).
  static const schemaVersion = 1;

  /// When this export was produced. Nullable so a hand-edited or legacy file
  /// without a stamp still restores (preview shows "unknown age", never an
  /// error).
  final DateTime? createdAt;

  const PeckishExport({this.createdAt});

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(_toMap());

  Map<String, Object?> _toMap() => {
        'app': 'peckish',
        'schemaVersion': schemaVersion,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      };

  factory PeckishExport.fromJson(String json) {
    final raw = jsonDecode(json);
    if (raw is! Map<String, Object?>) {
      throw const FormatException('export root must be a JSON object');
    }
    if (raw['app'] != 'peckish') {
      throw const FormatException('not a Peckish export');
    }
    final version = raw['schemaVersion'];
    if (version is! int || version > schemaVersion) {
      throw FormatException(
        'export schema $version is newer than this app understands '
        '($schemaVersion) — update Peckish, then restore',
      );
    }
    final stamp = raw['createdAt'];
    return PeckishExport(
      createdAt: stamp is String ? DateTime.tryParse(stamp) : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PeckishExport && other.createdAt == createdAt;

  @override
  int get hashCode => createdAt.hashCode;
}
