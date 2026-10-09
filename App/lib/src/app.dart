import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'storage.dart';
import 'transport.dart';
import 'update_service.dart';

abstract final class NavRideColors {
  static const ink = Color(0xFF1D1D1F);
  static const muted = Color(0xFF626269);
  static const canvas = Color(0xFFF5F5F7);
  static const blue = Color(0xFF0066CC);
  static const blueSoft = Color(0xFFEAF2FC);
  static const green = Color(0xFF237747);
}

class NavRideApp extends StatefulWidget {
  const NavRideApp({super.key});
  @override
  State<NavRideApp> createState() => _NavRideAppState();
}

class _NavRideAppState extends State<NavRideApp> {
  NavRideSnapshot? _snapshot;
  String? _loadError;
  String? _loadWarning;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final storage = NavRideStorage();
      final snapshot = await storage.load();
      if (mounted) {
        setState(() {
          _snapshot = snapshot;
          _loadWarning = storage.recoveryWarning;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _loadError =
              'Could not read saved data. Your original data has not been replaced.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'ESP32-NavRide',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: NavRideColors.blue,
        primary: NavRideColors.blue,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: NavRideColors.canvas,
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: NavRideColors.ink,
        displayColor: NavRideColors.ink,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NavRideColors.canvas,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCDCDD2)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: NavRideColors.blueSoft,
        elevation: 0,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    ),
    home: _snapshot != null
        ? NavRideHome(snapshot: _snapshot!, recoveryWarning: _loadWarning)
        : Scaffold(
            body: Center(
              child: _loadError == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_loadError!),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
            ),
          ),
  );
}

class NavRideHome extends StatefulWidget {
  const NavRideHome({required this.snapshot, this.recoveryWarning, super.key});
  final NavRideSnapshot snapshot;
  final String? recoveryWarning;
  @override
  State<NavRideHome> createState() => _NavRideHomeState();
}

class _NavRideHomeState extends State<NavRideHome> with WidgetsBindingObserver {
  static const _navigationChannel = MethodChannel('esp32_navride/navigation');
  final _storage = NavRideStorage();
  final _ble = BluetoothTransport();
  late final TextEditingController _baseUrlController;
  late final TextEditingController _pairingPinController;
  late final TextEditingController _updateUrlController;
  final _wifiSsidController = TextEditingController();
  final _wifiPasswordController = TextEditingController();
  late List<Notice> _notices;
  late List<TaskItem> _tasks;
  late NavRideConfig _config;
  late String _profileName;
  late DeviceTransport _transport;
  DeviceStatus? _status;
  List<BleCandidate> _bleCandidates = [];
  Map<String, bool> _bridge = const {};
  Map<String, dynamic> _speed = const {};
  bool _speedBusy = false;
  Future<void>? _bridgeRefresh;
  Future<void> _pendingSave = Future<void>.value();
  Timer? _statusTimer;
  bool _healthPending = false;
  bool _pinRejected = false;
  int _statusGeneration = 0;
  int _page = 0;
  bool _showTasks = false;
  bool _connectionBusy = false;
  bool _navigationBusy = false;
  bool _sending = false;
  bool _editing = false;
  bool _updatingApp = false;
  bool _showWifiPassword = false;
  bool _showWifiSetup = false;
  bool _showPairingPin = false;
  bool _clearingData = false;
  double? _updateProgress;
  AppVersion? _appVersion;
  String? _deviceError;
  String? _recoveryWarning;

  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _usingNativeBle =>
      _android &&
      _config.mode == ConnectionMode.bluetooth &&
      _bridge['configured'] == true;
  bool get _listenerNeedsRestore =>
      _usingNativeBle &&
      _bridge['notificationAccess'] == true &&
      _bridge['listenerConnected'] == false;
  bool get _deviceBusy =>
      _connectionBusy || _navigationBusy || _sending || _clearingData;
  bool get _connected =>
      _config.mode != ConnectionMode.demo &&
      (_usingNativeBle
          ? _bridge['bleConnected'] == true
          : _status?.connected == true);
  bool get _canSend =>
      _config.mode != ConnectionMode.demo &&
      (_config.mode != ConnectionMode.network ||
          _config.pairingPin.length == 6) &&
      (_config.mode != ConnectionMode.bluetooth ||
          _config.bluetoothId.isNotEmpty) &&
      !_deviceBusy;
  bool get _navigationReady =>
      _usingNativeBle && _bridge['ready'] == true && _connected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notices = [...widget.snapshot.notices];
    _tasks = [...widget.snapshot.tasks];
    _config = widget.snapshot.config;
    _profileName = widget.snapshot.profileName;
    _recoveryWarning = widget.recoveryWarning;
    try {
      _transport = transportFor(_config, _ble);
    } on FormatException {
      _config = _config.copyWith(mode: ConnectionMode.demo);
      _transport = DemoTransport();
    }
    _baseUrlController = TextEditingController(text: _config.baseUrl);
    _pairingPinController = TextEditingController(text: _config.pairingPin);
    _updateUrlController = TextEditingController(text: _config.updateBaseUrl);
    unawaited(_refreshDevice());
    unawaited(_loadAppVersion());
    _startStatusTimer();
  }

  void _startStatusTimer() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_config.mode == ConnectionMode.network &&
          !_deviceBusy &&
          !_pinRejected &&
          _config.pairingPin.length == 6) {
        unawaited(_pollNetworkHealth());
      }
      if (!_android) return;
      if (!_deviceBusy && (_page == 0 || _usingNativeBle)) {
        unawaited(_refreshBridge());
        if (_page == 0 &&
            _config.mode == ConnectionMode.bluetooth &&
            !_usingNativeBle &&
            !_ble.isConnected) {
          unawaited(_refreshDevice());
        }
      }
    });
  }

  // Health polling must not disable buttons or overlap slower requests.
  Future<void> _pollNetworkHealth() async {
    if (_healthPending || !mounted) return;
    _healthPending = true;
    final transport = _transport;
    final generation = _statusGeneration;
    try {
      final status = await transport.health();
      if (mounted &&
          identical(transport, _transport) &&
          generation == _statusGeneration &&
          !_deviceBusy) {
        _pinRejected = false;
        setState(() {
          _status = status;
          _deviceError = null;
        });
      }
    } catch (error) {
      if (mounted &&
          identical(transport, _transport) &&
          generation == _statusGeneration &&
          !_deviceBusy) {
        if (error is PairingPinException) _pinRejected = true;
        setState(() {
          _status = null;
          _deviceError = _friendlyError(error);
        });
      }
    } finally {
      _healthPending = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startStatusTimer();
      unawaited(_refreshDevice());
    } else {
      _statusTimer?.cancel();
      setState(() {
        _showWifiPassword = false;
        _showPairingPin = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusTimer?.cancel();
    // The native bridge owns its own background BLE connection.
    unawaited(_transport.disconnect().catchError((Object _) {}));
    _baseUrlController.dispose();
    _pairingPinController.dispose();
    _updateUrlController.dispose();
    _wifiSsidController.dispose();
    _wifiPasswordController.dispose();
    super.dispose();
  }

  Future<void> _save() {
    final snapshot = NavRideSnapshot(
      profileName: _profileName,
      notices: _notices,
      tasks: _tasks,
      config: _config,
    );
    final save = _pendingSave.then((_) => _storage.save(snapshot));
    _pendingSave = save.catchError((Object _) {});
    return save;
  }

  Future<void> _refreshBridge() {
    if (!_android || !mounted) return Future<void>.value();
    return _bridgeRefresh ??= _readBridge().whenComplete(
      () => _bridgeRefresh = null,
    );
  }

  Future<void> _readBridge() async {
    try {
      final status = await _navigationChannel.invokeMapMethod<String, bool>(
        'getOsmAndBridgeStatus',
      );
      if (mounted && status != null && !mapEquals(status, _bridge)) {
        setState(() => _bridge = status);
      }
    } catch (_) {
      if (mounted && _bridge.isNotEmpty) setState(() => _bridge = const {});
    }
    try {
      final speed = await _navigationChannel.invokeMapMethod<String, dynamic>(
        'getSpeedStatus',
      );
      if (mounted && speed != null && !mapEquals(speed, _speed)) {
        setState(() => _speed = speed);
      }
    } catch (_) {
      if (mounted && _speed.isNotEmpty) setState(() => _speed = const {});
    }
  }

  Future<void> _toggleSpeed() async {
    if (_speedBusy || _clearingData) return;
    setState(() => _speedBusy = true);
    try {
      await _navigationChannel.invokeMethod<bool>(
        _speed['running'] == true ? 'stopSpeed' : 'startSpeed',
      );
      // The service starts asynchronously after the method channel returns.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await _refreshBridge();
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message ?? 'Could not start GPS speed.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GPS speed is unavailable. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _speedBusy = false);
    }
  }

  Future<void> _runConnection(Future<void> Function() action) async {
    if (_deviceBusy || !mounted) return;
    _statusGeneration++;
    setState(() {
      _connectionBusy = true;
      _deviceError = null;
    });
    try {
      await action();
    } catch (error) {
      if (error is PairingPinException) _pinRejected = true;
      if (mounted) {
        setState(() {
          _status = null;
          _deviceError = _friendlyError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _connectionBusy = false);
    }
  }

  Future<void> _refreshDevice() => _runConnection(_readDevice);

  Future<void> _readDevice() async {
    await _refreshBridge();
    if (!mounted || _config.mode == ConnectionMode.demo || _usingNativeBle) {
      return;
    }
    if (_config.mode == ConnectionMode.bluetooth && !_ble.isConnected) {
      if (_config.bluetoothId.isEmpty) return;
      await _ble.connectSaved(_config.bluetoothId);
    }
    final transport = _transport;
    final status = await transport.health();
    if (mounted && identical(transport, _transport)) {
      setState(() {
        _pinRejected = false;
        _status = status;
      });
    }
  }

  Future<void> _stopBridge() async {
    if (!_android || _bridge['configured'] != true) return;
    await _navigationChannel.invokeMethod<void>('disableOsmAndBridge');
    await _refreshBridge();
  }

  Future<void> _changeMode(ConnectionMode mode) async {
    if (mode == _config.mode) return;
    await _runConnection(() async {
      final url = mode == ConnectionMode.network
          ? normalizeEsp32BaseUrl(_baseUrlController.text)
          : _config.baseUrl;
      await _refreshBridge();
      // Hardware buttons can change mode before the app; allow reconnecting
      // with the new method even when the old connection no longer responds.
      if (_connected && mode != ConnectionMode.demo) {
        final command = {
          'command': 'set_mode',
          'mode': mode == ConnectionMode.bluetooth ? 'bluetooth' : 'wifi',
        };
        try {
          if (_usingNativeBle) {
            await _sendNative(command);
            await _waitForNativeAck('modeCommandConfirmed');
          } else {
            await _transport.send(command);
          }
        } catch (_) {
          if (mounted) {
            setState(
              () => _deviceError =
                  'If connection fails, select ${mode.label} using Button 3 on ESP32.',
            );
          }
        }
      }
      await _stopBridge();
      await _transport.disconnect();
      if (!mounted) return;
      setState(() {
        _config = _config.copyWith(mode: mode, baseUrl: url);
        _baseUrlController.text = url;
        _transport = transportFor(_config, _ble);
        _status = null;
        _bleCandidates = [];
      });
      await _save();
      if (mode == ConnectionMode.bluetooth && _config.bluetoothId.isNotEmpty) {
        if (_android && _bridge['notificationAccess'] == true) {
          await _navigationChannel.invokeMethod<void>('configureOsmAndBridge', {
            'deviceId': _config.bluetoothId,
          });
          await _refreshBridge();
        } else {
          await _readDevice();
        }
      }
    });
  }

  Future<void> _saveNetworkAddress() => _runConnection(() async {
    final url = normalizeEsp32BaseUrl(_baseUrlController.text);
    final pin = _pairingPinController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw const FormatException('Enter the 6-digit PIN from ESP32 Info.');
    }
    await _transport.disconnect();
    if (!mounted) return;
    setState(() {
      _config = _config.copyWith(baseUrl: url, pairingPin: pin);
      _pinRejected = false;
      _baseUrlController.text = url;
      _transport = transportFor(_config, _ble);
      _status = null;
    });
    await _save();
    await _readDevice();
  });

  Future<void> _scanBle() => _runConnection(() async {
    setState(() => _bleCandidates = []);
    final candidates = await _ble.scan();
    if (!mounted) return;
    setState(() {
      _bleCandidates = candidates;
      if (candidates.isEmpty) {
        _deviceError =
            'No ESP32 found. Press Button 2 until BLT flashes, then scan again.';
      }
    });
  });

  Future<void> _connectBle(BleCandidate candidate) => _runConnection(() async {
    await _stopBridge();
    await _ble.connect(candidate.device);
    final status = await _ble.health();
    if (!mounted) return;
    setState(() {
      _config = _config.copyWith(
        mode: ConnectionMode.bluetooth,
        bluetoothId: candidate.id,
      );
      _transport = _ble;
      _status = status;
      _bleCandidates = [];
    });
    await _save();
    await _refreshBridge();
    // If notification access is already granted, hand the BLE link directly
    // to the background navigation bridge; no second setup tap is needed.
    if (_android && _bridge['notificationAccess'] == true) {
      await _ble.disconnect();
      if (mounted) setState(() => _status = null);
      await _navigationChannel.invokeMethod<void>('configureOsmAndBridge', {
        'deviceId': candidate.id,
      });
      await _refreshBridge();
    }
    if (mounted) setState(() => _page = 0);
  });

  Future<void> _sendNative(Map<String, dynamic> command) async {
    final encoded = encodeDeviceCommand({
      ...command,
      'requestId': nextDeviceRequestId(),
    }, maxBytes: 180);
    final queued = await _navigationChannel.invokeMethod<bool>(
      'sendBleCommand',
      {'payload': encoded},
    );
    if (queued != true) {
      throw StateError('Could not send. Check the Bluetooth connection.');
    }
  }

  Future<void> _waitForNativeAck(String key) async {
    for (var attempt = 0; attempt < 25; attempt++) {
      if (!mounted) return;
      final status = await _navigationChannel.invokeMapMethod<String, bool>(
        'getOsmAndBridgeStatus',
      );
      if (status?[key] == true) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError(
      'No confirmation from ESP32. Check the connection and try again.',
    );
  }

  Future<void> _send(Map<String, dynamic> command) async {
    if (!_canSend) return;
    _statusGeneration++;
    setState(() => _sending = true);
    try {
      if (_config.mode == ConnectionMode.bluetooth) {
        // Use the largest ID so the preview also fits the final packet.
        final preview =
            jsonDecode(
                  encodeDeviceCommand({
                    ...command,
                    'requestId': 2147483647,
                  }, maxBytes: 180),
                )
                as Map<String, dynamic>;
        final shortened = ['title', 'body'].any(
          (key) =>
              command[key] is String &&
              preview[key] != toTftText(command[key] as String),
        );
        if (shortened) {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Message is too long for Bluetooth'),
              content: SingleChildScrollView(
                child: Text(
                  'Only the following text fits on this connection. Cancel to keep the full message, or send this shorter version.\n\n${preview['title']}\n${preview['body']}',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Send shorter version'),
                ),
              ],
            ),
          );
          if (confirmed != true || !mounted) return;
          command = {
            ...command,
            'title': preview['title'],
            'body': preview['body'],
          };
        }
      }
      await _refreshBridge();
      if (_usingNativeBle) {
        await _sendNative(command);
        await _waitForNativeAck('popupCommandConfirmed');
        _showMessage('ESP32 confirmed delivery.');
      } else {
        if (_config.mode == ConnectionMode.bluetooth && !_ble.isConnected) {
          await _ble.connectSaved(_config.bluetoothId);
        }
        await _transport.send(command);
        _showMessage('ESP32 confirmed delivery.');
      }
    } catch (error) {
      if (mounted && _config.mode == ConnectionMode.network) {
        setState(() {
          _status = null;
          _deviceError = _friendlyError(error);
        });
      }
      _showMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _configureBridge() async {
    if (!_android || _deviceBusy) return;
    setState(() => _navigationBusy = true);
    try {
      if (_config.mode != ConnectionMode.bluetooth ||
          _config.bluetoothId.isEmpty) {
        setState(() => _page = 2);
        return;
      }
      if (_bridge['configured'] != true ||
          _bridge['notificationAccess'] == true) {
        await _ble.disconnect();
        if (mounted) setState(() => _status = null);
        await _navigationChannel.invokeMethod<void>('configureOsmAndBridge', {
          'deviceId': _config.bluetoothId,
        });
      }
      await _refreshBridge();
      if (_bridge['notificationAccess'] != true) {
        await _navigationChannel.invokeMethod<void>(
          'openNotificationAccessSettings',
        );
      }
    } catch (error) {
      _showMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _navigationBusy = false);
    }
  }

  Future<void> _openOsmAnd() async {
    try {
      await _navigationChannel.invokeMethod<void>('openOsmAnd');
    } catch (error) {
      _showMessage(_friendlyError(error), error: true);
    }
  }

  Future<void> _navigationAction() async {
    if (!_android) {
      _showHelp();
      return;
    }
    if (_config.mode != ConnectionMode.bluetooth ||
        _config.bluetoothId.isEmpty) {
      setState(() => _page = 2);
      await _changeMode(ConnectionMode.bluetooth);
    } else if (_listenerNeedsRestore) {
      if (_deviceBusy) return;
      setState(() => _navigationBusy = true);
      try {
        await _navigationChannel.invokeMethod<void>(
          'recoverNavigationConnection',
        );
        await _refreshBridge();
      } catch (error) {
        _showMessage(_friendlyError(error), error: true);
      } finally {
        if (mounted) setState(() => _navigationBusy = false);
      }
    } else if (_bridge['osmandInstalled'] == false || _navigationReady) {
      await _openOsmAnd();
    } else {
      await _configureBridge();
    }
  }

  Future<void> _sendNavigationSample(String maneuver) async {
    if (!_navigationReady || _deviceBusy) return;
    setState(() => _navigationBusy = true);
    try {
      final queued = await _navigationChannel.invokeMethod<bool>(
        'sendOsmAndSample',
        {
          'maneuver': maneuver,
          'distanceMeters': 250,
          'streetName': 'Nguyen Hue',
        },
      );
      if (queued != true) {
        throw StateError('Could not send the sample. Reconnect ESP32.');
      }
      await _waitForNativeAck('lastNavigationConfirmed');
      await _refreshBridge();
      _showMessage('ESP32 received the 250 m navigation sample.');
    } catch (error) {
      _showMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _navigationBusy = false);
    }
  }

  Future<void> _setupWifi() => _runConnection(() async {
    final ssid = _wifiSsidController.text.trim();
    if (ssid.isEmpty) throw const FormatException('Enter a Wi-Fi name.');
    validateWifiCredentials(ssid, _wifiPasswordController.text);
    if (_config.mode == ConnectionMode.demo) {
      throw StateError('Connect ESP32 first.');
    }
    if (_usingNativeBle) {
      await _sendNative({
        'command': 'configure_wifi',
        'ssid': ssid,
        'password': _wifiPasswordController.text,
      });
      await _waitForNativeAck('wifiCommandConfirmed');
      await _stopBridge();
    } else {
      if (_config.mode == ConnectionMode.bluetooth && !_ble.isConnected) {
        await _ble.connectSaved(_config.bluetoothId);
      }
      await _transport.setupWifi(ssid, _wifiPasswordController.text);
    }
    await _transport.disconnect();
    if (!mounted) return;
    setState(() {
      _status = null;
      _config = _config.copyWith(mode: ConnectionMode.network);
      _transport = transportFor(_config, _ble);
      _wifiPasswordController.clear();
      _showWifiSetup = false;
    });
    await _save();
    _showMessage(
      'Wi-Fi saved. Press Button 3 → ESP32 Info to find the new IP, then enter it here.',
    );
  });

  Future<void> _loadAppVersion() async {
    if (!_android) return;
    try {
      final version = await AppUpdateService(
        baseUrl: 'http://127.0.0.1',
      ).currentVersion();
      if (mounted) setState(() => _appVersion = version);
    } catch (_) {
      /* No native version in a preview. */
    }
  }

  Future<void> _checkAndInstallUpdate() async {
    if (_updatingApp || _clearingData) return;
    String url;
    try {
      url = normalizeUpdateBaseUrl(_updateUrlController.text);
    } catch (error) {
      _showMessage(friendlyUpdateError(error), error: true);
      return;
    }
    setState(() {
      _updatingApp = true;
      _updateProgress = null;
      _config = _config.copyWith(updateBaseUrl: url);
      _updateUrlController.text = url;
    });
    try {
      await _save();
      if (!_android) {
        _showMessage('Server saved. Install updates on your Android phone.');
        return;
      }
      final service = AppUpdateService(baseUrl: url);
      final current = await service.currentVersion();
      if (mounted) setState(() => _appVersion = current);
      final info = await service.checkLatest(currentVersionCode: current.code);
      if (!info.available) {
        _showMessage('You are up to date.');
        return;
      }
      if (!mounted) return;
      final install = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Update ${info.versionName}'),
          content: SingleChildScrollView(
            child: Text(
              '${info.notes}\n\n${(info.sizeBytes / 1048576).toStringAsFixed(1)} MB',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Download and install'),
            ),
          ],
        ),
      );
      if (install != true) return;
      final path = await service.downloadApk(
        info,
        onProgress: (value) {
          if (mounted) setState(() => _updateProgress = value);
        },
      );
      await service.installApk(path);
    } catch (error) {
      _showMessage(friendlyUpdateError(error), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _updatingApp = false;
          _updateProgress = null;
        });
      }
    }
  }

  Future<bool> _editContent({
    List<Notice>? notices,
    List<TaskItem>? tasks,
  }) async {
    if (_editing || !mounted) return false;
    final oldNotices = _notices;
    final oldTasks = _tasks;
    setState(() {
      _editing = true;
      _notices = notices ?? _notices;
      _tasks = tasks ?? _tasks;
    });
    try {
      await _save();
      return true;
    } catch (_) {
      if (mounted) {
        setState(() {
          _notices = oldNotices;
          _tasks = oldTasks;
        });
      }
      _showMessage('Could not save. Please try again.', error: true);
      return false;
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _addContent({Notice? notice, TaskItem? taskItem}) async {
    if (_editing) return;
    final task = taskItem != null || (notice == null && _showTasks);
    final entry = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _ContentDialog(
        task: task,
        editing: notice != null || taskItem != null,
        title: notice?.title ?? taskItem?.title ?? '',
        body: notice?.body ?? '',
      ),
    );
    if (!mounted || entry == null) return;
    final now = DateTime.now();
    if (task) {
      await _editContent(
        tasks: taskItem != null
            ? _tasks
                  .map(
                    (item) => item.id == taskItem.id
                        ? item.copyWith(title: entry.$1)
                        : item,
                  )
                  .toList()
            : [
                TaskItem(
                  id: now.microsecondsSinceEpoch.toString(),
                  title: entry.$1,
                  createdAt: now,
                ),
                ..._tasks,
              ],
      );
    } else {
      await _editContent(
        notices: notice != null
            ? _notices
                  .map(
                    (item) => item.id == notice.id
                        ? Notice(
                            id: item.id,
                            title: entry.$1,
                            body: entry.$2,
                            createdAt: item.createdAt,
                            priority: item.priority,
                          )
                        : item,
                  )
                  .toList()
            : [
                Notice(
                  id: now.microsecondsSinceEpoch.toString(),
                  title: entry.$1,
                  body: entry.$2,
                  createdAt: now,
                ),
                ..._notices,
              ],
      );
    }
  }

  Future<void> _deleteNotice(Notice notice) async {
    if (await _editContent(
      notices: _notices.where((item) => item.id != notice.id).toList(),
    )) {
      _showMessage(
        'Notification deleted.',
        undo: () => unawaited(_editContent(notices: [notice, ..._notices])),
      );
    }
  }

  Future<void> _deleteTask(TaskItem task) async {
    if (await _editContent(
      tasks: _tasks.where((item) => item.id != task.id).toList(),
    )) {
      _showMessage(
        'Task deleted.',
        undo: () => unawaited(_editContent(tasks: [task, ..._tasks])),
      );
    }
  }

  Future<void> _clearLocalData() async {
    if (_deviceBusy || _editing || _updatingApp || _speedBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saved data?'),
        scrollable: true,
        content: const Text(
          'This stops GPS speed and navigation sharing, disconnects ESP32, '
          'and deletes saved content, connection settings, PINs and recovery copies from this app. '
          'Downloaded updates are also deleted on Android. This cannot be undone.\n\n'
          'Content and Wi-Fi saved on ESP32, Android permissions and Bluetooth pairings remain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete data'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _clearingData = true;
      _editing = true;
    });
    _statusTimer?.cancel();
    _statusGeneration++;
    try {
      await _pendingSave;
      await _bridgeRefresh;
      if (_android) {
        await _navigationChannel.invokeMethod<void>('clearLocalData');
      }
      await _transport.disconnect();
      await _storage.clear();
      if (!mounted) return;
      setState(() {
        _config = const NavRideConfig();
        _profileName = 'You';
        _transport = DemoTransport();
        _notices = [];
        _tasks = [];
        _status = null;
        _bridge = const {};
        _speed = const {};
        _bleCandidates = [];
        _deviceError = null;
        _recoveryWarning = null;
        _pinRejected = false;
        _baseUrlController.text = _config.baseUrl;
        _pairingPinController.clear();
        _updateUrlController.clear();
        _wifiSsidController.clear();
        _wifiPasswordController.clear();
        _showPairingPin = false;
        _showWifiPassword = false;
      });
      _showMessage('Saved data deleted. GPS speed and sharing are off.');
    } catch (_) {
      _showMessage('Could not delete all data. Please try again.', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _clearingData = false;
          _editing = false;
        });
        _startStatusTimer();
      }
    }
  }

  String _friendlyError(Object error) {
    final bleHint = bleConnectionRecoveryHint(error);
    if (bleHint != null) return bleHint;
    if (error is PlatformException) {
      return error.message ?? 'Could not complete the action. Try again.';
    }
    if (error is TimeoutException) {
      return 'ESP32 did not respond. Check the connection and try again.';
    }
    if (error is FormatException) return error.message;
    if (error is StateError) return error.message.toString();
    if (error is PairingPinException) return error.toString();
    return 'Could not reach ESP32. Check the connection and try again.';
  }

  void _showMessage(String message, {bool error = false, VoidCallback? undo}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        action: undo == null
            ? null
            : SnackBarAction(label: 'Undo', onPressed: undo),
      ),
    );
  }

  void _showHelp() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: const SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: _NavigationHelp(),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    const destinations = [
      NavigationDestination(
        icon: Icon(Icons.near_me_outlined),
        selectedIcon: Icon(Icons.near_me),
        label: 'Navigation',
      ),
      NavigationDestination(
        icon: Icon(Icons.inbox_outlined),
        selectedIcon: Icon(Icons.inbox),
        label: 'Content',
      ),
      NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: 'Settings',
      ),
    ];
    final page = switch (_page) {
      0 => _navigationPage(),
      1 => _contentPage(),
      _ => _settingsPage(),
    };
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              NavigationRail(
                selectedIndex: _page,
                backgroundColor: Colors.white,
                indicatorColor: NavRideColors.blueSoft,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: (value) => setState(() => _page = value),
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Icon(Icons.navigation, color: NavRideColors.blue),
                ),
                destinations: destinations
                    .map(
                      (item) => NavigationRailDestination(
                        icon: item.icon,
                        selectedIcon: item.selectedIcon,
                        label: Text(item.label),
                      ),
                    )
                    .toList(),
              ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: page,
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _page,
              onDestinationSelected: (value) => setState(() => _page = value),
              destinations: destinations,
            ),
    );
  }

  Widget _pageLayout(
    String title,
    String subtitle,
    List<Widget> children, {
    Widget? action,
  }) => ListView(
    key: PageStorageKey('page-$_page'),
    padding: EdgeInsets.fromLTRB(
      MediaQuery.sizeOf(context).width < 420 ? 16 : 24,
      24,
      MediaQuery.sizeOf(context).width < 420 ? 16 : 24,
      32,
    ),
    children: [
      if (_recoveryWarning != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(_recoveryWarning!),
        ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: NavRideColors.muted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          ?action,
        ],
      ),
      const SizedBox(height: 24),
      ...children,
    ],
  );

  String get _navigationTitle {
    if (!_android) return 'Directions on your display';
    if (!_navigationReady) return 'Get ready to ride';
    if (_bridge['osmandDataRecent'] != true) return 'Ready for directions';
    return _bridge['lastNavigationConfirmed'] == true
        ? 'Sending directions'
        : 'Waiting for ESP32';
  }

  String get _navigationDescription {
    if (!_android) {
      return 'Connect your Android phone to ESP32 for turn-by-turn directions from OsmAnd.';
    }
    if (_config.mode != ConnectionMode.bluetooth ||
        _config.bluetoothId.isEmpty) {
      return 'Connect ESP32 over Bluetooth to get started. No Wi-Fi needed on the road.';
    }
    if (_bridge['notificationAccess'] != true) {
      return 'Allow notification access so NavRide can receive directions and street names from OsmAnd.';
    }
    if (_listenerNeedsRestore) {
      return _bridge['listenerRecovering'] == true
          ? 'Reconnecting navigation in the background. This may take a few seconds.'
          : 'Notification access is already enabled. Tap Retry connection to restart the navigation connection.';
    }
    if (!_navigationReady) {
      return _bridge['bleConnected'] == true
          ? 'Check that OsmAnd is installed on your phone.'
          : 'Wait for automatic reconnection. If BLT stops flashing, press Button 2 on ESP32, then tap Reconnect ESP32.';
    }
    if (_bridge['osmandDataRecent'] != true) {
      return 'Open OsmAnd, choose a destination and start navigation.';
    }
    return _bridge['lastNavigationConfirmed'] == true
        ? 'ESP32 confirmed the latest directions from OsmAnd.'
        : 'Directions received from OsmAnd. Waiting for delivery confirmation from ESP32.';
  }

  String get _navigationButton {
    if (!_android) return 'Android setup';
    if (_config.mode != ConnectionMode.bluetooth ||
        _config.bluetoothId.isEmpty) {
      return 'Connect ESP32';
    }
    if (_bridge['osmandInstalled'] == false) return 'Check OsmAnd';
    if (_listenerNeedsRestore) {
      return _bridge['listenerRecovering'] == true
          ? 'Reconnecting…'
          : 'Retry connection';
    }
    if (_navigationReady) return 'Open OsmAnd';
    if (_bridge['notificationAccess'] != true) return 'Enable navigation';
    return 'Reconnect ESP32';
  }

  Widget _navigationPage() => _pageLayout(
    'Navigation',
    'ESP32-NavRide',
    [
      _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NavRideColors.blueSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.navigation_outlined,
                size: 40,
                color: NavRideColors.blue,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _navigationTitle,
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _navigationDescription,
              style: const TextStyle(
                color: NavRideColors.muted,
                fontSize: 16,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('navigation-primary'),
                onPressed: _deviceBusy || _bridge['listenerRecovering'] == true
                    ? null
                    : _navigationAction,
                icon: const Icon(Icons.arrow_forward),
                label: Text(_deviceBusy ? 'Connecting…' : _navigationButton),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Column(
          children: [
            _StatusRow(
              icon: Icons.memory_outlined,
              title: 'ESP32 display',
              detail: _connected
                  ? 'Connected · ${_config.mode.label}'
                  : 'Not connected',
              ready: _connected,
            ),
            const Divider(height: 1, indent: 56, endIndent: 20),
            _StatusRow(
              icon: Icons.alt_route,
              title: 'OsmAnd',
              detail: !_android
                  ? 'Available on Android'
                  : _bridge['aidlSubscribed'] == true
                  ? 'Navigation source connected'
                  : _bridge['ready'] == true
                  ? 'Notification fallback ready'
                  : 'Not ready',
              ready: _android && _bridge['ready'] == true,
            ),
          ],
        ),
      ),
      if (_deviceError != null) ...[
        const SizedBox(height: 16),
        _connectionError(),
      ],
      const SizedBox(height: 16),
      _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GPS speed',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '${_speed['running'] == true ? (_speed['kmh'] ?? '--') : '--'} km/h',
              key: const ValueKey('gps-speed-value'),
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              !_android
                  ? 'GPS speed requires an Android phone connected by Bluetooth.'
                  : _speed['running'] == true
                  ? _speed['kmh'] == null
                        ? '${_speed['message'] ?? 'Waiting for GPS'}'
                        : '${_speed['message'] ?? 'GPS speed active'} · ${_speed['delivered'] == true ? 'ESP32 receiving' : 'Waiting for ESP32'}'
                  : 'Uses phone GPS, including while OsmAnd is open. No internet needed. Start while parked.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('gps-speed-toggle'),
              onPressed:
                  !_android ||
                      _speedBusy ||
                      (_speed['running'] != true &&
                          (!_usingNativeBle || !_connected || _deviceBusy))
                  ? null
                  : _toggleSpeed,
              icon: Icon(_speed['running'] == true ? Icons.stop : Icons.speed),
              label: Text(
                _speedBusy
                    ? 'Please wait…'
                    : _speed['running'] == true
                    ? 'Stop GPS speed'
                    : 'Start GPS speed',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _showHelp,
          icon: const Icon(Icons.help_outline),
          label: const Text('OsmAnd and street name setup'),
        ),
      ),
      if (_android) ...[
        const SizedBox(height: 8),
        _Disclosure(
          title: 'Test display',
          icon: Icons.build_outlined,
          children: [
            const Text(
              'Send a Nguyen Hue · 250 m sample while parked. It clears after 15 seconds; real OsmAnd exit angles may differ.',
              style: TextStyle(color: NavRideColors.muted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('speed-sample'),
                  onPressed:
                      !_usingNativeBle ||
                          !_connected ||
                          _deviceBusy ||
                          _speed['running'] == true
                      ? null
                      : () async {
                          try {
                            final sent = await _navigationChannel
                                .invokeMethod<bool>('sendSpeedSample');
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    sent == true
                                        ? 'Test: 42 km/h for 5 seconds. Not live GPS.'
                                        : 'Could not send. Stop GPS speed and reconnect first.',
                                  ),
                                ),
                              );
                            }
                          } catch (_) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Could not send the speed sample.',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                  icon: const Icon(Icons.speed),
                  label: const Text('Speed · 42 km/h (test)'),
                ),
                for (final sample in const [
                  ('left', Icons.turn_left, 'Left'),
                  ('slight_left', Icons.turn_left, 'Slight left'),
                  ('sharp_left', Icons.turn_left, 'Sharp left'),
                  ('keep_left', Icons.turn_left, 'Keep left'),
                  ('straight', Icons.straight, 'Straight'),
                  ('right', Icons.turn_right, 'Right'),
                  ('slight_right', Icons.turn_right, 'Slight right'),
                  ('sharp_right', Icons.turn_right, 'Sharp right'),
                  ('keep_right', Icons.turn_right, 'Keep right'),
                  ('u_turn', Icons.u_turn_left, 'U-turn'),
                  ('u_turn_right', Icons.u_turn_right, 'Right U-turn'),
                  ('off_route', Icons.not_listed_location, 'Off route'),
                  (
                    'roundabout_1',
                    Icons.roundabout_left,
                    'Roundabout · exit 1',
                  ),
                  (
                    'roundabout_2',
                    Icons.roundabout_left,
                    'Roundabout · exit 2',
                  ),
                  (
                    'roundabout_3',
                    Icons.roundabout_left,
                    'Roundabout · exit 3',
                  ),
                  (
                    'roundabout_4',
                    Icons.roundabout_left,
                    'Roundabout · exit 4',
                  ),
                  (
                    'roundabout_5',
                    Icons.roundabout_left,
                    'Roundabout · exit 5',
                  ),
                  (
                    'roundabout_6',
                    Icons.roundabout_left,
                    'Roundabout · exit 6',
                  ),
                ])
                  OutlinedButton.icon(
                    key: ValueKey('navigation-sample-${sample.$1}'),
                    onPressed: !_navigationReady || _deviceBusy
                        ? null
                        : () => _sendNavigationSample(sample.$1),
                    icon: Icon(sample.$2),
                    label: Text(sample.$3),
                  ),
              ],
            ),
            if (!_navigationReady)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Connect ESP32 and enable navigation before sending a sample.',
                ),
              ),
          ],
        ),
      ],
    ],
    action: IconButton(
      tooltip: 'Refresh status',
      onPressed: _deviceBusy ? null : _refreshDevice,
      icon: const Icon(Icons.refresh),
    ),
  );

  Widget _contentPage() => _pageLayout(
    'Content',
    'Saved on your phone. Sent only when you choose.',
    [
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Notifications')),
          ButtonSegment(value: true, label: Text('Tasks')),
        ],
        selected: {_showTasks},
        onSelectionChanged: (value) => setState(() => _showTasks = value.first),
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          key: const ValueKey('add-content'),
          onPressed: _editing ? null : _addContent,
          icon: const Icon(Icons.add),
          label: Text(_showTasks ? 'Add task' : 'Add notification'),
        ),
      ),
      const SizedBox(height: 16),
      if (_config.mode == ConnectionMode.demo)
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'Save content now. Connect ESP32 in Settings when you want to send it.',
            style: TextStyle(color: NavRideColors.muted, height: 1.45),
          ),
        ),
      if (_showTasks && _tasks.isEmpty)
        const _EmptyContent(
          icon: Icons.checklist,
          title: 'No tasks yet',
          message: 'Add a task to remember for your ride.',
        ),
      if (!_showTasks && _notices.isEmpty)
        const _EmptyContent(
          icon: Icons.notifications_none,
          title: 'No notifications yet',
          message: 'Save a message and send it to the display when needed.',
        ),
      if (_showTasks)
        for (final task in _tasks)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
                child: Row(
                  children: [
                    Checkbox(
                      value: task.done,
                      semanticLabel: 'Complete ${task.title}',
                      onChanged: _editing
                          ? null
                          : (value) => unawaited(
                              _editContent(
                                tasks: _tasks
                                    .map(
                                      (item) => item.id == task.id
                                          ? item.copyWith(done: value)
                                          : item,
                                    )
                                    .toList(),
                              ),
                            ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            style: TextStyle(
                              fontSize: 16,
                              decoration: task.done
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          if (task.dueAt != null)
                            Text(
                              'Due ${DateFormat('dd/MM HH:mm').format(task.dueAt!)}',
                              style: const TextStyle(
                                color: NavRideColors.muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    _contentMenu(
                      'task-${task.id}',
                      () => _send({
                        'command': 'push_task',
                        'title': task.title,
                        'body': task.done ? 'Completed' : 'Pending',
                        'done': task.done,
                      }),
                      () => _deleteTask(task),
                      () => _addContent(taskItem: task),
                    ),
                  ],
                ),
              ),
            ),
          ),
      if (!_showTasks)
        for (final notice in _notices)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notice.title,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _contentMenu(
                          'notice-${notice.id}',
                          () => _send({
                            'command': 'push_notification',
                            'title': notice.title,
                            'body': notice.body,
                          }),
                          () => _deleteNotice(notice),
                          () => _addContent(notice: notice),
                        ),
                      ],
                    ),
                    Text(
                      notice.body,
                      style: const TextStyle(fontSize: 16, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      DateFormat('dd/MM · HH:mm').format(notice.createdAt),
                      style: const TextStyle(
                        color: NavRideColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    ],
  );

  Widget _contentMenu(
    String id,
    VoidCallback send,
    VoidCallback remove,
    VoidCallback edit,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        key: ValueKey('send-$id'),
        tooltip: 'Send to display',
        onPressed: _editing || !_canSend ? null : send,
        icon: const Icon(Icons.send_outlined),
      ),
      PopupMenuButton<String>(
        key: ValueKey('menu-$id'),
        tooltip: 'Content options',
        enabled: !_editing && !_sending,
        onSelected: (value) {
          if (value == 'send') {
            send();
          } else if (value == 'edit') {
            edit();
          } else {
            remove();
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'send',
            enabled: _canSend,
            child: const Text('Send to display'),
          ),
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    ],
  );

  Widget
  _settingsPage() => _pageLayout('Settings', 'Connect and manage your display.', [
    _Panel(
      title: 'Connect ESP32',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Use Bluetooth for navigation, or Wi-Fi to send content on the same network.',
            style: TextStyle(color: NavRideColors.muted, height: 1.45),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in [
                ConnectionMode.bluetooth,
                ConnectionMode.network,
              ])
                ChoiceChip(
                  key: ValueKey('mode-${mode.name}'),
                  label: Text(mode.label),
                  avatar: Icon(
                    mode == ConnectionMode.bluetooth
                        ? Icons.bluetooth
                        : Icons.wifi,
                    size: 18,
                  ),
                  selected: _config.mode == mode,
                  onSelected: _deviceBusy ? null : (_) => _changeMode(mode),
                ),
            ],
          ),
          if (_connectionBusy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(),
            ),
          const SizedBox(height: 16),
          Text(
            _connected
                ? 'Connected · ${_config.mode.label}'
                : 'ESP32 not connected',
            style: TextStyle(
              color: _connected ? NavRideColors.green : NavRideColors.muted,
            ),
          ),
          if (_config.mode != ConnectionMode.demo)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                key: const ValueKey('disconnect-device'),
                onPressed: _deviceBusy
                    ? null
                    : () => _changeMode(ConnectionMode.demo),
                icon: const Icon(Icons.link_off),
                label: const Text('Disconnect'),
              ),
            )
          else if (_config.bluetoothId.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('reconnect-saved-ble'),
                    onPressed: _deviceBusy
                        ? null
                        : () => _changeMode(ConnectionMode.bluetooth),
                    icon: const Icon(Icons.bluetooth),
                    label: const Text('Connect saved ESP32'),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'If BLT is not flashing, press Button 2 on ESP32 first.',
                    style: TextStyle(color: NavRideColors.muted),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('change-wifi'),
            onPressed: _deviceBusy
                ? null
                : () => setState(() => _showWifiSetup = !_showWifiSetup),
            icon: const Icon(Icons.wifi),
            label: const Text('Change Wi-Fi'),
          ),
          if (_showWifiSetup) ...[
            const SizedBox(height: 12),
            Text(
              _connected
                  ? 'Enter the new network. ESP32 will switch to Wi-Fi after saving.'
                  : 'Connect ESP32 over Bluetooth or Wi-Fi first, then enter the new network.',
              style: const TextStyle(color: NavRideColors.muted, height: 1.45),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _wifiSsidController,
              enabled: !_deviceBusy,
              maxLength: 32,
              decoration: const InputDecoration(
                labelText: 'Wi-Fi name',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _wifiPasswordController,
              enabled: !_deviceBusy,
              maxLength: 63,
              obscureText: !_showWifiPassword,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Wi-Fi password',
                counterText: '',
                suffixIcon: IconButton(
                  tooltip: _showWifiPassword
                      ? 'Hide password'
                      : 'Show password',
                  onPressed: () =>
                      setState(() => _showWifiPassword = !_showWifiPassword),
                  icon: Icon(
                    _showWifiPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: !_connected || !_canSend ? null : _setupWifi,
              child: const Text('Save Wi-Fi network'),
            ),
          ],
          if (_config.mode == ConnectionMode.bluetooth) ...[
            const SizedBox(height: 8),
            const Text(
              'Press Button 2 on ESP32 until BLT flashes, then select Find devices. Android may ask for the PIN shown in ESP32 Info.',
              style: TextStyle(color: NavRideColors.muted, height: 1.45),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('scan-ble'),
                  onPressed: _deviceBusy ? null : _scanBle,
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Find devices'),
                ),
                if (_config.bluetoothId.isNotEmpty)
                  TextButton(
                    onPressed: _deviceBusy
                        ? null
                        : _usingNativeBle
                        ? _configureBridge
                        : _refreshDevice,
                    child: const Text('Reconnect'),
                  ),
              ],
            ),
            for (final candidate in _bleCandidates)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(candidate.name),
                subtitle: Text(candidate.id),
                trailing: TextButton(
                  onPressed: _deviceBusy ? null : () => _connectBle(candidate),
                  child: const Text('Connect'),
                ),
              ),
            if (kIsWeb)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Web Bluetooth requires HTTPS or localhost and a supported browser.',
                  style: TextStyle(color: NavRideColors.muted),
                ),
              ),
          ],
          if (_config.mode == ConnectionMode.network) ...[
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('device-pairing-pin'),
              controller: _pairingPinController,
              enabled: !_deviceBusy,
              keyboardType: TextInputType.number,
              obscureText: !_showPairingPin,
              enableSuggestions: false,
              autocorrect: false,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              decoration: InputDecoration(
                labelText: 'ESP32 pairing PIN',
                hintText: 'Shown in ESP32 Info',
                counterText: '',
                suffixIcon: IconButton(
                  tooltip: _showPairingPin ? 'Hide PIN' : 'Show PIN',
                  onPressed: () =>
                      setState(() => _showPairingPin = !_showPairingPin),
                  icon: Icon(
                    _showPairingPin
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('device-address'),
              controller: _baseUrlController,
              enabled: !_deviceBusy,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveNetworkAddress(),
              decoration: const InputDecoration(
                labelText: 'ESP32 IP address',
                hintText: '192.168.1.55',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Find the PIN and IP on the display: Button 3 → ESP32 Info.',
              style: TextStyle(color: NavRideColors.muted),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _deviceBusy ? null : _saveNetworkAddress,
              child: const Text('Save and connect'),
            ),
          ],
          if (_deviceError != null) ...[
            const SizedBox(height: 12),
            _connectionError(),
          ],
        ],
      ),
    ),
    const SizedBox(height: 16),
    _Disclosure(
      title: 'Device info',
      icon: Icons.info_outline,
      children: [
        Text('Device: ${_status?.deviceName ?? 'ESP32-NavRide'}'),
        const SizedBox(height: 8),
        Text('Connection: ${_config.mode.label}'),
        if (_status?.ssid.isNotEmpty == true) Text('Wi-Fi: ${_status!.ssid}'),
        if (_status?.ip.isNotEmpty == true)
          SelectableText('IP: ${_status!.ip}'),
        if (_status?.firmware.isNotEmpty == true)
          Text('Firmware: ${_status!.firmware}'),
        if (_config.bluetoothId.isNotEmpty)
          SelectableText('Bluetooth: ${_config.bluetoothId}'),
      ],
    ),
    const SizedBox(height: 12),
    _Disclosure(
      title: 'App updates',
      icon: Icons.system_update_alt,
      children: [
        Text(
          _appVersion == null
              ? 'ESP32-NavRide · ${_android ? 'Android' : 'Preview'}'
              : 'Version ${_appVersion!.name}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('update-server-url'),
          controller: _updateUrlController,
          enabled: !_updatingApp && !_clearingData,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _checkAndInstallUpdate(),
          decoration: const InputDecoration(
            labelText: 'Update server',
            hintText: 'http://192.168.1.149:3000',
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'The computer running the update server, not the ESP32 IP address.',
          style: TextStyle(color: NavRideColors.muted),
        ),
        if (_updatingApp)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: LinearProgressIndicator(value: _updateProgress),
          ),
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('check-app-update'),
          onPressed: _updatingApp || _clearingData
              ? null
              : _checkAndInstallUpdate,
          child: Text(
            _updatingApp
                ? (_updateProgress == null
                      ? 'Checking…'
                      : 'Downloading ${(_updateProgress! * 100).round()}%')
                : _android
                ? 'Check for updates'
                : 'Save server',
          ),
        ),
      ],
    ),
    const SizedBox(height: 12),
    _Disclosure(
      title: 'Privacy and data',
      icon: Icons.privacy_tip_outlined,
      children: [
        const Text(
          'Saved content stays on this device until you send it. There is no analytics or cloud sync. '
          'Android backups of app data are disabled.\n\n'
          'Navigation sharing processes only OsmAnd notifications and directions. '
          'GPS speed is optional: only speed is sent to ESP32; coordinates and route history are not saved by NavRide.\n\n'
          'Wi-Fi uses local HTTP, which is not encrypted. Use a trusted network or paired Bluetooth for private content. '
          'Updates contact only the server you choose. OsmAnd has its own privacy settings.',
          style: TextStyle(color: NavRideColors.muted, height: 1.5),
        ),
        if (_android) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _clearingData
                ? null
                : () async {
                    try {
                      await _navigationChannel.invokeMethod<void>(
                        'openAppPrivacySettings',
                      );
                    } catch (_) {
                      _showMessage(
                        'Open Android Settings → Apps → ESP32-NavRide to manage permissions.',
                        error: true,
                      );
                    }
                  },
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: const Text('Manage Android permissions'),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('clear-local-data'),
          onPressed: _deviceBusy || _editing || _updatingApp || _speedBusy
              ? null
              : _clearLocalData,
          icon: const Icon(Icons.delete_outline),
          label: Text(_clearingData ? 'Deleting…' : 'Delete saved data'),
        ),
      ],
    ),
    const SizedBox(height: 12),
    Card(
      child: ListTile(
        leading: const Icon(Icons.help_outline),
        title: const Text('Help'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _showHelp,
      ),
    ),
  ]);

  Widget _connectionError() => Semantics(
    liveRegion: true,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 20,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _deviceError ?? '',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.title});
  final String? title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    ),
  );
}

class _Disclosure extends StatefulWidget {
  const _Disclosure({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;
  @override
  State<_Disclosure> createState() => _DisclosureState();
}

class _DisclosureState extends State<_Disclosure> {
  // Keep text-field scroll offsets separate from the tile's saved bool.
  final _contentStorage = PageStorageBucket();
  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      key: PageStorageKey(widget.title),
      leading: Icon(widget.icon),
      title: Text(widget.title),
      shape: const Border(),
      collapsedShape: const Border(),
      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageStorage(
          bucket: _contentStorage,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: widget.children,
          ),
        ),
      ],
    ),
  );
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.ready,
  });
  final IconData icon;
  final String title;
  final String detail;
  final bool ready;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    leading: Icon(icon, color: NavRideColors.muted),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(detail),
    trailing: ready
        ? const Icon(Icons.check_circle, color: NavRideColors.green)
        : null,
  );
}

class _EmptyContent extends StatelessWidget {
  const _EmptyContent({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      children: [
        Icon(icon, size: 40, color: NavRideColors.muted),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: NavRideColors.muted, height: 1.45),
        ),
      ],
    ),
  );
}

class _NavigationHelp extends StatelessWidget {
  const _NavigationHelp();
  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Get started with OsmAnd',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      ),
      SizedBox(height: 20),
      Text(
        '1. Connect the display',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
      ),
      SizedBox(height: 8),
      Text(
        'Press Button 2 on ESP32 to enable Bluetooth. In the Android app, open Settings → Bluetooth → Find devices and select ESP32-NavRide.',
      ),
      SizedBox(height: 20),
      Text(
        '2. Enable navigation',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
      ),
      SizedBox(height: 8),
      Text(
        'In Navigation, select Enable navigation and allow notification access for ESP32-NavRide. In OsmAnd, open Menu → Plugins and enable ESP32-NavRide (Third-party app). Return to NavRide once to connect the navigation API, then open OsmAnd and start a route. Notification fallback still works if the API is unavailable.',
      ),
      SizedBox(height: 20),
      Text(
        '3. Show street names',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
      ),
      SizedBox(height: 8),
      Text(
        'NavRide reads the next road, maneuver and distance together from the OsmAnd navigation API. Street names appear only when OsmAnd supplies them; a blank name is not replaced with the previous road. Allow OsmAnd notifications for fallback. TTS voice prompts are optional.',
      ),
      SizedBox(height: 20),
      Text(
        'If notification access is enabled but directions do not arrive after the app was stopped, turn ESP32-NavRide off and on in Android notification access. Then return here. Test a simulated route while parked before riding.',
      ),
      SizedBox(height: 20),
      Text(
        'ESP32 buttons',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
      ),
      SizedBox(height: 8),
      Text(
        'Button 1: saved Wi-Fi. Button 2: Bluetooth. Button 3: open Menu for the IP address and device info. In Menu, Button 1 moves down and Button 2 selects.',
      ),
      SizedBox(height: 20),
      Text(
        'Automatic OsmAnd navigation is available on Android only. Bluetooth works without Wi-Fi; download maps in OsmAnd before riding offline.',
        style: TextStyle(color: NavRideColors.muted, height: 1.5),
      ),
    ],
  );
}

class _ContentDialog extends StatefulWidget {
  const _ContentDialog({
    required this.task,
    this.editing = false,
    this.title = '',
    this.body = '',
  });
  final bool task;
  final bool editing;
  final String title;
  final String body;
  @override
  State<_ContentDialog> createState() => _ContentDialogState();
}

class _ContentDialogState extends State<_ContentDialog> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.title);
  late final _body = TextEditingController(text: widget.body);
  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState?.validate() == true) {
      Navigator.pop(context, (_title.text.trim(), _body.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      '${widget.editing ? 'Edit' : 'Add'} ${widget.task ? 'task' : 'notification'}',
    ),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 400,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _title,
                autofocus: true,
                maxLength: 40,
                textInputAction: widget.task
                    ? TextInputAction.done
                    : TextInputAction.next,
                onFieldSubmitted: widget.task ? (_) => _submit() : null,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a ${widget.task ? 'task name' : 'title'}.'
                    : null,
                decoration: InputDecoration(
                  labelText: widget.task ? 'Task name' : 'Title',
                ),
              ),
              if (!widget.task) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _body,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 80,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a message.'
                      : null,
                  decoration: const InputDecoration(labelText: 'Content'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Save')),
    ],
  );
}
