package com.thanhhao.esp32_navride

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.util.Log
import android.view.KeyEvent
import kotlin.math.roundToInt
import net.osmand.aidlapi.IOsmAndAidlCallback
import net.osmand.aidlapi.IOsmAndAidlInterface
import net.osmand.aidlapi.gpx.AGpxBitmap
import net.osmand.aidlapi.logcat.OnLogcatMessageParams
import net.osmand.aidlapi.navigation.ADirectionInfo
import net.osmand.aidlapi.navigation.ANavigationUpdateParams
import net.osmand.aidlapi.navigation.ANavigationVoiceRouterMessageParams
import net.osmand.aidlapi.navigation.OnVoiceNavigationParams
import net.osmand.aidlapi.search.SearchResult

internal object OsmAndPackages {
    private val packageNames = listOf("net.osmand.plus", "net.osmand", "net.osmand.dev")

    fun isAllowed(packageName: String): Boolean = packageName in packageNames

    fun installed(context: Context): String? = packageNames.firstOrNull { packageName ->
        runCatching { context.packageManager.getApplicationInfo(packageName, 0) }.isSuccess
    }
}

internal object OsmAndAidlState {
    @Volatile
    var connected = false

    @Volatile
    var subscribed = false

    @Volatile
    var lastDirectionAt = 0L

    @Volatile
    var lastApiDirectionAt = 0L

    fun directionReceivedRecently(): Boolean =
        lastDirectionAt > 0 && SystemClock.elapsedRealtime() - lastDirectionAt < 120_000
}

internal class OsmAndAidlBridge(context: Context) {
    private val appContext = context.applicationContext
    @Volatile private var service: IOsmAndAidlInterface? = null
    private var callbackId = -1L
    private var voiceCallbackId = -1L
    private var bound = false
    private var snapshotFailureReported = false
    private var reportedTurnKeys: String? = null

    private val callback = object : IOsmAndAidlCallback.Stub() {
        override fun updateNavigationInfo(directionInfo: ADirectionInfo) {
            val snapshot = readNextTurn()
            val navigation = snapshot ?: OsmAndDirectionMapper.map(
                directionInfo.turnType,
                directionInfo.distanceTo,
                directionInfo.isLeftSide,
            )
            if (navigation == null) {
                OsmAndNotificationListener.requestRouteClear()
                return
            }
            OsmAndAidlState.lastDirectionAt = SystemClock.elapsedRealtime()
            // The callback's bare turn type lacks the roundabout exit and
            // angle; only the complete snapshot should suppress notification
            // fallback or be treated as the authoritative icon.
            OsmAndAidlState.lastApiDirectionAt =
                if (snapshot != null) OsmAndAidlState.lastDirectionAt else 0L
            NavigationBleSender.sendNavigation(
                appContext,
                navigation,
            )
        }

        override fun onSearchComplete(resultSet: MutableList<SearchResult>?) = Unit
        override fun onUpdate() = Unit
        override fun onAppInitialized() = Unit
        override fun onGpxBitmapCreated(bitmap: AGpxBitmap?) = Unit
        override fun onContextMenuButtonClicked(buttonId: Int, pointId: String?, layerId: String?) = Unit
        override fun onVoiceRouterNotify(params: OnVoiceNavigationParams?) {
            // Spoken guidance can contain a road name even when the Android
            // navigation notification omits it. The direction API stays the
            // source of truth for maneuver and distance.
            params?.played?.forEach { message ->
                OsmAndNotificationParser.parseStreet(message)
                    .takeIf(String::isNotBlank)
                    ?.let(NavigationBleSender::updateStreetName)
            }
        }
        override fun onKeyEvent(keyEvent: KeyEvent?) = Unit
        override fun onLogcatMessage(params: OnLogcatMessageParams?) = Unit
    }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            service = IOsmAndAidlInterface.Stub.asInterface(binder)
            OsmAndAidlState.connected = true
            val params = ANavigationUpdateParams().apply {
                setSubscribeToUpdates(true)
            }
            callbackId = runCatching {
                service?.registerForNavigationUpdates(params, callback) ?: -1L
            }.onFailure { Log.w("NavRide", "OsmAnd direction subscription failed", it) }.getOrDefault(-1L)
            voiceCallbackId = runCatching {
                service?.registerForVoiceRouterMessages(
                    ANavigationVoiceRouterMessageParams(), callback,
                ) ?: -1L
            }.onFailure { Log.w("NavRide", "OsmAnd voice subscription failed", it) }.getOrDefault(-1L)
            OsmAndAidlState.subscribed = callbackId >= 0
            Log.i("NavRide", "OsmAnd AIDL connected; direction subscription=$callbackId, voice=$voiceCallbackId")
            refreshNavigation()
        }

        override fun onServiceDisconnected(name: ComponentName) {
            service = null
            callbackId = -1L
            voiceCallbackId = -1L
            OsmAndAidlState.connected = false
            OsmAndAidlState.subscribed = false
            OsmAndAidlState.lastDirectionAt = 0L
            OsmAndAidlState.lastApiDirectionAt = 0L
        }

        override fun onBindingDied(name: ComponentName) = onServiceDisconnected(name)
        override fun onNullBinding(name: ComponentName) = onServiceDisconnected(name)
    }

    private fun readNextTurn(): OsmAndNavigation? = runCatching {
        val appInfo = service?.appInfo
        if (appInfo != null && appInfo.turnInfo == null && reportedTurnKeys != "(none)") {
            reportedTurnKeys = "(none)"
            Log.i("NavRide", "OsmAnd AppInfo received; turnInfo absent (no active turn); no documented speed-limit field")
        }
        appInfo?.turnInfo?.let { info ->
            // Diagnostic schema only: never log location, road names or other values.
            val keys = info.keySet().sorted().joinToString(",")
            if (keys != reportedTurnKeys) {
                reportedTurnKeys = keys
                Log.i("NavRide", "OsmAnd turnInfo keys=[$keys]; no documented speed-limit field")
            }
            OsmAndDirectionMapper.fromNextTurn(
                info.getString("next_turn_type"),
                info.getInt("next_turn_distance", -1),
                info.getString("next_turn_name"),
                OsmAndDirectionMapper.angleFromBundle(info.get("next_turn_angle")),
            )
        }
    }.onSuccess { snapshotFailureReported = false }.onFailure {
        if (!snapshotFailureReported) {
            Log.w("NavRide", "OsmAnd next-turn snapshot unavailable", it)
            snapshotFailureReported = true
        }
    }.getOrNull()

    fun hasActiveTurn(): Boolean = readNextTurn() != null

    fun refreshNavigation(): Boolean {
        val navigation = readNextTurn() ?: return false
        OsmAndAidlState.lastDirectionAt = SystemClock.elapsedRealtime()
        OsmAndAidlState.lastApiDirectionAt = OsmAndAidlState.lastDirectionAt
        return NavigationBleSender.sendNavigation(appContext, navigation)
    }

    fun start(): Boolean {
        if (bound) return true
        val packageName = OsmAndPackages.installed(appContext) ?: return false
        val intent = Intent("net.osmand.aidl.OsmandAidlServiceV2").setPackage(packageName)
        var flags = Context.BIND_AUTO_CREATE
        if (Build.VERSION.SDK_INT >= 34) flags = flags or Context.BIND_ALLOW_ACTIVITY_STARTS
        bound = runCatching { appContext.bindService(intent, connection, flags) }
            .onFailure { Log.w("NavRide", "OsmAnd AIDL bind failed", it) }.getOrDefault(false)
        if (!bound) Log.w("NavRide", "OsmAnd AIDL unavailable; using notification fallback")
        return bound
    }

    fun stop() {
        val currentService = service
        if (currentService != null && callbackId >= 0) {
            val params = ANavigationUpdateParams().apply {
                setSubscribeToUpdates(false)
                setCallbackId(callbackId)
            }
            runCatching { currentService.registerForNavigationUpdates(params, callback) }
        }
        if (currentService != null && voiceCallbackId >= 0) {
            val params = ANavigationVoiceRouterMessageParams().apply {
                setSubscribeToUpdates(false)
                setCallbackId(voiceCallbackId)
            }
            runCatching { currentService.registerForVoiceRouterMessages(params, callback) }
        }
        if (bound) runCatching { appContext.unbindService(connection) }
        bound = false
        service = null
        callbackId = -1L
        voiceCallbackId = -1L
        OsmAndAidlState.connected = false
        OsmAndAidlState.subscribed = false
        OsmAndAidlState.lastDirectionAt = 0L
        OsmAndAidlState.lastApiDirectionAt = 0L
    }
}
