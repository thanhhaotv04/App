import 'dart:convert';

import '../models/checkin.dart';

class BackupService {
  const BackupService();

  Map<String, dynamic> buildExport(
    List<CheckIn> items, {
    DateTime? exportedAt,
  }) {
    return {
      'schema': 'vietnam-map-checkin.backup.v1',
      'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
      'total': items.length,
      'checkins': items.map((item) => item.toJson()).toList(),
    };
  }

  String encode(List<CheckIn> items, {DateTime? exportedAt}) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(buildExport(items, exportedAt: exportedAt));
  }

  List<CheckIn> decode(String raw) {
    final decoded = jsonDecode(raw);
    final Object? list = decoded is List
        ? decoded
        : decoded is Map<String, dynamic>
        ? decoded['checkins']
        : null;
    if (list is! List) {
      throw const FormatException('Backup does not contain check-ins.');
    }
    return list
        .whereType<Map<String, dynamic>>()
        .map(CheckIn.fromJson)
        .where((item) => item.id.isNotEmpty && item.city.isNotEmpty)
        .toList();
  }

  List<CheckIn> merge(List<CheckIn> current, List<CheckIn> imported) {
    final byId = <String, CheckIn>{};
    for (final item in [...current, ...imported]) {
      final previous = byId[item.id];
      if (previous == null || item.createdAt >= previous.createdAt) {
        byId[item.id] = item;
      }
    }
    return byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}
