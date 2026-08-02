/// Static app identity for the About screen and the license page.
///
/// [appVersion] is kept in sync with `pubspec.yaml`'s `version:` field
/// (a hardcoded constant avoids a package_info_plus dependency for one
/// string). The sync is enforced by test/core/app_info_test.dart — the
/// hand-bump was missed in three releases before the test existed.
class AppInfo {
  AppInfo._();

  static const String appName = 'Peckish';
  static const String appVersion = '0.8.0';
  static const String tagline = 'Feed the week.';
}
