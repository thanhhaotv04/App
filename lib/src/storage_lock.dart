import 'dart:async';

import 'storage_lock_native.dart'
    if (dart.library.js_interop) 'storage_lock_web.dart'
    as platform;

// One queue for the native app's UI isolate; Web Locks also coordinate tabs.
Future<void>? _pending;
Future<T> withStorageLock<T>(Future<T> Function() action) async {
  final previous = _pending;
  final gate = Completer<void>();
  _pending = gate.future;
  if (previous != null) await previous;
  try {
    return await platform.lock(action);
  } finally {
    if (identical(_pending, gate.future)) _pending = null;
    gate.complete();
  }
}
