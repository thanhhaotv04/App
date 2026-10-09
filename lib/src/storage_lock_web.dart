import 'dart:js_interop';

@JS('navigator.locks')
external _LockManager? get _locks;

extension type _LockManager(JSObject _) implements JSObject {
  external JSPromise<JSAny?> request(String name, JSFunction callback);
}

Future<T> lock<T>(Future<T> Function() action) async {
  final locks = _locks;
  if (locks == null) {
    throw const FormatException(
      'Open this app over HTTPS in a browser that supports Web Locks to save data safely.',
    );
  }
  late T result;
  Object? failure;
  StackTrace? trace;
  await locks
      .request(
        'money-manager-storage',
        ((JSAny? _) {
          return (() async {
            try {
              result = await action();
            } catch (error, stack) {
              failure = error;
              trace = stack;
            }
            return null;
          })().toJS;
        }).toJS,
      )
      .toDart;
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
  return result;
}
