import 'checkin.dart';

enum SyncOperationType { upsertCheckIn, deleteCheckIn }

class SyncOperation {
  const SyncOperation({
    required this.id,
    required this.checkInId,
    required this.type,
    required this.queuedAt,
    this.attempts = 0,
    this.lastError = '',
  });

  final String id;
  final String checkInId;
  final SyncOperationType type;
  final int queuedAt;
  final int attempts;
  final String lastError;

  SyncOperation copyWith({int? attempts, String? lastError}) => SyncOperation(
    id: id,
    checkInId: checkInId,
    type: type,
    queuedAt: queuedAt,
    attempts: attempts ?? this.attempts,
    lastError: lastError ?? this.lastError,
  );

  factory SyncOperation.fromJson(Map<String, dynamic> json) => SyncOperation(
    id: json['id']?.toString() ?? '',
    checkInId: json['checkInId']?.toString() ?? '',
    type: SyncOperationType.values.firstWhere(
      (value) => value.name == json['type'],
      orElse: () => SyncOperationType.upsertCheckIn,
    ),
    queuedAt: (json['queuedAt'] as num?)?.toInt() ?? 0,
    attempts: (json['attempts'] as num?)?.toInt() ?? 0,
    lastError: json['lastError']?.toString() ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'checkInId': checkInId,
    'type': type.name,
    'queuedAt': queuedAt,
    'attempts': attempts,
    'lastError': lastError,
  };
}

class SyncConflict {
  const SyncConflict({
    required this.checkInId,
    required this.local,
    required this.remote,
    required this.detectedAt,
  });

  final String checkInId;
  final CheckIn local;
  final CheckIn remote;
  final int detectedAt;

  factory SyncConflict.fromJson(Map<String, dynamic> json) => SyncConflict(
    checkInId: json['checkInId']?.toString() ?? '',
    local: CheckIn.fromJson(Map<String, dynamic>.from(json['local'] as Map)),
    remote: CheckIn.fromJson(Map<String, dynamic>.from(json['remote'] as Map)),
    detectedAt: (json['detectedAt'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'checkInId': checkInId,
    'local': local.toJson(),
    'remote': remote.toJson(),
    'detectedAt': detectedAt,
  };
}
