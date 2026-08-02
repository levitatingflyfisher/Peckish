import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:peckish/features/sync/data/replay_challenge_store.dart';
import 'package:peckish/features/sync/data/sync_clock.dart';
import 'package:peckish/features/sync/data/sync_codec.dart';
import 'package:peckish/features/sync/data/sync_engine.dart';

/// Peckish's LAN port — one above StillLife's 8420, so a phone running both
/// apps can host both households.
const kSyncPort = 8421;

/// Header carrying the single-use replay challenge on `/sync/import`.
const kChallengeHeader = 'x-sync-challenge';

/// Embedded HTTP server exposing the household sync endpoints on the LAN.
///
/// The wire is encrypted: `/sync/export` and `/sync/import` bodies are
/// binary AEAD frames (nonce ‖ ciphertext ‖ mac, see [SyncCodec]) sealed
/// under a key HKDF-derived from the shared household secret. `/sync/status`
/// stays a minimal cleartext probe that negotiates the protocol version and
/// issues a single-use replay challenge. There is NO plaintext-body path — a
/// frame that will not open is rejected before it touches the database.
///
/// AEAD possession is the pairing proof; there is no bearer token to leak or
/// compare. Asymmetry, documented honestly: `/sync/export` can be triggered
/// by any LAN host (the response is ciphertext, so confidentiality holds;
/// the cost is one export + a clock tick).
class LanSyncServer {
  LanSyncServer({
    required SyncEngine engine,
    required SyncClock clock,
    required Future<String> Function() secret,
    SyncCodec? codec,
    ReplayChallengeStore? challenges,
    int port = kSyncPort,
  })  : _engine = engine,
        _clock = clock,
        _secret = secret,
        _codec = codec ?? SyncCodec(),
        _challenges = challenges ?? ReplayChallengeStore(),
        _port = port;

  final SyncEngine _engine;
  final SyncClock _clock;
  final Future<String> Function() _secret;
  final SyncCodec _codec;
  final ReplayChallengeStore _challenges;
  final int _port;

  HttpServer? _server;

  bool get isRunning => _server != null;

  /// The bound port — pass 0 to [LanSyncServer.new] for an ephemeral one
  /// (the loopback test does).
  int get port => _server?.port ?? _port;

  /// Debug-only request-line logging; never headers, never bodies.
  Middleware _redactedLogger() => (Handler inner) => (Request req) async {
        if (kDebugMode) {
          debugPrint('[LanSyncServer] ${req.method} ${req.requestedUri.path}');
        }
        return inner(req);
      };

  Future<void> start() async {
    if (_server != null) return;
    final router = Router()
      ..get('/sync/status', _handleStatus)
      ..get('/sync/export', _handleExport)
      ..post('/sync/import', _handleImport);
    final handler =
        const Pipeline().addMiddleware(_redactedLogger()).addHandler(router.call);
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, _port);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<Uint8List> _key() async => SyncCodec.deriveKey(await _secret());

  /// `/sync/status` — minimal cleartext capability probe: node id, clock,
  /// protocol version, and a fresh single-use replay challenge. Nothing that
  /// identifies the household beyond "a Peckish lives here".
  Future<Response> _handleStatus(Request request) async {
    return Response.ok(
      jsonEncode({
        'nodeId': await _clock.nodeId(),
        'hlc': (await _clock.next()),
        'proto': SyncCodec.protocolVersion,
        'challenge': _challenges.issue(),
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// `/sync/export` — the local changeset as an encrypted binary frame.
  Future<Response> _handleExport(Request request) async {
    final changeset = await _engine.buildChangeset();
    final frame = await _codec.seal(
      Uint8List.fromList(utf8.encode(changeset.toJsonString())),
      await _key(),
      endpointTag: SyncCodec.endpointExport,
    );
    return Response.ok(frame,
        headers: {'content-type': 'application/octet-stream'});
  }

  /// Grocery lists and meal plans are small; 20 MB of plaintext is a
  /// generous ceiling that still stops a hostile flood.
  static const maxPlaintextBytes = 20 * 1024 * 1024;
  static const _maxFrameBytes = maxPlaintextBytes + SyncCodec.frameOverhead;

  Future<Response> _handleImport(Request request) async {
    final declaredLen = request.contentLength;
    if (declaredLen != null && declaredLen > _maxFrameBytes) {
      return _tooLarge();
    }

    final builder = BytesBuilder(copy: false);
    await for (final chunk in request.read()) {
      builder.add(chunk);
      if (builder.length > _maxFrameBytes) return _tooLarge();
    }
    final frame = builder.takeBytes();

    // Single-use replay challenge, consumed BEFORE decrypt so a replayed
    // frame never reaches the merge.
    final token = request.headers[kChallengeHeader];
    final challenge = token == null ? null : _challenges.consume(token);
    if (challenge == null) {
      return Response(401,
          body:
              jsonEncode({'error': 'Missing or already-used sync challenge.'}),
          headers: {'content-type': 'application/json'});
    }

    final Uint8List plaintext;
    try {
      plaintext = await _codec.open(
        frame,
        await _key(),
        endpointTag: SyncCodec.endpointImport,
        challenge: challenge,
      );
    } on SanctuaryAuthException catch (e) {
      return Response(400,
          body: jsonEncode({'error': e.message}),
          headers: {'content-type': 'application/json'});
    }

    if (plaintext.length > maxPlaintextBytes) return _tooLarge();

    try {
      final changeset = SyncChangeset.fromJsonString(utf8.decode(plaintext));
      final result = await _engine.apply(changeset);
      return Response(
        result.isSuccess ? 200 : 422,
        body: jsonEncode({
          'recordsApplied': result.recordsApplied,
          if (result.error != null) 'error': result.error,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (_) {
      // Never echo exception internals to the peer (the StillLife
      // leftover-review lesson) — authenticated or not, the wire gets a
      // shape, not a stack.
      return Response.internalServerError(
          body: jsonEncode({'error': 'Merge failed.'}),
          headers: {'content-type': 'application/json'});
    }
  }

  Response _tooLarge() => Response(413,
      body: jsonEncode({'error': 'Payload too large'}),
      headers: {'content-type': 'application/json'});
}
