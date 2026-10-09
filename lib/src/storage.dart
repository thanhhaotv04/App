import 'dart:convert';

import 'package:crypto/crypto.dart' as digest;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'storage_lock.dart';
import 'snapshot_storage_native.dart'
    if (dart.library.js_interop) 'snapshot_storage_web.dart'
    as snapshots;

class BackendConfig {
  static const defaultUrl = 'https://192.168.1.146:3002';
  static const offlineUrl = 'https://offline.local';
  static const legacyDefaultUrl = 'http://127.0.0.1:3000';
  static const key = 'money-manager-backend-url';

  static String normalize(String value) {
    final uri = Uri.tryParse(value.trim().replaceAll(RegExp(r'/+$'), ''));
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
        'Enter a server URL such as https://your-server:3002.',
      );
    }
    final loopback = ['localhost', '127.0.0.1', '::1'].contains(uri.host);
    if (uri.scheme != 'https' && !loopback) {
      throw const FormatException(
        'Use HTTPS to protect your password and financial data.',
      );
    }
    return uri.replace(path: '').toString().replaceAll(RegExp(r'/+$'), '');
  }

  static Future<String> loadUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(key)?.trim();
    if (value == null || value.isEmpty || value == legacyDefaultUrl) {
      return defaultUrl;
    }
    // Preserve the old address for migration and display; requests validate it.
    return value;
  }

  static Future<void> saveUrl(String value) async {
    final normalized = normalize(value);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, normalized)) {
      throw const FormatException(
        'Could not save the server address. Try again.',
      );
    }
  }
}

class LocalSecretStorage {
  static const _secure = FlutterSecureStorage();
  static const _fallbackPrefix = 'money-manager-browser-fallback-v1-';
  // The compatibility fallback is limited to local browser use.
  bool get _allowFallback =>
      kIsWeb && ['localhost', '127.0.0.1', '::1'].contains(Uri.base.host);

  Future<String?> read({required String key}) async {
    if (!kIsWeb) return _secure.read(key: key);
    final prefs = await SharedPreferences.getInstance();
    try {
      final value = await _secure.read(key: key);
      if (value != null) return value;
    } catch (_) {
      if (!_allowFallback) rethrow;
    }
    final fallback = prefs.getString('$_fallbackPrefix$key');
    if (fallback != null && !_allowFallback) {
      // Move existing fallback secrets before returning them on a remote site.
      await _secure.write(key: key, value: fallback);
      if (!await prefs.remove('$_fallbackPrefix$key')) {
        throw const FormatException(
          'Could not secure browser storage. Try again.',
        );
      }
    }
    return fallback;
  }

  Future<void> write({required String key, required String value}) async {
    if (!kIsWeb) {
      await _secure.write(key: key, value: value);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    try {
      await _secure.write(key: key, value: value);
    } catch (_) {
      if (!_allowFallback) rethrow;
      if (!await prefs.setString('$_fallbackPrefix$key', value)) {
        throw const FormatException(
          'Browser storage is unavailable. Check browser privacy settings and try again.',
        );
      }
      return;
    }
    if (!await prefs.remove('$_fallbackPrefix$key')) {
      throw const FormatException(
        'Could not secure browser storage. Try again.',
      );
    }
  }

  Future<void> delete({required String key}) async {
    if (!kIsWeb) {
      await _secure.delete(key: key);
      return;
    }
    try {
      await _secure.delete(key: key);
    } catch (_) {
      if (!_allowFallback) rethrow;
    }
    await (await SharedPreferences.getInstance()).remove(
      '$_fallbackPrefix$key',
    );
  }
}

class AuthCache {
  static const userKey = 'vmc-auth-user';
  static const passwordKey = 'vmc-auth-password';
  static const sessionKey = 'money-manager-session-v2';
  static const pendingLogoutKey = 'money-manager-pending-logouts';
  static const offlineIdKey = 'money-manager-offline-account-id';
  static const offlineAccountPrefix = 'money-manager-offline-account-v1-';
  static final secure = LocalSecretStorage();
  static const passwordIterations = 600000;

  static Future<AuthSession?> load() => withStorageLock(_load);

  static Future<AuthSession?> _load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final saved = await secure.read(key: sessionKey);
    if (saved != null) {
      final json = jsonDecode(saved) as Map<String, dynamic>;
      final session = AuthSession.fromJson(json);
      if (json.containsKey('legacyPassword')) await _save(session);
      await prefs.remove(passwordKey);
      await prefs.remove(userKey);
      return session;
    }
    final name = prefs.getString(userKey);
    final password = prefs.getString(passwordKey);
    if (name == null || name.isEmpty || password == null || password.isEmpty) {
      return null;
    }
    final session = AuthSession(
      name: name,
      backendUrl: await BackendConfig.loadUrl(),
    );
    // Cached credentials do not prove ownership of the old shared dataset.
    await _save(session);
    return session;
  }

  static Future<void> save(AuthSession session) =>
      withStorageLock(() => _save(session));

  static Future<AuthSession> registerOffline(String name, String password) =>
      withStorageLock(() async {
        final trimmedName = _validOfflineName(name);
        _validateOfflinePassword(password);
        final accountKey = _offlineAccountKey(trimmedName);
        if (await secure.read(key: accountKey) != null) {
          throw const FormatException(
            'This local account already exists. Sign in instead.',
          );
        }
        await secure.write(
          key: accountKey,
          value: await _offlinePasswordRecord(trimmedName, password),
        );
        final session = await _offlineSession(trimmedName);
        await _save(session);
        return session;
      });

  static Future<AuthSession> signInOffline(String name, String password) =>
      withStorageLock(() async {
        final trimmedName = _validOfflineName(name);
        final savedName = await _verifyOfflinePassword(trimmedName, password);
        final session = await _offlineSession(savedName);
        await _save(session);
        return session;
      });

  static Future<String> _offlinePasswordRecord(
    String name,
    String password,
  ) async {
    final salt = SecretKeyData.random(length: 16).bytes;
    return jsonEncode({
      'name': name,
      'salt': base64Encode(salt),
      'hash': base64Encode(
        await _passwordHash(password, salt, passwordIterations),
      ),
      'iterations': passwordIterations,
    });
  }

  // Called under the storage lock so attempts and password changes are atomic.
  static Future<String> _verifyOfflinePassword(
    String name,
    String password,
  ) async {
    if (password.isEmpty || password.length > 128) throw _invalidOfflineLogin();
    final accountKey = _offlineAccountKey(name);
    final saved = await secure.read(key: accountKey);
    if (saved == null) throw _invalidOfflineLogin();
    late Map<String, dynamic> record;
    late List<int> salt;
    late List<int> expected;
    late int iterations;
    try {
      record = jsonDecode(saved) as Map<String, dynamic>;
      if (record['name'] is! String) throw const FormatException();
      salt = base64Decode(record['salt'] as String);
      expected = base64Decode(record['hash'] as String);
      iterations = record['iterations'] as int? ?? 120000;
      if (salt.length != 16 ||
          expected.length != 32 ||
          ![120000, passwordIterations].contains(iterations)) {
        throw const FormatException();
      }
    } catch (_) {
      throw const FormatException(
        'This local account could not be read. Do not clear app storage.',
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final lockedUntil = record['lockedUntil'] as int? ?? 0;
    if (lockedUntil > now) {
      throw const FormatException(
        'Too many attempts. Wait five minutes and try again.',
      );
    }
    final actual = await _passwordHash(password, salt, iterations);
    if (!_constantTimeEquals(actual, expected)) {
      final attempts = lockedUntil > 0
          ? 1
          : (record['failedAttempts'] as int? ?? 0) + 1;
      record['failedAttempts'] = attempts;
      record['lockedUntil'] = attempts >= 10 ? now + 5 * 60000 : 0;
      await secure.write(key: accountKey, value: jsonEncode(record));
      throw _invalidOfflineLogin();
    }
    final savedName = record['name'] as String;
    if (iterations != passwordIterations) {
      await secure.write(
        key: accountKey,
        value: await _offlinePasswordRecord(savedName, password),
      );
    } else if (record.containsKey('failedAttempts')) {
      record.remove('failedAttempts');
      record.remove('lockedUntil');
      await secure.write(key: accountKey, value: jsonEncode(record));
    }
    return savedName;
  }

  static Future<void> updateOfflinePassword({
    required AuthSession session,
    required String currentPassword,
    required String newPassword,
  }) => withStorageLock(() async {
    _validateOfflinePassword(newPassword);
    final current = await _load();
    if (!session.isOffline ||
        current == null ||
        MoneyStore.scopeFor(current) != MoneyStore.scopeFor(session)) {
      throw const FormatException(
        'The signed-in account changed. Sign in again.',
      );
    }
    final name = await _verifyOfflinePassword(session.name, currentPassword);
    await secure.write(
      key: _offlineAccountKey(name),
      value: await _offlinePasswordRecord(name, newPassword),
    );
  });

  static String _validOfflineName(String name) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty || trimmedName.length > 80) {
      throw const FormatException('Enter a user name of 1–80 characters.');
    }
    if (RegExp(r'[\u0000-\u001F\u007F]').hasMatch(trimmedName)) {
      throw const FormatException('User name contains unsupported characters.');
    }
    return trimmedName;
  }

  static void _validateOfflinePassword(String password) {
    if (password.length < 12 || password.length > 128) {
      throw const FormatException('Use a password of 12–128 characters.');
    }
  }

  static String _offlineAccountKey(String name) =>
      '$offlineAccountPrefix${digest.sha256.convert(utf8.encode(name.trim().toLowerCase()))}';

  static Future<List<int>> _passwordHash(
    String password,
    List<int> salt,
    int iterations,
  ) async => (await Pbkdf2.hmacSha256(
    iterations: iterations,
    bits: 256,
  ).deriveKeyFromPassword(password: password, nonce: salt)).extractBytes();

  static FormatException _invalidOfflineLogin() =>
      const FormatException('Username or password is incorrect.');

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  static Future<AuthSession> _offlineSession(String name) async {
    var id = await secure.read(key: offlineIdKey);
    if (id == null || !RegExp(r'^offline-[a-f0-9-]{36}$').hasMatch(id)) {
      id = 'offline-${const Uuid().v4()}';
      await secure.write(key: offlineIdKey, value: id);
    }
    return AuthSession(
      name: name,
      backendUrl: BackendConfig.offlineUrl,
      id: id,
    );
  }

  static Future<void> _save(AuthSession session) async {
    await secure.write(key: sessionKey, value: jsonEncode(session.toJson()));
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(passwordKey);
    await prefs.remove(userKey);
  }

  static Future<void> clear() => withStorageLock(_clear);

  static Future<void> _clear() async {
    await secure.delete(key: sessionKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(passwordKey);
    await prefs.remove(userKey);
  }

  static Future<AuthSession> requireCurrent(AuthSession expected) async {
    final current = await load();
    if (current == null ||
        current.id.isEmpty ||
        MoneyStore.scopeFor(current) != MoneyStore.scopeFor(expected)) {
      throw const FormatException(
        'The signed-in account changed in another window. Reopen the app before continuing.',
      );
    }
    return current;
  }

  static Future<void> saveIfCurrent(AuthSession next, AuthSession expected) =>
      withStorageLock(() async {
        final current = await _load();
        if (current == null ||
            current.token != expected.token ||
            MoneyStore.scopeFor(current) != MoneyStore.scopeFor(expected)) {
          throw const FormatException(
            'The signed-in account changed. Sign in again.',
          );
        }
        await _save(next);
      });

  static Future<List<AuthSession>> pendingLogouts() async =>
      (jsonDecode(await secure.read(key: pendingLogoutKey) ?? '[]') as List)
          .map((v) => AuthSession.fromJson(Map<String, dynamic>.from(v as Map)))
          .toList();

  static Future<void> signOutLocally(AuthSession expected) =>
      withStorageLock(() async {
        final current = await _load();
        final sameAccount =
            current != null &&
            MoneyStore.scopeFor(current) == MoneyStore.scopeFor(expected);
        final target = sameAccount ? current : expected;
        final pending = await pendingLogouts();
        if (target.token != null &&
            !pending.any(
              (s) =>
                  s.token == target.token && s.backendUrl == target.backendUrl,
            )) {
          pending.add(target);
          await secure.write(
            key: pendingLogoutKey,
            value: jsonEncode(pending.map((s) => s.toJson()).toList()),
          );
        }
        if (sameAccount) {
          await _clear();
        }
      });

  static Future<void> finishLogout(AuthSession session) =>
      withStorageLock(() async {
        final pending = await pendingLogouts();
        pending.removeWhere(
          (s) => s.token == session.token && s.backendUrl == session.backendUrl,
        );
        await secure.write(
          key: pendingLogoutKey,
          value: jsonEncode(pending.map((s) => s.toJson()).toList()),
        );
      });
}

class MoneyStore {
  MoneyStore._(this._prefs, this.session, this.scope, this._key, this._data);
  static const transactionsKey = 'money-manager-transactions-v2';
  static const legacyTransactionsKey = 'money-manager-transactions-v1';
  static const recurringKey = 'money-manager-recurring-v1';
  static final _cipher = AesGcm.with256bits();
  final SharedPreferences _prefs;
  final AuthSession session;
  final String scope;
  final SecretKey _key;
  MoneySyncData _data;
  String get storageKey => 'money-manager-encrypted-$scope';

  static String _oldScopeFor(AuthSession session) => digest.sha256
      .convert(
        utf8.encode(
          '${Uri.parse(session.backendUrl).host.toLowerCase()}:${Uri.parse(session.backendUrl).port}\n${session.name.trim().toLowerCase()}',
        ),
      )
      .toString();

  static String scopeFor(AuthSession session) => digest.sha256
      .convert(
        utf8.encode('${_oldScopeFor(session)}\naccount-id:${session.id}'),
      )
      .toString();

  static Future<MoneyStore> load({AuthSession? session}) async {
    session ??= await AuthCache.load();
    if (session == null || session.id.isEmpty) {
      throw const FormatException(
        'Sign in again to open your account. Older data has been preserved for recovery.',
      );
    }
    final signed = session;
    final store = await withStorageLock(() => _load(signed));
    await store.applyDueRecurringExpenses();
    return store;
  }

  static Future<MoneyStore> _load(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final scope = scopeFor(session);
    final keyName = 'money-manager-data-key-$scope';
    final keyText = await AuthCache.secure.read(key: keyName);
    final raw = await snapshots.readSnapshot(
      prefs,
      'money-manager-encrypted-$scope',
    );
    if (keyText == null && raw != null) {
      throw const FormatException(
        'This device cannot unlock saved data. Restore its secure storage before continuing.',
      );
    }
    final key = keyText == null
        ? await _cipher.newSecretKey()
        : SecretKey(base64Decode(keyText));
    if (keyText == null) {
      await AuthCache.secure.write(
        key: keyName,
        value: base64Encode(await key.extractBytes()),
      );
    }
    var data = const MoneySyncData([], []);
    if (raw != null) {
      try {
        final box = SecretBox.fromConcatenation(
          base64Decode(raw),
          nonceLength: 12,
          macLength: 16,
        );
        final bytes = await _cipher.decrypt(
          box,
          secretKey: key,
          aad: utf8.encode(scope),
        );
        data = decodeData(
          jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
        );
      } catch (_) {
        throw const FormatException(
          'Saved data could not be read. It has been preserved; do not clear app storage.',
        );
      }
    }
    return MoneyStore._(prefs, session, scope, key, data);
  }

  // Recovery is always explicit: neither a username nor an old cached login
  // proves who owns data written by versions that shared account storage.
  Future<MoneySyncData> readRecoveryData({required bool confirmed}) async {
    if (!confirmed) {
      throw const FormatException(
        'Confirm ownership before recovering older data.',
      );
    }
    await AuthCache.requireCurrent(session);
    return withStorageLock(() async {
      await _prefs.reload();
      var data = decodeData({
        'transactions': jsonDecode(
          _prefs.getString(transactionsKey) ??
              _prefs.getString(legacyTransactionsKey) ??
              '[]',
        ),
        'recurring': jsonDecode(_prefs.getString(recurringKey) ?? '[]'),
      });
      final oldScope = _oldScopeFor(session);
      final raw = _prefs.getString('money-manager-encrypted-$oldScope');
      if (raw != null) {
        final keyText = await AuthCache.secure.read(
          key: 'money-manager-data-key-$oldScope',
        );
        if (keyText == null) {
          throw const FormatException(
            'Older data cannot be unlocked. Its original copy has been preserved.',
          );
        }
        final bytes = await _cipher.decrypt(
          SecretBox.fromConcatenation(
            base64Decode(raw),
            nonceLength: 12,
            macLength: 16,
          ),
          secretKey: SecretKey(base64Decode(keyText)),
          aad: utf8.encode(oldScope),
        );
        data = mergeData(
          data,
          decodeData(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>),
        );
      }
      return data;
    });
  }

  Future<bool> hasRecoveryData() async {
    await _prefs.reload();
    return [
      transactionsKey,
      legacyTransactionsKey,
      recurringKey,
      'money-manager-encrypted-${_oldScopeFor(session)}',
    ].any(_prefs.containsKey);
  }

  static MoneySyncData decodeData(Map<String, dynamic> json) => MoneySyncData(
    (json['transactions'] as List)
        .map((v) => Tx.fromJson(Map<String, Object?>.from(v as Map)))
        .toList(),
    (json['recurring'] as List)
        .map(
          (v) => RecurringExpense.fromJson(Map<String, Object?>.from(v as Map)),
        )
        .toList(),
    deletedTransactions: List<String>.from(
      json['deletedTransactions'] as List? ?? [],
    ),
    deletedRecurring: List<String>.from(
      json['deletedRecurring'] as List? ?? [],
    ),
  );
  static Map<String, Object?> encodeData(MoneySyncData data) => {
    'transactions': data.transactions.map((v) => v.toJson()).toList(),
    'recurring': data.recurring.map((v) => v.toJson()).toList(),
    'deletedTransactions': data.deletedTransactions,
    'deletedRecurring': data.deletedRecurring,
  };
  List<Tx> transactions() =>
      [..._data.transactions]..sort((a, b) => b.date.compareTo(a.date));
  List<RecurringExpense> recurring() => [..._data.recurring];
  MoneySyncData get snapshot => MoneySyncData(
    transactions(),
    recurring(),
    deletedTransactions: [..._data.deletedTransactions],
    deletedRecurring: [..._data.deletedRecurring],
  );

  Future<void> _persist(MoneySyncData data) async {
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(encodeData(data))),
      secretKey: _key,
      aad: utf8.encode(scope),
    );
    if (!await snapshots.writeSnapshot(
      _prefs,
      storageKey,
      base64Encode(box.concatenation()),
    )) {
      throw const FormatException('Could not save data. Please try again.');
    }
    _data = data;
  }

  Future<void> _change(
    MoneySyncData Function(MoneySyncData) change,
  ) => withStorageLock(() async {
    // Reload inside the shared lock so every writer starts from committed data.
    final latest = await _load(session);
    await _persist(change(latest._data));
  });

  Future<void> refresh() => withStorageLock(() async {
    _data = (await _load(session))._data;
  });

  Future<void> saveTransactions(List<Tx> items) => _change(
    (d) => MoneySyncData(
      [...items],
      d.recurring,
      deletedTransactions: d.deletedTransactions,
      deletedRecurring: d.deletedRecurring,
    ),
  );
  Future<void> saveRecurring(List<RecurringExpense> items) => _change(
    (d) => MoneySyncData(
      d.transactions,
      [...items],
      deletedTransactions: d.deletedTransactions,
      deletedRecurring: d.deletedRecurring,
    ),
  );
  Future<void> addExpense(Tx tx) => addEntry(tx);
  Future<void> addEntry(Tx tx, [RecurringExpense? rule]) => _change(
    (d) => MoneySyncData(
      [...d.transactions.where((t) => t.id != tx.id), tx],
      [...d.recurring, ?rule],
      deletedTransactions: d.deletedTransactions,
      deletedRecurring: d.deletedRecurring,
    ),
  );
  Future<void> addRecurring(RecurringExpense item) => _change(
    (d) => MoneySyncData(
      d.transactions,
      [...d.recurring.where((r) => r.id != item.id), item],
      deletedTransactions: d.deletedTransactions,
      deletedRecurring: d.deletedRecurring,
    ),
  );
  Future<void> restoreTransaction(Tx tx) =>
      addExpense(Tx.fromJson({...tx.toJson(), 'id': const Uuid().v4()}));
  Future<void> removeTransaction(String id) => _change(
    (d) => MoneySyncData(
      d.transactions.where((t) => t.id != id).toList(),
      d.recurring,
      deletedTransactions: {...d.deletedTransactions, id}.toList(),
      deletedRecurring: d.deletedRecurring,
    ),
  );
  Future<void> removeRecurring(String id) => _change(
    (d) => MoneySyncData(
      d.transactions,
      d.recurring.where((r) => r.id != id).toList(),
      deletedTransactions: d.deletedTransactions,
      deletedRecurring: {...d.deletedRecurring, id}.toList(),
    ),
  );
  Future<int> removeTransactionsWhere(bool Function(Tx) predicate) async {
    var count = 0;
    await _change((d) {
      final removed = d.transactions.where(predicate).map((t) => t.id).toSet();
      count = removed.length;
      return MoneySyncData(
        d.transactions.where((t) => !removed.contains(t.id)).toList(),
        d.recurring,
        deletedTransactions: {...d.deletedTransactions, ...removed}.toList(),
        deletedRecurring: d.deletedRecurring,
      );
    });
    return count;
  }

  // Merge with the current local state, including changes made while a request
  // was in flight. Deletions always win; Undo creates a new transaction ID.
  Future<void> replaceAll(MoneySyncData incoming) =>
      _change((d) => mergeData(d, incoming));

  static MoneySyncData mergeData(MoneySyncData d, MoneySyncData incoming) {
    final deletedTx = {
      ...d.deletedTransactions,
      ...incoming.deletedTransactions,
    };
    final deletedRules = {...d.deletedRecurring, ...incoming.deletedRecurring};
    // Incoming is the authoritative server copy when timestamps tie.
    final txs = {for (final tx in incoming.transactions) tx.id: tx};
    for (final tx in d.transactions) {
      if (txs[tx.id] == null || tx.date.isAfter(txs[tx.id]!.date)) {
        txs[tx.id] = tx;
      }
    }
    final rules = {for (final rule in incoming.recurring) rule.id: rule};
    for (final rule in d.recurring) {
      if (rules[rule.id] == null ||
          rule.lastAppliedAt.isAfter(rules[rule.id]!.lastAppliedAt)) {
        rules[rule.id] = rule;
      }
    }
    return MoneySyncData(
      txs.values.where((t) => !deletedTx.contains(t.id)).toList(),
      rules.values.where((r) => !deletedRules.contains(r.id)).toList(),
      deletedTransactions: deletedTx.toList(),
      deletedRecurring: deletedRules.toList(),
    );
  }

  Future<void> applyDueRecurringExpenses() => _change((d) {
    final now = DateTime.now();
    final txs = {for (final tx in d.transactions) tx.id: tx};
    final rules = [...d.recurring];
    for (var i = 0; i < rules.length; i++) {
      final rule = rules[i];
      if (!rule.active) continue;
      if (rule.lastAppliedAt.year < 2000) {
        throw const FormatException(
          'A scheduled expense has an invalid start date. Saved data was preserved.',
        );
      }
      var last = rule.lastAppliedAt;
      var due = _nextDueAfter(rule, last);
      while (!due.isAfter(now)) {
        final id = '${rule.id}-${due.millisecondsSinceEpoch}';
        if (!d.deletedTransactions.contains(id)) {
          txs[id] = Tx(
            id: id,
            title: rule.title,
            note: rule.frequency == RecurringFrequency.daily
                ? 'Daily recurring expense'
                : 'Monthly recurring expense',
            category: rule.category,
            amount: rule.amount,
            date: due,
            icon: categoryByName(rule.category).icon.codePoint,
          );
        }
        if (txs.length > 20000) {
          throw const FormatException(
            'Too many scheduled expenses to apply at once. Saved data was preserved.',
          );
        }
        last = due;
        due = _nextDueAfter(rule, due);
      }
      rules[i] = rule.copyWith(lastAppliedAt: last);
    }
    return MoneySyncData(
      txs.values.toList(),
      rules,
      deletedTransactions: d.deletedTransactions,
      deletedRecurring: d.deletedRecurring,
    );
  });
  static DateTime _nextDueAfter(RecurringExpense rule, DateTime after) {
    if (rule.frequency == RecurringFrequency.daily) {
      return DateTime(after.year, after.month, after.day + 1);
    }
    DateTime monthly(int year, int month) => DateTime(
      year,
      month,
      rule.dayOfMonth.clamp(1, DateTime(year, month + 1, 0).day),
    );
    final candidate = monthly(after.year, after.month);
    return candidate.isAfter(after)
        ? candidate
        : monthly(after.year, after.month + 1);
  }
}
