import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class BackendConfig {
  static const defaultUrl = 'http://192.168.1.141:3002';
  static const legacyDefaultUrl = 'http://127.0.0.1:3000';
  static const key = 'money-manager-backend-url';

  static Future<String> loadUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(key)?.trim();
    if (value == null || value.isEmpty || value == legacyDefaultUrl) {
      await prefs.setString(key, defaultUrl);
      return defaultUrl;
    }
    return value;
  }

  static Future<void> saveUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = value.trim().replaceAll(RegExp(r'/+$'), '');
    await prefs.setString(key, normalized.isEmpty ? defaultUrl : normalized);
  }
}

class AuthCache {
  static const userKey = 'vmc-auth-user';
  static const passwordKey = 'vmc-auth-password';

  static Future<(String, String)?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString(userKey);
    final password = prefs.getString(passwordKey);
    if (user == null || user.isEmpty || password == null || password.isEmpty) {
      return null;
    }
    return (user, password);
  }

  static Future<void> save(String user, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(userKey, user);
    await prefs.setString(passwordKey, password);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(userKey);
    await prefs.remove(passwordKey);
  }
}

class MoneyStore {
  MoneyStore._(this._prefs);

  static const transactionsKey = 'money-manager-transactions-v2';
  static const legacyTransactionsKey = 'money-manager-transactions-v1';
  static const recurringKey = 'money-manager-recurring-v1';

  final SharedPreferences _prefs;

  static Future<MoneyStore> load() async {
    final store = MoneyStore._(await SharedPreferences.getInstance());
    await store.applyDueRecurringExpenses();
    return store;
  }

  List<Tx> transactions() {
    final raw =
        _prefs.getString(transactionsKey) ??
        _prefs.getString(legacyTransactionsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final items = decoded
          .map((item) => Tx.fromJson(Map<String, Object?>.from(item as Map)))
          .toList();
      items.sort((a, b) => b.date.compareTo(a.date));
      return items;
    } catch (_) {
      return [];
    }
  }

  List<RecurringExpense> recurring() {
    final raw = _prefs.getString(recurringKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map(
            (item) => RecurringExpense.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveTransactions(List<Tx> items) async {
    items.sort((a, b) => b.date.compareTo(a.date));
    await _prefs.setString(
      transactionsKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> saveRecurring(List<RecurringExpense> items) => _prefs.setString(
    recurringKey,
    jsonEncode(items.map((item) => item.toJson()).toList()),
  );

  Future<void> addExpense(Tx tx) async {
    final items = transactions()..add(tx);
    await saveTransactions(items);
  }

  Future<void> addRecurring(RecurringExpense item) async {
    final items = recurring()..add(item);
    await saveRecurring(items);
  }

  Future<void> removeTransaction(String id) async {
    final items = transactions()..removeWhere((item) => item.id == id);
    await saveTransactions(items);
  }

  Future<void> removeRecurring(String id) async {
    final items = recurring()..removeWhere((item) => item.id == id);
    await saveRecurring(items);
  }

  Future<int> removeTransactionsWhere(bool Function(Tx) predicate) async {
    final items = transactions();
    final before = items.length;
    items.removeWhere(predicate);
    await saveTransactions(items);
    return before - items.length;
  }

  Future<void> replaceAll(MoneySyncData data) async {
    await saveTransactions([...data.transactions]);
    await saveRecurring([...data.recurring]);
  }

  Future<void> applyDueRecurringExpenses() async {
    final rules = recurring();
    if (rules.isEmpty) return;
    final now = DateTime.now();
    final txs = transactions();
    var changed = false;

    for (var index = 0; index < rules.length; index++) {
      final rule = rules[index];
      if (!rule.active) continue;
      var due = _nextDueAfter(rule, rule.lastAppliedAt);
      var lastApplied = rule.lastAppliedAt;
      while (!due.isAfter(now)) {
        txs.add(
          Tx(
            id: '${rule.id}-${due.millisecondsSinceEpoch}',
            title: rule.title,
            note: rule.frequency == RecurringFrequency.daily
                ? 'Daily recurring expense'
                : 'Monthly recurring expense',
            category: rule.category,
            amount: rule.amount,
            date: due,
            icon: categoryByName(rule.category).icon.codePoint,
          ),
        );
        lastApplied = due;
        due = _nextDueAfter(rule, due);
        changed = true;
      }
      if (lastApplied != rule.lastAppliedAt) {
        rules[index] = rule.copyWith(lastAppliedAt: lastApplied);
      }
    }

    if (changed) {
      await saveTransactions(txs);
      await saveRecurring(rules);
    }
  }

  DateTime _nextDueAfter(RecurringExpense rule, DateTime after) {
    if (rule.frequency == RecurringFrequency.daily) {
      final candidate = DateTime(
        after.year,
        after.month,
        after.day,
      ).add(const Duration(days: 1));
      return candidate;
    }
    var year = after.year;
    var month = after.month;
    var candidate = _monthlyDue(year, month, rule.dayOfMonth);
    if (!candidate.isAfter(after)) {
      month++;
      if (month == 13) {
        month = 1;
        year++;
      }
      candidate = _monthlyDue(year, month, rule.dayOfMonth);
    }
    return candidate;
  }

  DateTime _monthlyDue(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day.clamp(1, lastDay));
  }
}
