import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/app_info.dart';

// AppInfo.appVersion is a hand-synced constant ("avoids a package_info_plus
// dependency for one string") — and hand-sync has now been missed in three
// releases running: v0.3 caught About stuck on 0.1.0, then 0.7.0 and 0.7.1
// shipped showing 0.6.0. A comment saying "bump this too" doesn't fail CI;
// this does.
void main() {
  test('AppInfo.appVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final versionLine = pubspec.firstWhere((l) => l.startsWith('version:'));
    final pubspecVersion = versionLine.split(':')[1].trim().split('+').first;

    expect(AppInfo.appVersion, pubspecVersion,
        reason: 'About would show the wrong version — bump '
            'AppInfo.appVersion alongside pubspec.yaml');
  });
}
