import 'dart:convert';

enum ConnectionMode { demo, network, bluetooth }

extension ConnectionModeLabel on ConnectionMode {
  String get label => switch (this) {
    ConnectionMode.demo => 'Not connected',
    ConnectionMode.network => 'Wi-Fi',
    ConnectionMode.bluetooth => 'Bluetooth',
  };
}

class Notice {
  const Notice({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.priority = 'normal',
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final String priority;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'createdAt': createdAt.toIso8601String(),
    'priority': priority,
  };

  factory Notice.fromJson(Map<String, dynamic> json) => Notice(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? 'Notification',
    body: json['body'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    priority: json['priority'] as String? ?? 'normal',
  );
}

class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.createdAt,
    this.dueAt,
    this.done = false,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime? dueAt;
  final bool done;

  TaskItem copyWith({bool? done}) => TaskItem(
    id: id,
    title: title,
    createdAt: createdAt,
    dueAt: dueAt,
    done: done ?? this.done,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'dueAt': dueAt?.toIso8601String(),
    'done': done,
  };

  factory TaskItem.fromJson(Map<String, dynamic> json) => TaskItem(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? 'Task',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    dueAt: DateTime.tryParse(json['dueAt'] as String? ?? ''),
    done: json['done'] as bool? ?? false,
  );
}

class DeviceStatus {
  const DeviceStatus({
    required this.connected,
    required this.mode,
    this.ip = '',
    this.ssid = '',
    this.deviceName = 'ESP32-NavRide',
    this.firmware = '',
    this.setup = false,
  });

  final bool connected;
  final String mode;
  final String ip;
  final String ssid;
  final String deviceName;
  final String firmware;
  final bool setup;

  factory DeviceStatus.fromJson(Map<String, dynamic> json) => DeviceStatus(
    connected: json['connected'] as bool? ?? false,
    mode: json['mode'] as String? ?? 'setup',
    ip: json['ip'] as String? ?? '',
    ssid: json['ssid'] as String? ?? '',
    deviceName: json['deviceName'] as String? ?? 'ESP32-NavRide',
    firmware: json['firmware'] as String? ?? '',
    setup: json['setup'] as bool? ?? false,
  );
}

class NavRideConfig {
  const NavRideConfig({
    this.mode = ConnectionMode.demo,
    this.baseUrl = 'http://192.168.4.1',
    this.bluetoothId = '',
    this.updateBaseUrl = '',
  });

  final ConnectionMode mode;
  final String baseUrl;
  final String bluetoothId;
  final String updateBaseUrl;

  NavRideConfig copyWith({
    ConnectionMode? mode,
    String? baseUrl,
    String? bluetoothId,
    String? updateBaseUrl,
  }) => NavRideConfig(
    mode: mode ?? this.mode,
    baseUrl: baseUrl ?? this.baseUrl,
    bluetoothId: bluetoothId ?? this.bluetoothId,
    updateBaseUrl: updateBaseUrl ?? this.updateBaseUrl,
  );

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'baseUrl': baseUrl,
    'bluetoothId': bluetoothId,
    'updateBaseUrl': updateBaseUrl,
  };

  factory NavRideConfig.fromJson(Map<String, dynamic> json) => NavRideConfig(
    mode: ConnectionMode.values.firstWhere(
      (value) => value.name == json['mode'],
      orElse: () => ConnectionMode.demo,
    ),
    baseUrl: json['baseUrl'] as String? ?? 'http://192.168.4.1',
    bluetoothId: json['bluetoothId'] as String? ?? '',
    updateBaseUrl: json['updateBaseUrl'] as String? ?? '',
  );
}

class NavRideSnapshot {
  const NavRideSnapshot({
    required this.profileName,
    required this.notices,
    required this.tasks,
    required this.config,
  });

  final String profileName;
  final List<Notice> notices;
  final List<TaskItem> tasks;
  final NavRideConfig config;

  String encode() => jsonEncode({
    'profileName': profileName,
    'notices': notices.map((item) => item.toJson()).toList(),
    'tasks': tasks.map((item) => item.toJson()).toList(),
    'config': config.toJson(),
  });

  factory NavRideSnapshot.decode(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    return NavRideSnapshot(
      profileName: json['profileName'] as String? ?? 'You',
      notices: (json['notices'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Notice.fromJson)
          .toList(),
      tasks: (json['tasks'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(TaskItem.fromJson)
          .toList(),
      config: NavRideConfig.fromJson(
        json['config'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}
