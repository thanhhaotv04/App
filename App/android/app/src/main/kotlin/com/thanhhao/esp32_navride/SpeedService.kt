package com.thanhhao.esp32_navride

import android.Manifest
import android.annotation.SuppressLint
import android.app.*
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Network
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.*
import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import java.util.Date
import java.util.UUID

/** One opt-in GPS foreground service for BLE speed and fleet trip sharing. */
class SpeedService : Service(), LocationListener {
    companion object {
        const val START_SPEED = "START_SPEED"
        const val STOP_SPEED = "STOP_SPEED"
        const val START_FLEET = "START_FLEET"
        const val STOP_FLEET = "STOP_FLEET"
        const val STOP_ALL = "STOP_ALL"

        @Volatile var running = false
            private set
        @Volatile var fleetActive = false
            private set
        @Volatile private var fleetPending = false
        @Volatile private var fleetMessage = "Trip is off"
        @Volatile private var trackError: String? = null
        @Volatile private var tripError: String? = null
        @Volatile private var queuedPoints = 0
        @Volatile private var fleetOnline = false
        @Volatile private var fleetWriteVersion = 0
        @Volatile private var lastFleetSyncAt = 0L
        @Volatile private var latestKmh: Int? = null
        @Volatile private var fixAt = 0L
        @Volatile private var message = "Speed is off"
        @Volatile var acknowledgedAt = 0L
        private const val CHANNEL = "navride_location"
        private const val NOTIFICATION = 7301

        fun status(): Map<String, Any?> {
            val now = SystemClock.elapsedRealtime()
            val speed = latestKmh.takeIf { running && now - fixAt in 0..SpeedReading.MAX_AGE_MS }
            return mapOf(
                "running" to running, "kmh" to speed,
                "message" to if (running && speed == null && message == "GPS speed active")
                    "Waiting for a fresh GPS fix" else message,
                "delivered" to (running && acknowledgedAt > 0 && now - acknowledgedAt < 5_000),
                "limitKmh" to null,
            )
        }

        fun fleetStatus(): Map<String, Any?> = mapOf(
            "active" to fleetActive,
            "pending" to fleetPending,
            "message" to fleetMessage,
            "trackError" to trackError,
            "tripError" to tripError,
            "queuedPoints" to queuedPoints,
            "online" to fleetOnline,
            "syncedSecondsAgo" to lastFleetSyncAt.takeIf { it > 0L }
                ?.let { (SystemClock.elapsedRealtime() - it) / 1_000L },
        )
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var locations: LocationManager
    private var serviceStarted = false
    private var heartbeatScheduled = false
    private var fleetId = ""
    private var vehicleId = ""
    private var fleetUid = ""
    private var lastFleetAttempt = 0L
    private var tripId = ""
    private var tripStartedAt = Date(0)
    private var lastTrackAt = 0L
    private var lastTrackLat = Double.NaN
    private var lastTrackLon = Double.NaN
    private var lastAcceptedAt = 0L
    private var lastAcceptedLocation: Location? = null
    private val networkListener = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = scheduleNetworkRefresh()
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) =
            scheduleNetworkRefresh()
        override fun onLost(network: Network) = scheduleNetworkRefresh()
    }

    private fun scheduleNetworkRefresh() {
        handler.post {
            val wasOnline = fleetOnline
            fleetOnline = hasInternet()
            if (!fleetActive || fleetOnline == wasOnline) return@post
            if (!fleetOnline) {
                fleetMessage = "Offline · route saved on phone"
                return@post
            }
            fleetMessage = "Online · waiting for a fresh GPS fix"
            val now = SystemClock.elapsedRealtime()
            val fresh = lastAcceptedLocation.takeIf {
                it != null && now - lastAcceptedAt in 0L..15_000L
            }
            if (fresh != null && !fleetPending) {
                lastFleetAttempt = now
                publishFleet(true, fresh)
            }
            runCatching { updateLocationRequest() }
        }
    }
    private val heartbeat = object : Runnable {
        override fun run() {
            if (!running) {
                heartbeatScheduled = false
                return
            }
            if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                message = "Location permission was removed"
                fleetMessage = "Location permission was removed; trip stopped"
                stopSelf()
                return
            }
            val speed = (status()["kmh"] as? Int)
                .takeIf { locations.isProviderEnabled(LocationManager.GPS_PROVIDER) }
            NavigationBleSender.sendSpeed(this@SpeedService, SpeedReading.packet(speed))
            handler.postDelayed(this, 1_000)
        }
    }

    override fun onCreate() {
        super.onCreate()
        locations = getSystemService(LocationManager::class.java)
        runCatching {
            getSystemService(ConnectivityManager::class.java)
                .registerDefaultNetworkCallback(networkListener)
        }
    }

    private fun hasInternet(): Boolean {
        val manager = getSystemService(ConnectivityManager::class.java)
        val network = manager.activeNetwork ?: return false
        return manager.getNetworkCapabilities(network)
            ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
    }

    private fun captureTime(location: Location): Date {
        val now = System.currentTimeMillis()
        return Date(location.time.takeIf { it in (now - 15_000)..(now + 5_000) } ?: now)
    }

    private fun notification(): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, SpeedService::class.java).setAction(STOP_ALL),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL)
            else Notification.Builder(this)
        return builder.setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle(if (fleetActive) "NavRide fleet trip" else "NavRide GPS speed")
            .setContentText(if (fleetActive) "Sharing phone GPS with your fleet" else "Sending GPS speed to ESP32")
            .setContentIntent(open).setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build()).build()
    }

    private fun updateNotification() {
        if (serviceStarted) getSystemService(NotificationManager::class.java).notify(NOTIFICATION, notification())
    }

    @SuppressLint("MissingPermission")
    private fun updateLocationRequest() {
        locations.removeUpdates(this)
        // Fleet-only updates need no 1-second GPS callback; BLE speed does.
        locations.requestLocationUpdates(LocationManager.GPS_PROVIDER,
            if (running) 1_000L else 15_000L, 0f,
            this, Looper.getMainLooper())
    }

    @SuppressLint("MissingPermission")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            STOP_ALL -> {
                if (fleetActive) {
                    fleetActive = false
                    publishFleet(false)
                    publishTripEnd()
                }
                if (running) NavigationBleSender.sendSpeed(this, SpeedReading.packet(null))
                running = false
                stopSelf()
                return START_NOT_STICKY
            }
            STOP_SPEED -> {
                running = false
                message = "Speed is off"
                NavigationBleSender.sendSpeed(this, SpeedReading.packet(null))
                if (fleetActive) {
                    runCatching { updateLocationRequest() }
                    updateNotification()
                } else stopSelf()
                return START_NOT_STICKY
            }
            STOP_FLEET -> {
                if (fleetActive) {
                    fleetActive = false
                    publishFleet(false)
                    publishTripEnd()
                }
                if (running) updateNotification() else stopSelf()
                return START_NOT_STICKY
            }
            START_SPEED -> {
                running = true
                latestKmh = null
                fixAt = 0
                acknowledgedAt = 0
                message = "Waiting for a GPS fix"
            }
            START_FLEET -> {
                val user = FirebaseAuth.getInstance().currentUser
                val requestedFleet = intent.getStringExtra("fleetId").orEmpty()
                val requestedVehicle = intent.getStringExtra("vehicleId").orEmpty()
                if (user == null || !requestedFleet.matches(Regex("[A-Za-z0-9_-]{1,64}")) ||
                    !requestedVehicle.matches(Regex("[A-Za-z0-9_-]{1,64}"))) {
                    fleetMessage = "Sign in and choose a valid fleet vehicle"
                    if (!running) stopSelf()
                    return START_NOT_STICKY
                }
                fleetId = requestedFleet
                vehicleId = requestedVehicle
                fleetUid = user.uid
                fleetActive = true
                fleetMessage = "Waiting for an accurate GPS fix"
                trackError = null
                tripError = null
                // Queued end-of-trip writes are ordered before this trip's new writes.
                fleetWriteVersion++
                fleetPending = false
                lastFleetAttempt = 0L
                lastFleetSyncAt = 0L
                fleetOnline = hasInternet()
                tripId = UUID.randomUUID().toString()
                tripStartedAt = Date(System.currentTimeMillis())
                lastTrackAt = 0L
                lastTrackLat = Double.NaN
                lastTrackLon = Double.NaN
                lastAcceptedAt = 0L
                lastAcceptedLocation = null
                publishTripStart()
            }
            else -> {
                if (!running && !fleetActive) stopSelf()
                return START_NOT_STICKY
            }
        }
        try {
            if (!serviceStarted) {
                val manager = getSystemService(NotificationManager::class.java)
                if (Build.VERSION.SDK_INT >= 26) {
                    manager.createNotificationChannel(NotificationChannel(CHANNEL, "NavRide location", NotificationManager.IMPORTANCE_LOW))
                }
                if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
                else startForeground(NOTIFICATION, notification())
                serviceStarted = true
                updateLocationRequest()
                Log.i("NavRide", "Location service started")
            } else {
                updateLocationRequest()
                updateNotification()
            }
            if (running && !heartbeatScheduled) {
                heartbeatScheduled = true
                handler.post(heartbeat)
            }
        } catch (error: Exception) {
            message = "Could not start GPS. Check location permission and GPS settings."
            fleetMessage = "Could not start GPS; trip stopped"
            Log.w("NavRide", "Location service could not start", error)
            stopSelf()
        }
        // Never restart location sharing silently after a process kill.
        return START_NOT_STICKY
    }

    @Suppress("DEPRECATION")
    override fun onLocationChanged(location: Location) {
        val age = (SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos) / 1_000_000
        latestKmh = SpeedReading.kmh(location.hasSpeed(), location.speed, age,
            if (Build.VERSION.SDK_INT >= 26 && location.hasSpeedAccuracy()) location.speedAccuracyMetersPerSecond else null)
        fixAt = SystemClock.elapsedRealtime() - age
        if (running) message = if (latestKmh != null) "GPS speed active" else "Waiting for a reliable GPS speed"

        if (!fleetActive) return
        if (FirebaseAuth.getInstance().currentUser?.uid != fleetUid) {
            fleetActive = false
            fleetMessage = "Fleet account changed; trip stopped"
            if (!running) stopSelf() else updateNotification()
            return
        }
        val mock = if (Build.VERSION.SDK_INT >= 31) location.isMock else location.isFromMockProvider
        if (!FleetLocationPolicy.accepts(age, location.accuracy.takeIf { location.hasAccuracy() },
                mock, location.latitude, location.longitude)) {
            if (!fleetPending) {
                fleetMessage = if (mock) "Mock GPS is not uploaded" else "Waiting for accurate GPS (50 m or better)"
            }
            return
        }
        val now = SystemClock.elapsedRealtime()
        fleetOnline = hasInternet()
        lastAcceptedAt = now
        lastAcceptedLocation = Location(location)
        val movedMeters = if (lastTrackAt == 0L) 0.0 else FleetLocationPolicy.distanceMeters(
            lastTrackLat, lastTrackLon, location.latitude, location.longitude)
        if (FleetLocationPolicy.shouldRecordTrack(now, lastTrackAt, movedMeters, fleetOnline)) {
            lastTrackAt = now
            lastTrackLat = location.latitude
            lastTrackLon = location.longitude
            publishTrack(location)
        }
        if (fleetOnline && FleetLocationPolicy.shouldUpload(now, lastFleetAttempt, fleetPending)) {
            lastFleetAttempt = now
            publishFleet(true, location)
        } else if (!fleetOnline) {
            fleetMessage = "Offline · route saved on phone"
        }
    }

    private fun publishTrack(location: Location) {
        val pointTripId = tripId
        queuedPoints++
        val data = hashMapOf<String, Any?>(
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "accuracyMeters" to location.accuracy.toDouble(),
            "speedKmh" to latestKmh?.takeIf { it in 0..250 },
            "tripId" to pointTripId,
            "capturedAt" to captureTime(location),
            "uploadedAt" to FieldValue.serverTimestamp(),
        )
        FirebaseFirestore.getInstance()
            .document("fleets/$fleetId/vehicles/$vehicleId/track_points/${UUID.randomUUID()}")
            .set(data)
            .addOnSuccessListener {
                queuedPoints = (queuedPoints - 1).coerceAtLeast(0)
                if (pointTripId == tripId) trackError = null
            }
            .addOnFailureListener {
                queuedPoints = (queuedPoints - 1).coerceAtLeast(0)
                if (pointTripId == tripId) trackError = "Route history could not sync"
                Log.w("NavRide", "Route point write failed (no location logged)")
            }
    }

    private fun publishTripStart() {
        val pointTripId = tripId
        val data = hashMapOf<String, Any?>(
            "driverUid" to fleetUid,
            "startedAt" to tripStartedAt,
            "endedAt" to null,
            "updatedAt" to FieldValue.serverTimestamp(),
        )
        FirebaseFirestore.getInstance()
            .document("fleets/$fleetId/vehicles/$vehicleId/trips/$pointTripId")
            .set(data)
            .addOnSuccessListener {
                if (pointTripId == tripId) tripError = null
            }
            .addOnFailureListener {
                if (pointTripId == tripId) tripError = "Trip history could not sync"
                Log.w("NavRide", "Trip start write failed (no location logged)")
            }
    }

    private fun publishTripEnd() {
        if (tripId.isEmpty()) return
        val pointTripId = tripId
        val data = mapOf(
            "endedAt" to Date(System.currentTimeMillis()),
            "updatedAt" to FieldValue.serverTimestamp(),
        )
        FirebaseFirestore.getInstance()
            .document("fleets/$fleetId/vehicles/$vehicleId/trips/$pointTripId")
            .set(data, SetOptions.merge())
            .addOnSuccessListener {
                if (pointTripId == tripId) tripError = null
            }
            .addOnFailureListener {
                if (pointTripId == tripId) tripError = "Trip history could not sync"
                Log.w("NavRide", "Trip end write failed (no location logged)")
            }
    }

    private fun publishFleet(active: Boolean, location: Location? = null) {
        if (active && location == null) return
        if (FirebaseAuth.getInstance().currentUser?.uid != fleetUid || fleetId.isEmpty() || vehicleId.isEmpty()) {
            fleetPending = false
            fleetMessage = "Fleet session unavailable; not uploaded"
            return
        }
        val data = hashMapOf<String, Any?>(
            "latitude" to if (active) location?.latitude else null,
            "longitude" to if (active) location?.longitude else null,
            "speedKmh" to if (active) latestKmh?.takeIf { it in 0..250 } else null,
            "tripActive" to active,
            "capturedAt" to if (active) location?.let(::captureTime) else null,
            "updatedAt" to FieldValue.serverTimestamp(),
        )
        val version = ++fleetWriteVersion
        fleetPending = true
        fleetMessage = if (active) "Waiting for cloud sync" else "Trip ended locally; syncing final status"
        FirebaseFirestore.getInstance()
            .document("fleets/$fleetId/vehicles/$vehicleId/status/current")
            .set(data)
            .addOnSuccessListener {
                if (version != fleetWriteVersion) return@addOnSuccessListener
                fleetPending = false
                lastFleetSyncAt = SystemClock.elapsedRealtime()
                fleetMessage = if (active && fleetActive) "Shared with fleet" else "Trip ended; synced"
            }
            .addOnFailureListener {
                if (version != fleetWriteVersion) return@addOnFailureListener
                fleetPending = false
                fleetMessage = if (active && fleetActive) "Cloud upload failed; retrying" else "Trip ended locally; cloud sync failed"
                Log.w("NavRide", "Fleet status write failed (no location logged)")
            }
    }

    override fun onProviderDisabled(provider: String) {
        latestKmh = null
        message = "Turn on phone location"
        if (fleetActive) fleetMessage = "Turn on phone location to share this trip"
    }
    override fun onProviderEnabled(provider: String) { message = "Waiting for a GPS fix" }
    @Deprecated("Legacy Android callback")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onDestroy() {
        if (fleetActive) {
            fleetActive = false
            publishFleet(false)
            publishTripEnd()
        }
        val wasSendingSpeed = running
        running = false
        latestKmh = null
        acknowledgedAt = 0
        handler.removeCallbacksAndMessages(null)
        heartbeatScheduled = false
        runCatching { locations.removeUpdates(this) }
        runCatching { getSystemService(ConnectivityManager::class.java)
            .unregisterNetworkCallback(networkListener) }
        if (wasSendingSpeed) NavigationBleSender.sendSpeed(this, SpeedReading.packet(null))
        if (serviceStarted) stopForeground(STOP_FOREGROUND_REMOVE)
        serviceStarted = false
        Log.i("NavRide", "Location service stopped")
        super.onDestroy()
    }
}
