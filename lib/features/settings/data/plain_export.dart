import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/sanctuary_backup/data/backup_serializer.dart';

/// The plain-JSON export, gathered through the SAME snapshot the encrypted
/// backup uses — one gathering path, so the two exports can never disagree
/// about what the app holds. (v0.1 shipped the settings tile serializing an
/// empty export; this seam is the fix and its regression test's anchor.)
Future<String> buildPlainExport(AppDatabase db) async {
  final export = await PeckishBackupSerializer(db).snapshot();
  return export.toPrettyJson();
}
