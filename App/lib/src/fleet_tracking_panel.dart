import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FleetTrackingPanel extends StatefulWidget {
  const FleetTrackingPanel({required this.enabled, super.key});

  final bool enabled;

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
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    WidgetsBinding.instance.addObserver(this);
    _user = FirebaseAuth.instance.currentUser;
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (mounted) setState(() => _user = user);
      unawaited(_refreshStatus());
    });
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
    if (widget.enabled) WidgetsBinding.instance.removeObserver(this);
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
      final status = await _channel.invokeMapMethod<String, dynamic>(
        'getFleetStatus',
      );
      if (mounted && status != null) setState(() => _status = status);
    } catch (_) {
      // Navigation and BLE do not depend on the optional fleet channel.
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

  Future<void> _startTrip() async {
    if (_busy || _user == null) return;
    final fleetId = _fleetId.text.trim();
    final vehicleId = _vehicleId.text.trim();
    if (!_idPattern.hasMatch(fleetId) || !_idPattern.hasMatch(vehicleId)) {
      setState(
        () => _error =
            'Use 1–64 letters, numbers, hyphens or underscores for IDs.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Require a server-authorized assignment, never a cached/offline one.
      final vehicleRef = FirebaseFirestore.instance.doc(
        'fleets/$fleetId/vehicles/$vehicleId',
      );
      DocumentSnapshot<Map<String, dynamic>> vehicle;
      try {
        vehicle = await vehicleRef.get(const GetOptions(source: Source.server));
      } on FirebaseException catch (error) {
        if (error.code != 'unavailable' && error.code != 'deadline-exceeded') {
          rethrow;
        }
        // Only an assignment already fetched from the server may start offline.
        vehicle = await vehicleRef.get(const GetOptions(source: Source.cache));
      }
      if (vehicle.data()?['driverUid'] != _user?.uid) {
        throw StateError(
          'Ask the fleet admin to assign this vehicle to your account.',
        );
      }
      await _channel.invokeMethod<bool>('startFleetTrip', {
        'fleetId': fleetId,
        'vehicleId': vehicleId,
      });
      await _refreshStatus();
    } on FirebaseException catch (error) {
      _error = error.code == 'permission-denied'
          ? 'This account cannot access the selected vehicle.'
          : 'Vehicle assignment unavailable. Connect once to verify this vehicle before starting offline.';
    } on PlatformException catch (error) {
      _error = error.message ?? 'Could not start trip.';
    } on StateError catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'Could not start trip. Try again.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _endTrip() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _channel.invokeMethod<bool>('stopFleetTrip');
      await _refreshStatus();
    } on PlatformException catch (error) {
      _error = error.message ?? 'Could not end trip.';
    } catch (_) {
      _error = 'Could not end trip. Try again.';
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

  @override
  Widget build(BuildContext context) {
    final active = _status['active'] == true;
    final pending = _status['pending'] == true;
    final detail = _status['message'] as String?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Fleet tracking',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Optional. While a trip is active, share phone GPS and speed with your fleet. '
              'The first GPS fix is saved, then new points at least 1 minute apart, '
              'only if you moved more than 100 m. Points are saved on this phone first, '
              'then removed from the upload queue only after the server confirms receipt. '
              'Trip history stays in the cloud after End trip. '
              'OsmAnd directions and personal content stay on this device.',
            ),
            const SizedBox(height: 16),
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
                enabled: !active && !_busy,
                decoration: const InputDecoration(labelText: 'Fleet ID'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('vehicle-id'),
                controller: _vehicleId,
                enabled: !active && !_busy,
                decoration: const InputDecoration(labelText: 'Vehicle ID'),
              ),
              const SizedBox(height: 12),
              Text(
                active ? 'Trip active' : 'Trip off · location not shared',
                key: const ValueKey('fleet-trip-state'),
                style: TextStyle(
                  color: active ? const Color(0xFF237747) : null,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (detail != null) ...[const SizedBox(height: 4), Text(detail)],
              if (_status['trackError'] case final String historyError) ...[
                const SizedBox(height: 4),
                Text(
                  historyError,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_status['tripError'] case final String tripError) ...[
                const SizedBox(height: 4),
                Text(
                  tripError,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_status['syncedSecondsAgo'] case final int seconds) ...[
                const SizedBox(height: 4),
                Text(
                  seconds < 90
                      ? 'Last cloud update ${seconds}s ago'
                      : 'Last cloud update ${seconds ~/ 60}m ago · may be stale',
                ),
              ],
              if ((active || pending) && _status['online'] == false) ...[
                const SizedBox(height: 4),
                const Text(
                  'Offline · route points are saved on this phone and will sync when internet returns.',
                ),
              ],
              if (_status['queuedPoints'] case final int queued
                  when queued > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '$queued route ${queued == 1 ? 'point' : 'points'} waiting to sync',
                ),
              ],
              if (pending && _status['online'] != false)
                const Text('Waiting for cloud sync'),
              if (_status['historyPending'] == true)
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          try {
                            await _channel.invokeMethod<bool>('retryFleetSync');
                            await _refreshStatus();
                          } on PlatformException {
                            if (mounted) {
                              setState(
                                () => _error =
                                    'Could not retry sync. Reopen NavRide and try again.',
                              );
                            }
                          }
                        },
                  icon: const Icon(Icons.sync),
                  label: const Text('Retry sync'),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('fleet-trip-toggle'),
                onPressed: _busy
                    ? null
                    : active
                    ? _endTrip
                    : _startTrip,
                icon: Icon(
                  active ? Icons.stop_circle_outlined : Icons.play_arrow,
                ),
                label: Text(
                  _busy
                      ? 'Please wait…'
                      : active
                      ? 'End trip'
                      : 'Start trip',
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _openDashboard,
                icon: const Icon(Icons.map_outlined),
                label: const Text('View route dashboard'),
              ),
              TextButton(
                onPressed: _busy || active || pending ? null : _signOut,
                child: Text(_busy ? 'Checking sync…' : 'Sign out'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
