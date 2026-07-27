import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:peckish/features/sync/data/lan_sync_server.dart'
    show kChallengeHeader;
import 'package:peckish/features/sync/data/sync_codec.dart';
import 'package:peckish/features/sync/data/sync_engine.dart';

/// Copy shown when a peer cannot speak this build's encrypted protocol
/// (fail closed — never sync in the clear).
const kOutdatedSyncPeerMessage =
    'Update Peckish on your other device to sync securely.';

/// Status info from a peer's cleartext `/sync/status` probe.
class SyncStatus {
  final String nodeId;
  final String hlc;
  final int proto;
  final String? challenge;

  const SyncStatus({
    required this.nodeId,
    required this.hlc,
    this.proto = 0,
    this.challenge,
  });

  factory SyncStatus.fromJson(Map<String, dynamic> json) => SyncStatus(
        nodeId: json['nodeId'] as String? ?? '',
        hlc: json['hlc'] as String? ?? '',
        proto: json['proto'] as int? ?? 0,
        challenge: json['challenge'] as String?,
      );

  bool get supportsEncryptedSync =>
      proto >= SyncCodec.protocolVersion && challenge != null;
}

/// Thrown when a peer cannot speak the encrypted sync protocol. User-facing.
class SyncProtocolException implements Exception {
  final String message;
  SyncProtocolException([this.message = kOutdatedSyncPeerMessage]);
  @override
  String toString() => message;
}

/// Result of pushing a changeset to a peer.
class PushResult {
  final int recordsApplied;
  final String? error;

  const PushResult({required this.recordsApplied, this.error});

  factory PushResult.fromJson(Map<String, dynamic> json) => PushResult(
        recordsApplied: json['recordsApplied'] as int? ?? 0,
        error: json['error'] as String?,
      );
}

/// HTTP client for talking to a household peer's [LanSyncServer].
///
/// Pull-then-push: fetch their encrypted export and merge it, then seal our
/// changeset (bound to their single-use challenge) and push it. Both bodies
/// are AEAD frames under the shared-secret key; there is no plaintext path.
class LanSyncClient {
  LanSyncClient({
    required SyncEngine engine,
    required Future<String> Function() secret,
    SyncCodec? codec,
    http.Client? httpClient,
  })  : _engine = engine,
        _secret = secret,
        _codec = codec ?? SyncCodec(),
        _http = httpClient ?? http.Client();

  final SyncEngine _engine;
  final Future<String> Function() _secret;
  final SyncCodec _codec;
  final http.Client _http;

  static const _timeout = Duration(seconds: 10);

  String _base(String host, int port) => 'http://$host:$port';

  Future<Uint8List> _key() async => SyncCodec.deriveKey(await _secret());

  Future<SyncStatus> getStatus(String host, int port) async {
    final res = await _http
        .get(Uri.parse('${_base(host, port)}/sync/status'))
        .timeout(_timeout);
    return SyncStatus.fromJson(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<SyncChangeset> fetchExport(String host, int port) async {
    final res = await _http
        .get(Uri.parse('${_base(host, port)}/sync/export'))
        .timeout(_timeout);
    final plaintext = await _codec.open(
      Uint8List.fromList(res.bodyBytes),
      await _key(),
      endpointTag: SyncCodec.endpointExport,
    );
    return SyncChangeset.fromJsonString(utf8.decode(plaintext));
  }

  Future<PushResult> pushChangeset(
    String host,
    int port,
    SyncChangeset changeset, {
    required String challenge,
  }) async {
    final frame = await _codec.seal(
      Uint8List.fromList(utf8.encode(changeset.toJsonString())),
      await _key(),
      endpointTag: SyncCodec.endpointImport,
      challenge: base64.decode(challenge),
    );
    final res = await _http
        .post(
          Uri.parse('${_base(host, port)}/sync/import'),
          headers: {
            'content-type': 'application/octet-stream',
            kChallengeHeader: challenge,
          },
          body: frame,
        )
        .timeout(_timeout);
    return PushResult.fromJson(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Full bidirectional sync with a peer: negotiate (refusing a peer that
  /// cannot encrypt), pull their export and merge it, push ours bound to
  /// their challenge. Returns how many records each side applied.
  Future<({int pulled, int pushed})> syncWith(String host, int port) async {
    final status = await getStatus(host, port);
    if (!status.supportsEncryptedSync) throw SyncProtocolException();

    final remote = await fetchExport(host, port);
    final pulled = await _engine.apply(remote);
    if (!pulled.isSuccess) {
      throw SyncProtocolException(pulled.error!);
    }

    final push = await pushChangeset(
      host,
      port,
      await _engine.buildChangeset(),
      challenge: status.challenge!,
    );
    if (push.error != null) throw SyncProtocolException(push.error!);
    return (pulled: pulled.recordsApplied, pushed: push.recordsApplied);
  }
}
