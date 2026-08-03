import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/sync/data/lan_sync_client.dart';
import 'package:peckish/features/sync/data/lan_sync_server.dart';
import 'package:peckish/features/sync/data/sync_clock.dart';
import 'package:peckish/features/sync/data/sync_engine.dart';
import 'package:peckish/features/sync/data/sync_secret_store.dart';
import 'package:peckish/shared/theme/app_spacing.dart';
import 'package:uuid/uuid.dart';
import 'package:peckish/shared/widgets/input_modal.dart';

/// The household secret store; overridable in tests.
final syncSecretStoreProvider =
    Provider<SyncSecretStore>((_) => const SecureSyncSecretStore());

/// The embedded LAN server, one per app. Kept alive so it can keep serving
/// while the user wanders the app; stopped on dispose.
final lanSyncServerProvider = Provider<LanSyncServer>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final store = ref.watch(syncSecretStoreProvider);
  final server = LanSyncServer(
    engine: SyncEngine(db),
    clock: SyncClock.of(db),
    secret: () async => (await store.read()) ?? '',
  );
  ref.onDispose(server.stop);
  return server;
});

/// Household sync: one code shared by the family's devices, encrypted
/// LAN-only exchange, and a plain statement of what does and doesn't leave
/// the plate.
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  final _host = TextEditingController();
  String? _secret;
  bool _listening = false;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    // The server outlives this screen (kept-alive provider): re-entry must
    // report what it is actually doing, not a fresh local default.
    if (lanSyncSupported) {
      _listening = ref.read(lanSyncServerProvider).isRunning;
    }
    ref.read(syncSecretStoreProvider).read().then((s) {
      if (mounted) setState(() => _secret = s);
    });
  }

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The capability seam answers for the platform; this screen never asks
    // kIsWeb itself.
    if (!lanSyncSupported) {
      return Scaffold(
        appBar: AppBar(title: const Text('Household sync')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              'Household sync runs between the phones and tablets on your '
              'Wi-Fi — the browser cannot join in. Use the Android app for '
              'syncing; your data here stays local.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Household sync')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            'The kitchen is shared; the plate is yours. Recipes, the weekly '
            'plan, groceries, custom foods and saved meals sync between '
            'devices that hold the same household code — encrypted, over '
            'your own Wi-Fi, touching no server anywhere. Food diaries and '
            'targets never leave their device.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Household code', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (_secret == null || _secret!.isEmpty) ...[
            const Text('No code yet. Create one here, then enter it on the '
                'other device — the code is the pairing.'),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              onPressed: _createCode,
              child: const Text('Create a household code'),
            ),
            TextButton(
              onPressed: _enterCode,
              child: const Text('I have a code from another device'),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Text(_secret!,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontFamily: 'monospace')),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy the code',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _secret!)),
                ),
              ],
            ),
            TextButton(
              onPressed: _enterCode,
              child: const Text('Replace with a code from another device'),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text('This device', style: theme.textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reachable for sync'),
            subtitle: const Text(
                'Lets the other device pull from and push to this one '
                'while Peckish is open.'),
            value: _listening,
            onChanged:
                (_secret?.isNotEmpty ?? false) ? (v) => _toggleServer(v) : null,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Sync with a device', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _host,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Other device address',
              hintText: 'e.g. 192.168.1.23',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed:
                (_secret?.isNotEmpty ?? false) && !_busy ? _syncNow : null,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Sync now'),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(_message!, style: theme.textTheme.bodyMedium),
            ),
        ],
      ),
    );
  }

  Future<void> _createCode() async {
    final code = const Uuid().v4();
    await _adoptSecret(code);
  }

  Future<void> _enterCode() async {
    final controller = TextEditingController();
    final code = await showInputDialog<String>(
      context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter the household code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: 'Paste the code from the other device'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Join')),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    if (code.length < kMinSyncSecretLength) {
      setState(() => _message =
          'That code is too short to be a household code — copy the whole '
              'thing from the other device.');
      return;
    }
    await _adoptSecret(code);
  }

  Future<void> _adoptSecret(String code) async {
    await ref.read(syncSecretStoreProvider).write(code);
    // Rows written before sync existed carry no stamp; give them one so
    // they can travel.
    final stamped =
        await SyncEngine(ref.read(appDatabaseProvider)).stampUnstamped();
    if (!mounted) return;
    setState(() {
      _secret = code;
      _message = stamped > 0
          ? 'Household code saved — $stamped existing items made syncable.'
          : 'Household code saved.';
    });
  }

  Future<void> _toggleServer(bool on) async {
    final server = ref.read(lanSyncServerProvider);
    if (on) {
      await server.start();
    } else {
      await server.stop();
    }
    if (mounted) setState(() => _listening = server.isRunning);
  }

  Future<void> _syncNow() async {
    final host = _host.text.trim();
    if (host.isEmpty) {
      setState(
          () => _message = "Enter the other device's address (Settings, then "
              'Household sync, shows it there).');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final store = ref.read(syncSecretStoreProvider);
      final client = LanSyncClient(
        engine: SyncEngine(ref.read(appDatabaseProvider)),
        secret: () async => (await store.read()) ?? '',
      );
      final result = await client.syncWith(host, kSyncPort);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Synced — brought in ${result.pulled}, '
            'sent ${result.pushed}.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = e is SyncProtocolException
            ? e.message
            : "Couldn't reach that device — same Wi-Fi, Peckish open, "
                '"Reachable for sync" turned on?';
      });
    }
  }
}
