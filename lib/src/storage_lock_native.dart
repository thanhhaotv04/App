Future<T> lock<T>(Future<T> Function() action) => action();
