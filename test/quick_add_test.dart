import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_reminder/src/app.dart';
import 'package:task_reminder/src/models.dart';

void main() {
  test('does not interpret email or partial tags as schedule commands', () {
    final parsed = parseQuickTask('Read email #workshop !highway');
    expect(parsed.title, 'Read email #workshop !highway');
    expect(parsed.dates, isEmpty);
    expect(parsed.iconKind, isNull);
    expect(parsed.priority, isNull);
  });
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

  test('parses no priority quick-add token', () {
    final parsed = parseQuickTask('Dọn phòng hôm nay !không');

    expect(parsed.title, 'Dọn phòng');
    expect(parsed.priority, TaskPriority.none);
  });

  test('parses multiple month days separated by commas', () {
    expect(parseMonthDays('15, 1, 15'), [1, 15]);
    expect(parseMonthDays('0, 15'), isEmpty);
    expect(parseMonthDays('abc'), isEmpty);
  });
}
