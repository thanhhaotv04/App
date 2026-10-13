import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'fleet_marker_controls.dart';
import 'fleet_marker_list.dart';
import 'fleet_trip_history.dart';
import 'feature_help.dart';

class FleetTrackingPanel extends StatefulWidget {
  const FleetTrackingPanel({
    required this.enabled,
    this.trips = false,
    this.rideAvailable = false,
    this.savedDeviceId = '',
    this.onOpenSettings,
    super.key,
  });

  final bool enabled;
  final bool trips;
  final bool rideAvailable;
  final String savedDeviceId;
  final VoidCallback? onOpenSettings;

  @override
  State<FleetTrackingPanel> createState() => _FleetTrackingPanelState();
}

class _FleetTrackingPanelState extends State<FleetTrackingPanel>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('esp32_navride/navigation');
  static final _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _fleetId = TextEditingController(text: 'demo');
  final _vehicleId = TextEditingController(text: 'bike-01');
  StreamSubscription<User?>? _authSubscription;
  Timer? _statusTimer;
  User? _user;
  Map<String, dynamic> _status = const {};
  Map<String, dynamic> _speed = const {};
  bool _shareFleet = false;
  bool _selectionReady = false;
  int _markerRevision = 0;
  bool _busy = false;
  bool _markerPhoto = false;
  String? _markerFeedback;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled && !widget.rideAvailable) return;
    WidgetsBinding.instance.addObserver(this);
    if (widget.enabled) {
      _user = FirebaseAuth.instance.currentUser;
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
        user,
      ) {
        if (mounted) {
          setState(() {
            if (_user?.uid != user?.uid) {
              _shareFleet = false;
              _selectionReady = false;
              _markerFeedback = null;
              _markerPhoto = false;
              _error = null;
            }
            _user = user;
          });
        }
        unawaited(_loadSelection());
        unawaited(_refreshStatus());
      });
      unawaited(_loadSelection());
    }
    unawaited(_refreshStatus());
    _startStatusTimer();
  }

  void _startStatusTimer() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_refreshStatus()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startStatusTimer();
      unawaited(_refreshStatus());
    } else {
      _statusTimer?.cancel();
      _statusTimer = null;
    }
  }

  @override
  void dispose() {
    if (widget.enabled || widget.rideAvailable) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _statusTimer?.cancel();
    unawaited(_authSubscription?.cancel() ?? Future<void>.value());
    _email.dispose();
    _password.dispose();
    _fleetId.dispose();
    _vehicleId.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    try {
      final speed = await _channel.invokeMapMethod<String, dynamic>(
        'getSpeedStatus',
      );
      final status = await _channel.invokeMapMethod<String, dynamic>(
        'getFleetStatus',
      );
      if (mounted && status != null) {
        setState(() {
          if (_status['active'] != status['active']) _markerFeedback = null;
          _status = status;
          _speed = speed ?? const {};
        });
      }
    } catch (_) {
      // Navigation and BLE do not depend on the optional fleet channel.
    }
  }

  Future<void> _loadSelection() async {
    final uid = _user?.uid;
    if (uid == null) return;
    try {
      final selection = await _channel.invokeMapMethod<String, dynamic>(
        'getFleetSelection',
      );
      if (!mounted || _user?.uid != uid) return;
      setState(() {
        _fleetId.text = selection?['fleetId'] as String? ?? 'demo';
        _vehicleId.text = selection?['vehicleId'] as String? ?? 'bike-01';
        _selectionReady = true;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not load vehicle settings. Reopen NavRide.',
        );
      }
    }
  }

  Future<void> _verifyVehicle() async {
    final uid = _user?.uid;
    if (uid == null) throw StateError('Sign in to Fleet in Settings first.');
    final fleetId = _fleetId.text.trim();
    final vehicleId = _vehicleId.text.trim();
    if (!_idPattern.hasMatch(fleetId) || !_idPattern.hasMatch(vehicleId)) {
      throw StateError(
        'Use 1–64 letters, numbers, hyphens or underscores for IDs.',
      );
    }
    final ref = FirebaseFirestore.instance.doc(
      'fleets/$fleetId/vehicles/$vehicleId',
    );
    DocumentSnapshot<Map<String, dynamic>> vehicle;
    try {
      vehicle = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));
    } on FirebaseException catch (error) {
      if (error.code != 'unavailable' && error.code != 'deadline-exceeded') {
        rethrow;
      }
      vehicle = await ref.get(const GetOptions(source: Source.cache));
    } on TimeoutException {
      vehicle = await ref.get(const GetOptions(source: Source.cache));
    }
    if (_user?.uid != uid ||
        FirebaseAuth.instance.currentUser?.uid != uid ||
        vehicle.data()?['driverUid'] != uid ||
        vehicle.data()?['archived'] == true) {
      throw StateError(
        'Ask the fleet admin to assign an active vehicle to this account.',
      );
    }
  }

  Future<void> _saveSelection() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _verifyVehicle();
      await _channel.invokeMethod<bool>('setFleetSelection', {
        'fleetId': _fleetId.text.trim(),
        'vehicleId': _vehicleId.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vehicle saved · ready in Trips')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save this vehicle. Check the IDs, account assignment and connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on FirebaseAuthException catch (error) {
      _error = switch (error.code) {
        'network-request-failed' => 'Connect to the internet and try again.',
        'too-many-requests' => 'Too many attempts. Try again later.',
        _ => 'Could not sign in. Check your email and password.',
      };
    } catch (_) {
      _error = 'Could not sign in. Try again.';
    } finally {
      if (mounted) _password.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startRide() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_shareFleet) {
        if (!_selectionReady) {
          throw StateError('Choose your vehicle in Settings first.');
        }
        await _verifyVehicle();
      }
      if (!mounted) return;
      await _channel.invokeMethod<bool>('startRide', {
        'shareFleet': _shareFleet,
        if (widget.savedDeviceId.isNotEmpty) 'deviceId': widget.savedDeviceId,
        if (_shareFleet) 'fleetId': _fleetId.text.trim(),
        if (_shareFleet) 'vehicleId': _vehicleId.text.trim(),
      });
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _refreshStatus();
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _error = error.message ?? 'Could not start ride.');
      }
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not start ride. Check GPS, vehicle access and connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _endRide() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _channel.invokeMethod<bool>('endRide');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _refreshStatus();
      if (mounted) setState(() => _shareFleet = false);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not end ride. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    if (_busy || _status['active'] == true || _status['pending'] == true) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _refreshStatus();
      if (_status['pending'] == true) {
        throw TimeoutException('Trip data is still waiting to sync.');
      }
      await FirebaseFirestore.instance.waitForPendingWrites().timeout(
        const Duration(seconds: 10),
      );
      await FirebaseAuth.instance.signOut();
    } on TimeoutException {
      _error =
          'Trip data is still waiting to sync. Connect to the internet before signing out.';
    } catch (_) {
      _error =
          'Could not confirm trip sync. Stay signed in and try again online.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDashboard() async {
    try {
      await _channel.invokeMethod<bool>('openFleetDashboard');
    } on PlatformException {
      if (mounted) {
        setState(() => _error = 'Could not open the fleet dashboard.');
      }
    }
  }

  Future<void> _saveMarker(String kind) async {
    if (_busy || _status['active'] != true) return;
    setState(() {
      _busy = true;
      _error = null;
      _markerFeedback = null;
    });
    try {
      final message = await _channel.invokeMethod<String>('saveFleetMarker', {
        'kind': kind,
        'photo': _markerPhoto,
      });
      if (mounted) {
        setState(
          () =>
              _markerFeedback = message ?? 'Photo cancelled · no marker saved',
        );
        setState(() => _markerRevision++);
      }
      await _refreshStatus();
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.message ?? 'Could not save marker. Try again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not save marker. Reopen NavRide and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _status['active'] == true;
    final pending = _status['pending'] == true;
    final riding = active || _speed['running'] == true;
    final detail = _status['message'] as String?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.trips)
              Text('Your ride', style: Theme.of(context).textTheme.titleMedium)
            else
              const FeatureHeading(
                title: 'Fleet account',
                help:
                    'Sign in with the driver account assigned to your vehicle. '
                    'Choose your Fleet ID and Vehicle ID, then save. '
                    'Open Trips to start a ride and choose whether to share location. '
                    'End your Fleet ride before changing vehicles; wait for pending uploads before signing out.',
              ),
            const SizedBox(height: 8),
            if (widget.trips) ...[
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Share with Fleet'),
                subtitle: Text(
                  _user == null
                      ? 'Requires a Fleet account'
                      : '${_fleetId.text} / ${_vehicleId.text}',
                ),
                value: active || _shareFleet,
                onChanged: !riding && !_busy && _user != null && _selectionReady
                    ? (value) => setState(() => _shareFleet = value)
                    : null,
              ),
              if (_user == null)
                TextButton(
                  onPressed: widget.onOpenSettings,
                  child: const Text('Set up Fleet in Settings'),
                ),
              if (_shareFleet || active)
                const Text('Shares GPS location with your fleet.'),
              if (!_shareFleet && !active)
                const Text('Private ride · location is not shared with Fleet.'),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('ride-toggle'),
                  onPressed: _busy || !widget.rideAvailable
                      ? null
                      : riding
                      ? _endRide
                      : _startRide,
                  icon: Icon(
                    riding ? Icons.stop_circle_outlined : Icons.play_arrow,
                  ),
                  label: Text(
                    _busy
                        ? 'Please wait…'
                        : riding
                        ? 'End ride'
                        : 'Start ride',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                riding ? 'Ride active' : 'Ride off',
                key: const ValueKey('ride-state'),
              ),
              if (riding) ...[
                Text(_speed['message'] as String? ?? 'GPS speed is off'),
                Text(
                  _speed['delivered'] == true
                      ? (_speed['kmh'] != null
                            ? 'Speed delivered to ESP32'
                            : 'ESP32 connected · waiting for GPS speed')
                      : 'ESP32 not receiving speed yet · check Bluetooth in Settings',
                ),
              ],
              if (!widget.rideAvailable)
                const Text('Ride controls are available on Android.'),
              if (_user != null) ...[
                const Divider(height: 32),
                Text(
                  active ? 'Trip active' : 'Trip off · location not shared',
                  key: const ValueKey('fleet-trip-state'),
                ),
                if (detail != null) Text(detail),
                if (_status['trackError'] case final String error) Text(error),
                if (_status['tripError'] case final String error) Text(error),
                if (_status['queuedPoints'] case final int queued
                    when queued > 0)
                  Text('$queued route points waiting to sync'),
                if (pending) ...[
                  const Text('Saved on phone · waiting to sync'),
                  TextButton.icon(
                    onPressed: _busy ? null : _retrySync,
                    icon: const Icon(Icons.sync),
                    label: const Text('Retry sync'),
                  ),
                ],
                FleetMarkerControls(
                  active: active,
                  busy: _busy,
                  photo: _markerPhoto,
                  onPhotoChanged: (value) =>
                      setState(() => _markerPhoto = value),
                  onSave: (kind) => unawaited(_saveMarker(kind)),
                ),
                if (active &&
                    _markerFeedback == null &&
                    _status['markerMessage'] is String)
                  Semantics(
                    liveRegion: true,
                    child: Text(_status['markerMessage'] as String),
                  ),
                if (_markerFeedback != null)
                  Semantics(liveRegion: true, child: Text(_markerFeedback!)),
                FleetMarkerList(
                  key: ValueKey(_user!.uid),
                  revision: _markerRevision,
                ),
                const Divider(height: 32),
                Text(
                  'Trip history',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                FleetTripHistory(key: ValueKey('trip-history-${_user!.uid}')),
                TextButton.icon(
                  onPressed: _openDashboard,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Open dashboard'),
                ),
              ],
            ] else ...[
              if (!widget.enabled)
                const Text('Available on Android when Firebase is configured.')
              else if (_user == null) ...[
                TextField(
                  key: const ValueKey('fleet-email'),
                  controller: _email,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Driver email'),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('fleet-password'),
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _signIn(),
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const ValueKey('fleet-sign-in'),
                  onPressed: _busy ? null : _signIn,
                  child: Text(_busy ? 'Signing in…' : 'Sign in to fleet'),
                ),
              ] else ...[
                Text('Signed in: ${_user!.email ?? 'Driver'}'),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('fleet-id'),
                  controller: _fleetId,
                  enabled: !active && !_busy && _selectionReady,
                  decoration: const InputDecoration(labelText: 'Fleet ID'),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('vehicle-id'),
                  controller: _vehicleId,
                  enabled: !active && !_busy && _selectionReady,
                  decoration: const InputDecoration(labelText: 'Vehicle ID'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: active || _busy || !_selectionReady
                      ? null
                      : _saveSelection,
                  child: const Text('Save vehicle'),
                ),
                if (active)
                  const Text(
                    'End your ride in Trips before changing vehicles.',
                  ),
                TextButton(
                  onPressed: _busy || active || pending ? null : _signOut,
                  child: const Text('Sign out'),
                ),
                if (pending)
                  const Text('Waiting for sync. Keep this account signed in.'),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _retrySync() async {
    try {
      await _channel.invokeMethod<bool>('retryFleetSync');
      await _refreshStatus();
      if (mounted) setState(() => _markerRevision++);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not retry sync. Try again.');
    }
  }
}
