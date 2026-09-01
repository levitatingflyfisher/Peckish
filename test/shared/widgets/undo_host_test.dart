import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:peckish/shared/theme/app_theme.dart';
import 'package:peckish/shared/widgets/undo_host.dart';

// The app-wide Undo bar sits under every screen. Two things it must not do:
// expire, and pad for the phone's gesture bar twice (Furrow's shell bar
// once added a band the height of the gesture bar under its nav bar).
void main() {
  Future<ProviderContainer> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => UndoHost(child: child!),
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: NavigationBar(destinations: const [
            NavigationDestination(icon: Icon(Icons.home), label: 'A'),
            NavigationDestination(icon: Icon(Icons.list), label: 'B'),
          ]),
        ),
      ),
    ));
    return container;
  }

  testWidgets('the bar sits flush under the nav bar and never expires',
      (tester) async {
    final container = await pump(tester);
    final navBefore = tester.getRect(find.byType(NavigationBar));
    expect(navBefore.bottom, 800);

    container
        .read(undoControllerProvider)
        .show(message: 'Deleted Soup', onUndo: () async {});
    await tester.pumpAndSettle();

    final nav = tester.getRect(find.byType(NavigationBar));
    final bar = tester.getRect(find.byType(OhUndoBar));
    expect(bar.bottom, 800);
    expect(nav.bottom, bar.top, reason: 'no band between the two');
    expect(nav.height, navBefore.height - 48,
        reason: 'the gesture-bar inset is taken once, by the Undo bar');

    await tester.pump(const Duration(hours: 1));
    expect(find.text('Deleted Soup'), findsOneWidget);
  });
}
