import 'package:crdt/crdt.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:uuid/uuid.dart';

/// The device's sync identity and Hybrid Logical Clock.
///
/// Both persist in the [UserPrefs] table — inside the same database the
/// stamps protect, so clock state and data can never separate (a restored
/// .ohbk carries its clock; the shell prefs it shares the table with are
/// excluded from backup by key prefix, not by table).
///
/// Stamps are `package:crdt` HLC strings, whose fixed-width rendering makes
/// lexicographic comparison a total order — the property every LWW decision
/// in the merge rests on. Don't swap the representation.
class SyncClock {
  SyncClock(this._db);

  /// The one shared clock for [db]. Repositories must use this — two live
  /// instances over the same database could hand out non-monotonic stamps
  /// from stale in-memory state.
  factory SyncClock.of(AppDatabase db) => _shared[db] ??= SyncClock(db);

  static final _shared = Expando<SyncClock>();

  final AppDatabase _db;

  /// One stamp + identity pair, for writers.
  Future<({String hlc, String nodeId})> stamp() async =>
      (hlc: await next(), nodeId: await nodeId());

  static const nodeIdPref = 'sync.node_id';
  static const hlcPref = 'sync.hlc';

  Hlc? _hlc;
  String? _nodeId;

  /// Stable per-install identity, minted on first use.
  Future<String> nodeId() async {
    if (_nodeId != null) return _nodeId!;
    final stored = await _read(nodeIdPref);
    if (stored != null && stored.isNotEmpty) return _nodeId = stored;
    final minted = const Uuid().v4();
    await _write(nodeIdPref, minted);
    return _nodeId = minted;
  }

  /// The next strictly-increasing stamp, persisted before it is handed out.
  Future<String> next() async {
    final hlc = (await _load()).increment();
    _hlc = hlc;
    await _write(hlcPref, hlc.toString());
    return hlc.toString();
  }

  /// Pulls our clock forward past a peer's stamp (LWW max-merge). Garbage
  /// stamps are ignored — a malformed peer must not wedge the clock.
  Future<void> merge(String remote) async {
    if (remote.isEmpty) return;
    try {
      final merged = (await _load()).merge(Hlc.parse(remote));
      _hlc = merged;
      await _write(hlcPref, merged.toString());
    } catch (_) {
      // Ignored: a bad remote stamp never breaks local time.
    }
  }

  Future<Hlc> _load() async {
    if (_hlc != null) return _hlc!;
    final node = await nodeId();
    final stored = await _read(hlcPref);
    if (stored == null || stored.isEmpty) return _hlc = Hlc.zero(node);
    try {
      return _hlc = Hlc.parse(stored);
    } catch (_) {
      return _hlc = Hlc.zero(node);
    }
  }

  Future<String?> _read(String key) async {
    final row = await (_db.select(_db.userPrefs)
          ..where((p) => p.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  /// Deliberately a raw statement: drift's typed inserts broadcast a
  /// user_prefs table notification, and the clock advances on EVERY
  /// stamped write — each one would re-run every prefs watcher's query
  /// mid-write (and wedge drift's executor under widget-test fake-async).
  /// Nothing watches these keys — the clock reads itself with plain
  /// selects — so a silent write is correct, not sneaky.
  Future<void> _write(String key, String value) => _db.customStatement(
        'INSERT OR REPLACE INTO user_prefs ("key", value) VALUES (?, ?)',
        [key, value],
      );
}
