import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_reminder/src/app.dart';
import 'package:task_reminder/src/models.dart';

void main() {
  test('parses convenient quick-add tokens without keeping them in title', () {
    final parsed = parseQuickTask('Nộp báo cáo mai 9:30 !cao ~45p #laptop');

    expect(parsed.title, 'Nộp báo cáo');
    expect(parsed.dates, hasLength(1));
    expect(
      parsed.dates.single,
      dateOnly(DateTime.now().add(const Duration(days: 1))),
    );
    expect(parsed.reminderTime, const TimeOfDay(hour: 9, minute: 30));
    expect(parsed.priority, TaskPriority.high);
    expect(parsed.estimateMinutes, 45);
    expect(parsed.iconKind, TaskIconKind.laptop);
  });
}
