package com.thanhhao.esp32_navride

import android.Manifest
import android.annotation.SuppressLint
import android.app.*
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.*
import android.util.Log

/** Opt-in location foreground service. Uses the existing BLE connection, not a second GATT. */
class SpeedService : Service(), LocationListener {
    companion object {
        @Volatile var running = false
            private set
        @Volatile private var latestKmh: Int? = null
        @Volatile private var fixAt = 0L
        @Volatile private var message = "Speed is off"
        @Volatile var acknowledgedAt = 0L
        private const val CHANNEL = "gps_speed"
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
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var locations: LocationManager
    private val heartbeat = object : Runnable {
        override fun run() {
            if (!running) return
            if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                message = "Location permission was removed"
                stopSelf()
                return
            }
            val speed = (status()["kmh"] as? Int).takeIf { locations.isProviderEnabled(LocationManager.GPS_PROVIDER) }
            NavigationBleSender.sendSpeed(this@SpeedService, SpeedReading.packet(speed))
            handler.postDelayed(this, 1_000)
        }
    }

    override fun onCreate() {
        super.onCreate()
        locations = getSystemService(LocationManager::class.java)
    }

    @SuppressLint("MissingPermission")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") {
            stopSelf()
            return START_NOT_STICKY
        }
        if (running) return START_NOT_STICKY
        try {
            val manager = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) {
                manager.createNotificationChannel(NotificationChannel(CHANNEL, "GPS speed", NotificationManager.IMPORTANCE_LOW))
            }
            val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val stop = PendingIntent.getService(this, 1, Intent(this, SpeedService::class.java).setAction("STOP"),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
            val notification = builder.setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setContentTitle("NavRide GPS speed")
                .setContentText("Sending GPS speed to ESP32 via Bluetooth")
                .setContentIntent(open).setOngoing(true)
                .addAction(Notification.Action.Builder(null, "Stop", stop).build()).build()
            if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            else startForeground(NOTIFICATION, notification)
            latestKmh = null
            fixAt = 0
            acknowledgedAt = 0
            locations.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1_000L, 0f, this, Looper.getMainLooper())
            running = true
            message = "Waiting for a GPS fix"
            handler.post(heartbeat)
            Log.i("NavRide", "GPS speed service started (Bluetooth; no coordinates recorded)")
        } catch (error: Exception) {
            message = "Could not start GPS. Check location permission and GPS settings."
            Log.w("NavRide", "GPS speed service could not start", error)
            stopSelf()
        }
        // Do not silently restart location collection after an explicit stop or process kill.
        return START_NOT_STICKY
    }

    override fun onLocationChanged(location: Location) {
        val age = (SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos) / 1_000_000
        latestKmh = SpeedReading.kmh(location.hasSpeed(), location.speed, age,
            if (Build.VERSION.SDK_INT >= 26 && location.hasSpeedAccuracy()) location.speedAccuracyMetersPerSecond else null)
        fixAt = SystemClock.elapsedRealtime() - age
        message = if (latestKmh != null) "GPS speed active" else "Waiting for a reliable GPS speed"
    }

    override fun onProviderDisabled(provider: String) {
        latestKmh = null
        message = "Turn on phone location"
    }
    override fun onProviderEnabled(provider: String) { message = "Waiting for a GPS fix" }
    @Deprecated("Legacy Android callback")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onDestroy() {
        running = false
        latestKmh = null
        acknowledgedAt = 0
        handler.removeCallbacksAndMessages(null)
        runCatching { locations.removeUpdates(this) }
        NavigationBleSender.sendSpeed(this, SpeedReading.packet(null))
        stopForeground(STOP_FOREGROUND_REMOVE)
        Log.i("NavRide", "GPS speed service stopped")
        super.onDestroy()
    }
}
