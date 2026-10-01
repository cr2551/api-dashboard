// Picks the right SystemNotifier for the platform at compile time:
// the browser, Android (dart:io), or an unsupported stub.
export 'notifier_stub.dart'
    if (dart.library.js_interop) 'notifier_web.dart'
    if (dart.library.io) 'notifier_io.dart';
