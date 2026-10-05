package com.thanhhao.esp32_navride

import android.app.Notification
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class OsmAndNotificationListener : NotificationListenerService() {
    private var lastPayload = ""
    private var lastSentAt = 0L
    private var aidlBridge: OsmAndAidlBridge? = null
    private val handler = Handler(Looper.getMainLooper())
    private var routeNotificationKey: String? = null
    private var pendingClear: Runnable? = null
    private val rebindTask = Runnable {
        if (activeListener == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            Log.w("NavRide", "Notification listener disconnected; requesting system rebind")
            requestRebind(ComponentName(this, OsmAndNotificationListener::class.java))
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        handler.removeCallbacks(rebindTask)
        activeListener = this
        recovering = false
        Log.i("NavRide", "Notification listener connected")
        if (!NavigationBridgeStore.deviceId(this).isNullOrBlank()) {
            restartAidlBridge()
        }
    }

    override fun onListenerDisconnected() {
        pendingClear?.let(handler::removeCallbacks)
        pendingClear = null
        routeNotificationKey = null
        aidlBridge?.stop()
        aidlBridge = null
        if (activeListener === this) activeListener = null
        handler.postDelayed(rebindTask, 1_000)
        super.onListenerDisconnected()
    }

    override fun onDestroy() {
        pendingClear?.let(handler::removeCallbacks)
        handler.removeCallbacks(rebindTask)
        pendingClear = null
        routeNotificationKey = null
        aidlBridge?.stop()
        aidlBridge = null
        if (activeListener === this) activeListener = null
        super.onDestroy()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (!sbn.packageName.startsWith("net.osmand")) return
        if (NavigationBridgeStore.deviceId(this).isNullOrBlank()) return

        val raw = notificationText(sbn)
        OsmAndNotificationParser.parseStreet(raw).takeIf(String::isNotBlank)
            ?.let(NavigationBleSender::updateStreetName)
        val parsed = OsmAndNotificationParser.parse(raw)
        if (parsed != null &&
            (sbn.notification.flags and Notification.FLAG_ONGOING_EVENT) != 0
        ) {
            routeNotificationKey = sbn.key
            pendingClear?.let(handler::removeCallbacks)
            pendingClear = null
        }
        // A subscription alone does not guarantee any callbacks. Keep fallback
        // available until the API has actually supplied a recent direction.
        if (OsmAndAidlState.subscribed && OsmAndAidlState.lastApiDirectionAt > 0 &&
            SystemClock.elapsedRealtime() - OsmAndAidlState.lastApiDirectionAt < 5000
        ) return
        // A quiet AIDL subscription may still have the complete next-turn
        // snapshot. Prefer its real exit angle over notification text, which
        // only supplies an exit ordinal and would swap the roundabout shape.
        if (aidlBridge?.refreshNavigation() == true) return
        if (parsed == null) return
        OsmAndAidlState.lastDirectionAt = SystemClock.elapsedRealtime()
        val payload = "${parsed.maneuver}:${parsed.exitNumber}:${parsed.distanceMeters}:${parsed.streetName}"
        val now = SystemClock.elapsedRealtime()
        if (payload == lastPayload && now - lastSentAt < 5000) return
        if (NavigationBleSender.sendNavigation(this, parsed)) {
            lastPayload = payload
            lastSentAt = now
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        if (sbn.key != routeNotificationKey) return
        routeNotificationKey = null
        scheduleRouteClear()
    }

    private fun scheduleRouteClear(retryCount: Int = 0) {
        if (pendingClear != null) return
        val task = Runnable {
            pendingClear = null
            if (activeListener !== this || routeNotificationKey != null ||
                NavigationBridgeStore.deviceId(this).isNullOrBlank()) return@Runnable
            val hasRouteNotification = runCatching { activeNotifications }.getOrNull()
                ?.any { it.packageName.startsWith("net.osmand") &&
                    (it.notification.flags and Notification.FLAG_ONGOING_EVENT) != 0 &&
                    OsmAndNotificationParser.parse(notificationText(it)) != null } == true
            if (!hasRouteNotification && aidlBridge?.hasActiveTurn() != true) {
                if (NavigationBleSender.clearNavigation(this)) {
                    lastPayload = ""
                    OsmAndAidlState.lastDirectionAt = 0L
                    OsmAndAidlState.lastApiDirectionAt = 0L
                    Log.i("NavRide", "Route ended; clearing ESP32 directions")
                } else if (retryCount < 3) {
                    handler.postDelayed({
                        if (activeListener === this) scheduleRouteClear(retryCount + 1)
                    }, 1_000)
                }
            }
        }
        pendingClear = task
        handler.postDelayed(task, 2000)
    }

    private fun notificationText(sbn: StatusBarNotification): String {
        val extras = sbn.notification.extras
        // Preserve the boundary between the turn title, road and trip summary.
        return buildList {
            extras.getCharSequence(Notification.EXTRA_TITLE)?.let(::add)
            extras.getCharSequence(Notification.EXTRA_TEXT)?.let(::add)
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.let(::add)
            extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)?.forEach(::add)
            extras.getCharSequenceArrayList(Notification.EXTRA_TEXT_LINES)?.forEach(::add)
        }.distinct().joinToString("\n")
    }

    companion object {
        @Volatile
        private var activeListener: OsmAndNotificationListener? = null
        private val recoveryHandler = Handler(Looper.getMainLooper())
        @Volatile private var recovering = false
        private var lastRecoveryAt = -30_000L

        fun isListening(): Boolean = activeListener != null
        fun isRecovering(): Boolean = recovering

        fun hasAccess(context: Context): Boolean {
            val component = ComponentName(context, OsmAndNotificationListener::class.java)
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                context.getSystemService(NotificationManager::class.java)
                    .isNotificationListenerAccessGranted(component)
            } else {
                Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
                    ?.split(':')?.contains(component.flattenToString()) == true
            }
        }

        // Repair a stale system binding without changing the user's access grant.
        // Only one bounded recovery can run; never disturb a live listener.
        fun recoverListener(context: Context) {
            if (activeListener != null || recovering || !hasAccess(context)) return
            val now = SystemClock.elapsedRealtime()
            if (now - lastRecoveryAt < 30_000) return
            lastRecoveryAt = now
            recovering = true
            val app = context.applicationContext
            val component = ComponentName(app, OsmAndNotificationListener::class.java)
            runCatching {
                app.packageManager.setComponentEnabledSetting(component,
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
                requestRebind(component)
            }.onFailure { Log.w("NavRide", "Listener rebind request failed", it) }
            recoveryHandler.postDelayed({
                if (activeListener != null || !hasAccess(app)) {
                    recovering = false
                    return@postDelayed
                }
                Log.i("NavRide", "Repairing stale notification listener binding")
                runCatching {
                    app.packageManager.setComponentEnabledSetting(component,
                        PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
                }.onFailure { Log.w("NavRide", "Listener restart failed", it) }
                recoveryHandler.postDelayed({
                    // Always re-enable, even if access was revoked during recovery.
                    runCatching {
                        app.packageManager.setComponentEnabledSetting(component,
                            PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
                        if (hasAccess(app)) requestRebind(component)
                    }.onFailure { Log.w("NavRide", "Listener enable failed", it) }
                    recoveryHandler.postDelayed({ recovering = false }, 5_000)
                }, 500)
            }, 2_000)
        }

        fun replayActiveNavigation() {
            val listener = activeListener ?: return
            listener.handler.post {
                if (activeListener !== listener || !NavigationBleSender.isConnected()) return@post
                listener.lastPayload = ""
                if (listener.aidlBridge?.refreshNavigation() == true) return@post
                val routeNotifications = runCatching { listener.activeNotifications }.getOrNull()
                    ?.filter { it.packageName.startsWith("net.osmand") &&
                        (it.notification.flags and Notification.FLAG_ONGOING_EVENT) != 0 }
                    .orEmpty()
                routeNotifications.forEach(listener::onNotificationPosted)
                if (routeNotifications.none {
                        OsmAndNotificationParser.parse(listener.notificationText(it)) != null
                    }) listener.scheduleRouteClear()
            }
        }

        fun requestRouteClear() {
            val listener = activeListener ?: return
            listener.handler.post { listener.scheduleRouteClear() }
        }

        fun ensureBridge(context: Context) {
            val listener = activeListener
            if (listener != null) {
                listener.restartAidlBridge()
            } else {
                recoverListener(context)
            }
        }

        fun stopBridge() {
            activeListener?.aidlBridge?.stop()
            activeListener?.aidlBridge = null
        }
    }

    private fun restartAidlBridge() {
        // Connect before starting a route, so the app can offer Open OsmAnd and
        // test samples without waiting for the first navigation notification.
        NavigationBleSender.send(applicationContext,
            "{\"apiVersion\":1,\"command\":\"ping\",\"timestamp\":${System.currentTimeMillis() / 1000}}")
        if (aidlBridge == null || !OsmAndAidlState.subscribed) {
            aidlBridge?.stop()
            aidlBridge = OsmAndAidlBridge(applicationContext).also { it.start() }
        }
        if (NavigationBleSender.isConnected()) replayActiveNavigation()
    }
}
