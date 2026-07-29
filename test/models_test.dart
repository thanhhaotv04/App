import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/src/models.dart';

void main() {
  test('transaction JSON remains compatible with the recovered APK schema', () {
    final original = Tx(
      id: 'tx-1',
      title: 'Lunch',
      note: 'Office meal',
      category: 'Food',
      amount: 65000,
      date: DateTime.utc(2026, 7, 29, 10),
      type: TxType.expense,
      icon: 0xf316,
    );

    final restored = Tx.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.amount, original.amount);
    expect(restored.date, original.date);
    expect(restored.type, TxType.expense);
    expect(restored.icon, 0xf316);
  });

  test('recurring JSON keeps recovered defaults for older data', () {
    final restored = RecurringExpense.fromJson({
      'id': 'daily-1',
      'title': 'Coffee',
      'amount': 25000,
      'category': 'Daily',
      'frequency': 'daily',
      'lastAppliedAt': '2026-07-29T00:00:00.000',
    });

    expect(restored.frequency, RecurringFrequency.daily);
    expect(restored.dayOfMonth, 1);
    expect(restored.active, isTrue);
  });
}
