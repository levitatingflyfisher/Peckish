// Platform-selected brain factory — io is the default branch (it hands out
// the flutter_gemma implementation); web gets the null factory and never
// compiles the plugin.
export 'local_brain_factory_io.dart'
    if (dart.library.js_interop) 'local_brain_factory_web.dart';
