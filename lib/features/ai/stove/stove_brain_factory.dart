// Platform-selected stove factory (the house trio idiom) — io is the
// default branch (it hands out the domovoi StoveClient adapter); web gets
// the null factory and never compiles domovoi's dart:io files.
export 'stove_brain_factory_io.dart'
    if (dart.library.js_interop) 'stove_brain_factory_web.dart';
