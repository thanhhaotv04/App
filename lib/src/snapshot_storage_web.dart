import 'dart:async';
import 'dart:js_interop';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

const _storageError = FormatException(
  'Browser storage is full or unavailable. Free device space and retry; do not clear this app’s site data.',
);

Future<JSAny?> _request(web.IDBRequest request) {
  final result = Completer<JSAny?>();
  request.onsuccess = ((web.Event _) => result.complete(request.result)).toJS;
  request.onerror = ((web.Event _) => result.completeError(_storageError)).toJS;
  return result.future;
}

Future<web.IDBDatabase> _open() async {
  final request = web.window.indexedDB.open('money-manager-financial-v1', 1);
  request.onupgradeneeded = ((web.Event _) {
    (request.result as web.IDBDatabase).createObjectStore('snapshots');
  }).toJS;
  return await _request(request) as web.IDBDatabase;
}

Future<String?> readSnapshot(SharedPreferences prefs, String key) async {
  final db = await _open();
  try {
    final store = db
        .transaction('snapshots'.toJS, 'readonly')
        .objectStore('snapshots');
    final value = await _request(store.get(key.toJS));
    // Preserve support for ID-scoped snapshots written before IndexedDB.
    return value == null ? prefs.getString(key) : (value as JSString).toDart;
  } finally {
    db.close();
  }
}

Future<bool> writeSnapshot(
  SharedPreferences prefs,
  String key,
  String value,
) async {
  final db = await _open();
  try {
    final transaction = db.transaction('snapshots'.toJS, 'readwrite');
    final committed = Completer<void>();
    transaction.oncomplete = ((web.Event _) => committed.complete()).toJS;
    void failed(web.Event _) {
      if (!committed.isCompleted) committed.completeError(_storageError);
    }

    transaction.onabort = failed.toJS;
    transaction.onerror = failed.toJS;
    transaction.objectStore('snapshots').put(value.toJS, key.toJS);
    await committed.future;
    // Remove an older ID-scoped localStorage copy only after the DB commit.
    await prefs.remove(key);
    return true;
  } finally {
    db.close();
  }
}
