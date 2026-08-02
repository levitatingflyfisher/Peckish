import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/shared/theme/app_theme.dart';
import 'package:peckish/shared/widgets/download_card.dart';

/// A minimal host for the [DownloadCardEngine] mixin: three items whose
/// installed-probe is whatever the test hands in, so the refresh loop's
/// discipline can be exercised without a real screen.
class _Harness extends StatefulWidget {
  const _Harness(this.probe);

  final Future<bool> Function(String id) probe;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness>
    with DownloadCardEngine<_Harness, String, Never> {
  @override
  Iterable<String> get downloadItems => const ['a', 'b', 'c'];

  @override
  String downloadIdOf(String item) => item;

  @override
  Future<bool> isItemInstalled(String item) => widget.probe(item);

  @override
  Future<bool> itemHasPartial(String item) async => false;

  @override
  Stream<(int, int)> itemDownloadStream(String item) => const Stream.empty();

  @override
  Future<void> deleteItemFiles(String item) async {}

  @override
  String deleteConfirmTitle(String item) => 'Delete?';

  @override
  String deleteConfirmMessage(String item) => 'Really?';

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  group('DownloadProgressThrottle', () {
    test('a known total emits once per whole percent', () {
      final throttle = DownloadProgressThrottle();
      const total = 200 * 1024;
      var emits = 0;
      for (var received = 1024; received <= total; received += 1024) {
        if (throttle.shouldEmit(received, total)) emits++;
      }
      // 200 chunks crossing 0..100% — each percent earns exactly one
      // setState, never one per chunk.
      expect(emits, 101);
    });

    test('an unknown total emits on the first chunk, then every ~512 KB',
        () {
      final throttle = DownloadProgressThrottle();
      var emits = 0;
      var received = 0;
      for (var i = 0; i < 100; i++) {
        received += 8 * 1024;
        if (throttle.shouldEmit(received, -1)) emits++;
      }
      // 100 × 8 KB chunks: the old `null != -1` check passed EVERY chunk —
      // a 100-setState storm for a bar that shows no percent at all.
      expect(emits, 2);
    });
  });

  group('WakelockRefcount', () {
    test('two holders share one wakelock: enable on 0→1, disable on 1→0',
        () async {
      var enables = 0;
      var disables = 0;
      final lock = WakelockRefcount(
        enable: () async => enables++,
        disable: () async => disables++,
      );

      await lock.acquire();
      await lock.acquire(); // a second download joins mid-flight
      expect(enables, 1, reason: 'the light is already on');

      await lock.release();
      expect(disables, 0,
          reason: 'the first finisher must not switch the light off '
              'under the survivor');

      await lock.release();
      expect(disables, 1, reason: 'last one out turns it off');
    });

    test('a throwing platform stays best-effort and over-release is ignored',
        () async {
      final lock = WakelockRefcount(
        enable: () async => throw Exception('no plugin here'),
        disable: () async => throw Exception('no plugin here'),
      );
      await lock.acquire();
      await lock.release();
      await lock.release(); // stray extra release: quietly a no-op
      // Reaching this line without an escaped throw IS the assertion.
    });
  });

  group('refreshDownloadStatuses', () {
    testWidgets('never overwrites an item that is downloading right now',
        (tester) async {
      await tester.pumpWidget(_Harness((id) async => false));
      final state = tester.state<_HarnessState>(find.byType(_Harness));
      state.downloadStatuses['b'] = const DownloadInProgress<Never>(42);

      await state.refreshDownloadStatuses();
      await tester.pump();

      expect(state.downloadStatuses['b'], isA<DownloadInProgress<Never>>(),
          reason: "a sibling's completion refresh flipping a live download "
              'to Paused invites a second writer on the same partial');
      expect(state.downloadStatuses['a'], isA<DownloadNotStarted<Never>>());
    });

    testWidgets("one item's disk failure does not abort the sweep",
        (tester) async {
      await tester.pumpWidget(_Harness((id) async {
        if (id == 'b') throw const FileSystemException('slice vanished');
        return true;
      }));
      final state = tester.state<_HarnessState>(find.byType(_Harness));

      // Must not throw out of the loop (it is fired from initState).
      await state.refreshDownloadStatuses();
      await tester.pump();

      expect(state.downloadStatuses['a'], isA<DownloadInstalled<Never>>());
      expect(state.downloadStatuses['c'], isA<DownloadInstalled<Never>>(),
          reason: 'the loop continues past the failing sibling');
    });
  });

  group('DownloadCardTile failed copy', () {
    Widget tile(DownloadStatus<Never> status) => MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: DownloadCardTile<Never>(
              status: status,
              title: 'A database',
              notDownloadedSubtitle: 'not yet',
              installedSubtitle: (theme, detail) => const Text('installed'),
              failedSubtitle: 'generic failure line',
              deleteTooltip: 'delete',
              onDownload: () {},
              onDelete: () {},
            ),
          ),
        );

    testWidgets('a failure with its own message shows it, not the generic',
        (tester) async {
      await tester.pumpWidget(
          tile(const DownloadFailed('The checksum did not match.')));
      expect(find.text('The checksum did not match.'), findsOneWidget);
      expect(find.text('generic failure line'), findsNothing);
    });

    testWidgets('a failure without a message keeps the generic line',
        (tester) async {
      await tester.pumpWidget(tile(const DownloadFailed()));
      expect(find.text('generic failure line'), findsOneWidget);
    });
  });
}
