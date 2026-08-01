import 'package:peckish/features/sync/data/replay_challenge_store.dart';
import 'package:peckish/features/sync/data/sync_clock.dart';
import 'package:peckish/features/sync/data/sync_codec.dart';
import 'package:peckish/features/sync/data/sync_engine.dart';

/// A browser cannot bind an HTTP server. The seam owns the answer so
/// screens gate on capability, never on `kIsWeb` (the house trio idiom).
bool get lanSyncSupported => false;

/// Web stub: a browser cannot bind an HTTP server, so household sync is
/// native-only. API-compatible with the io implementation; the sync screen
/// shows a calm "not available on web" state instead of offering it.
const kSyncPort = 8421;
const kChallengeHeader = 'x-sync-challenge';

class LanSyncServer {
  LanSyncServer({
    required SyncEngine engine,
    required SyncClock clock,
    required Future<String> Function() secret,
    SyncCodec? codec,
    ReplayChallengeStore? challenges,
    int port = kSyncPort,
  }) : _port = port;

  final int _port;

  bool get isRunning => false;

  int get port => _port;

  Future<void> start() async =>
      throw UnsupportedError('Household sync is not available on web.');

  Future<void> stop() async {}
}
