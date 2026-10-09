import 'package:flutter/material.dart';

enum TxType { income, expense }

enum RecurringFrequency { daily, monthly }

@immutable
class MoneyCategory {
  const MoneyCategory(this.name, this.icon, this.color);

  final String name;
  final IconData icon;
  final Color color;
}

const moneyCategories = <MoneyCategory>[
  MoneyCategory('Food', Icons.restaurant, Color(0xFFCDF0B4)),
  MoneyCategory('Shopping', Icons.shopping_bag, Color(0xFFC4E7D4)),
  MoneyCategory('Bills', Icons.receipt_long, Color(0xFFE5F4B7)),
  MoneyCategory('Fun', Icons.movie, Color(0xFFE8F6D8)),
  MoneyCategory('Daily', Icons.today, Color(0xFFD9F0DD)),
  MoneyCategory('Monthly', Icons.calendar_month, Color(0xFFD3EDC6)),
  MoneyCategory('Income', Icons.savings, Color(0xFFBDE8AE)),
];

MoneyCategory categoryByName(String name) => moneyCategories.firstWhere(
  (category) => category.name == name,
  orElse: () => moneyCategories.first,
);

@immutable
class Tx {
  const Tx({
    required this.id,
    required this.title,
    this.note = '',
    required this.category,
    required this.amount,
    required this.date,
    this.type = TxType.expense,
    this.icon = 0xf2ef,
  });

  final String id;
  final String title;
  final String note;
  final String category;
  final int amount;
  final DateTime date;
  final TxType type;
  final int icon;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'note': note,
    'category': category,
    'amount': amount,
    'date': date.toIso8601String(),
    'type': type.name,
    'icon': icon,
  };

  factory Tx.fromJson(Map<String, Object?> json) => Tx(
    id: json['id'] as String,
    title: json['title'] as String,
    note: json['note'] as String? ?? '',
    category: json['category'] as String,
    amount: (json['amount'] as num).toInt(),
    date: DateTime.parse(json['date'] as String),
    type: json['type'] == 'income' ? TxType.income : TxType.expense,
    icon: (json['icon'] as num?)?.toInt() ?? 0xf2ef,
  );
}

@immutable
class RecurringExpense {
  const RecurringExpense({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.frequency,
    this.dayOfMonth = 1,
    required this.lastAppliedAt,
    this.active = true,
  });

  final String id;
  final String title;
  final int amount;
  final String category;
  final RecurringFrequency frequency;
  final int dayOfMonth;
  final DateTime lastAppliedAt;
  final bool active;

  RecurringExpense copyWith({DateTime? lastAppliedAt, bool? active}) =>
      RecurringExpense(
        id: id,
        title: title,
        amount: amount,
        category: category,
        frequency: frequency,
        dayOfMonth: dayOfMonth,
        lastAppliedAt: lastAppliedAt ?? this.lastAppliedAt,
        active: active ?? this.active,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'amount': amount,
    'category': category,
    'frequency': frequency.name,
    'dayOfMonth': dayOfMonth,
    'lastAppliedAt': lastAppliedAt.toIso8601String(),
    'active': active,
  };

  factory RecurringExpense.fromJson(Map<String, Object?> json) =>
      RecurringExpense(
        id: json['id'] as String,
        title: json['title'] as String,
        amount: (json['amount'] as num).toInt(),
        category: json['category'] as String,
        frequency: json['frequency'] == 'monthly'
            ? RecurringFrequency.monthly
            : RecurringFrequency.daily,
        dayOfMonth: (json['dayOfMonth'] as num?)?.toInt() ?? 1,
        lastAppliedAt: DateTime.parse(json['lastAppliedAt'] as String),
        active: json['active'] as bool? ?? true,
      );
}

@immutable
class MoneySyncData {
  const MoneySyncData(
    this.transactions,
    this.recurring, {
    this.deletedTransactions = const [],
    this.deletedRecurring = const [],
  });

  final List<Tx> transactions;
  final List<RecurringExpense> recurring;
  final List<String> deletedTransactions;
  final List<String> deletedRecurring;
}

class AuthSession {
  const AuthSession({
    required this.name,
    required this.backendUrl,
    this.id = '',
    this.token,
  });
  final String name;
  final String backendUrl;
  final String id;
  final String? token;

  bool get isOffline => token == null && id.startsWith('offline-');

  Map<String, Object?> toJson() => {
    'name': name,
    'backendUrl': backendUrl,
    'id': id,
    'token': token,
  };
  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    name: json['name'] as String,
    backendUrl: json['backendUrl'] as String,
    id: json['id'] as String? ?? '',
    token: json['token'] as String?,
  );
}
