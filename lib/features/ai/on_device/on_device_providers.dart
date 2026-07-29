import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:peckish/features/ai/on_device/local_brain.dart';
import 'package:peckish/features/ai/on_device/local_brain_factory.dart';
import 'package:peckish/features/ai/on_device/model_download_service.dart';
import 'package:peckish/features/ai/on_device/plate_scanner.dart';
import 'package:peckish/features/ai/presentation/guess_sheet.dart';

/// The platform-selected downloader (inert on web).
final modelDownloadServiceProvider =
    Provider<ModelDownloadService>((_) => ModelDownloadService());

/// The resident on-device brain, or null where none can exist (web).
/// Deliberately NOT autoDispose: the loaded model must survive route
/// changes (the Reckon lesson — reinstalling per navigation dwarfs the
/// inference). The model ID is read lazily at guess time, so switching
/// models in Settings needs no provider surgery.
final localBrainProvider = Provider<LocalBrain?>((ref) => createLocalBrain(
      downloads: ref.watch(modelDownloadServiceProvider),
      modelId: () => ref.read(aiConfigProvider).valueOrNull?.model,
    ));

/// The plate-photo labeler, or null where unsupported. Overridable so the
/// whole snap→label→draft pipeline is widget-testable without hardware.
final plateScannerProvider =
    Provider<PlateScanner?>((_) => createPlateScanner());

/// How a plate photo is obtained: the system camera, falling back to the
/// photo picker when the camera can't start (denied, headless, no lens).
/// A test seam — override with a fixture path.
final platePhotoPickerProvider =
    Provider<Future<String?> Function()>((_) => _pickPlatePhoto);

Future<String?> _pickPlatePhoto() async {
  final picker = ImagePicker();
  try {
    final shot = await picker.pickImage(
        source: ImageSource.camera, maxWidth: 1280, maxHeight: 1280);
    return shot?.path;
  } catch (_) {
    final chosen = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 1280, maxHeight: 1280);
    return chosen?.path;
  }
}
