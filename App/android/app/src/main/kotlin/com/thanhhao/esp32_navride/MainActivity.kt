package com.thanhhao.esp32_navride

import android.Manifest
import android.bluetooth.BluetoothManager
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.google.firebase.auth.FirebaseAuth
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val navigationChannelName = "esp32_navride/navigation"
    private val updateChannelName = "esp32_navride/update"
    private var locationPermissionResult: MethodChannel.Result? = null
    private var pendingLocationStart: Intent? = null

    private fun startSpeed(result: MethodChannel.Result) {
        if (!NavigationBleSender.isConnected()) {
            result.error("not_connected", "Connect ESP32 via Bluetooth first.", null)
            return
        }
        startLocationService(result, Intent(this, SpeedService::class.java).setAction(SpeedService.START_SPEED))
    }

    private fun startFleetTrip(result: MethodChannel.Result, fleetId: String, vehicleId: String) {
        if (FirebaseAuth.getInstance().currentUser == null) {
            result.error("not_signed_in", "Sign in to your fleet account first.", null)
            return
        }
        if (!fleetId.matches(Regex("[A-Za-z0-9_-]{1,64}")) ||
            !vehicleId.matches(Regex("[A-Za-z0-9_-]{1,64}"))) {
            result.error("invalid_vehicle", "Enter a valid fleet and vehicle ID.", null)
            return
        }
        if (SpeedService.fleetActive) {
            result.error("trip_busy", "End the current trip first.", null)
            return
        }
        startLocationService(result, Intent(this, SpeedService::class.java)
            .setAction(SpeedService.START_FLEET)
            .putExtra("fleetId", fleetId)
            .putExtra("vehicleId", vehicleId))
    }

    private fun startLocationService(result: MethodChannel.Result, intent: Intent) {
        val locations = getSystemService(android.location.LocationManager::class.java)
        if (!locations.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER)) {
            result.error("gps_disabled", "Turn on phone location, then try again.", null)
            return
        }
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            if (locationPermissionResult != null) {
                result.error("permission_pending", "Finish the location permission request first.", null)
                return
            }
            locationPermissionResult = result
            pendingLocationStart = intent
            val permissions = mutableListOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
            if (Build.VERSION.SDK_INT >= 33) permissions.add(Manifest.permission.POST_NOTIFICATIONS)
            requestPermissions(permissions.toTypedArray(), 7301)
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
            result.success(true)
        } catch (error: Exception) {
            result.error("gps_start_failed", "Could not start GPS. Keep NavRide open and try again.", null)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7301) {
            val result = locationPermissionResult ?: return
            val intent = pendingLocationStart ?: return
            locationPermissionResult = null
            pendingLocationStart = null
            if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
                startLocationService(result, intent)
            } else {
                result.error("location_denied", "Precise location is required for GPS sharing. Navigation still works without it.", null)
            }
        }
    }

    override fun onDestroy() {
        locationPermissionResult?.error("activity_closed", "Open NavRide to start GPS.", null)
        locationPermissionResult = null
        pendingLocationStart = null
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        NavigationBridgeStore.deviceId(this)?.takeIf { it.isNotBlank() }?.let {
            NavigationBleSender.connectSaved(this, it)
        }
        // Retry after the user enables this app in OsmAnd's Plugins screen,
        // or after Android restarts the activity. Keep an active bridge intact.
        if (notificationAccessGranted() &&
            !NavigationBridgeStore.deviceId(this).isNullOrBlank() &&
            (!OsmAndNotificationListener.isListening() ||
                !OsmAndAidlState.subscribed || !NavigationBleSender.isConnected())
        ) {
            OsmAndNotificationListener.ensureBridge(this)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FleetHistorySync.get(this).requestSync()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, navigationChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSpeedStatus" -> result.success(SpeedService.status())
                    "getFleetStatus" -> result.success(SpeedService.fleetStatus(this))
                    "retryFleetSync" -> {
                        FleetHistorySync.get(this).requestSync(force = true)
                        result.success(true)
                    }
                    "startSpeed" -> startSpeed(result)
                    "stopSpeed" -> {
                        startService(Intent(this, SpeedService::class.java).setAction(SpeedService.STOP_SPEED))
                        result.success(true)
                    }
                    "startFleetTrip" -> startFleetTrip(
                        result,
                        call.argument<String>("fleetId")?.trim().orEmpty(),
                        call.argument<String>("vehicleId")?.trim().orEmpty(),
                    )
                    "stopFleetTrip" -> {
                        startService(Intent(this, SpeedService::class.java).setAction(SpeedService.STOP_FLEET))
                        result.success(true)
                    }
                    "openFleetDashboard" -> {
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW,
                                android.net.Uri.parse("https://navride-96851.web.app")))
                            result.success(true)
                        } catch (_: Exception) {
                            result.error("dashboard_unavailable", "Could not open the fleet dashboard.", null)
                        }
                    }
                    "sendSpeedSample" -> {
                        result.success(!SpeedService.running &&
                            NavigationBleSender.sendSpeed(this, SpeedReading.packet(42)))
                    }
                    "configureOsmAndBridge" -> {
                        val deviceId = call.argument<String>("deviceId")?.trim().orEmpty()
                        if (deviceId.isEmpty()) {
                            result.error("invalid_device", "No Bluetooth device selected.", null)
                        } else {
                            NavigationBleSender.connectSaved(this, deviceId, restartPending = true)
                            if (notificationAccessGranted()) {
                                OsmAndNotificationListener.ensureBridge(this)
                            }
                            result.success(osmandBridgeStatus())
                        }
                    }
                    "getOsmAndBridgeStatus" -> result.success(osmandBridgeStatus())
                    "recoverNavigationConnection" -> {
                        OsmAndNotificationListener.ensureBridge(this)
                        result.success(true)
                    }
                    "openOsmAnd" -> {
                        val app = OsmAndPackages.installed(this)
                        val intent = app?.let { packageManager.getLaunchIntentForPackage(it) }
                        if (intent == null) {
                            result.error("osmand_missing", "Install OsmAnd to start navigation.", null)
                        } else {
                            try {
                                startActivity(intent)
                                result.success(true)
                            } catch (error: Exception) {
                                result.error("osmand_open_failed", "Could not open OsmAnd. Open it from your home screen.", null)
                            }
                        }
                    }
                    "openNotificationAccessSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(true)
                    }
                    "sendOsmAndSample" -> {
                        val maneuver = call.argument<String>("maneuver") ?: "right"
                        val distanceMeters = call.argument<Int>("distanceMeters") ?: 250
                        val streetName = call.argument<String>("streetName") ?: "Nguyen Hue"
                        result.success(
                            NavigationBleSender.sendSample(
                                this,
                                maneuver,
                                distanceMeters,
                                streetName,
                            ),
                        )
                    }
                    "sendBleCommand" -> {
                        val payload = call.argument<String>("payload").orEmpty()
                        result.success(payload.isNotBlank() && NavigationBleSender.send(this, payload))
                    }
                    "disableOsmAndBridge" -> {
                        NavigationBridgeStore.clear(this)
                        startService(Intent(this, SpeedService::class.java).setAction(SpeedService.STOP_SPEED))
                        OsmAndNotificationListener.stopBridge()
                        NavigationBleSender.close()
                        result.success(true)
                    }
                    "clearLocalData" -> {
                        if (SpeedService.fleetActive || SpeedService.fleetStatus(this)["pending"] == true ||
                            FleetHistorySync.get(this).hasPending()) {
                            result.error("trip_active", "End the fleet trip and wait for cloud sync before deleting data.", null)
                            return@setMethodCallHandler
                        }
                        NavigationBridgeStore.clear(this)
                        stopService(Intent(this, SpeedService::class.java))
                        OsmAndNotificationListener.stopBridge()
                        NavigationBleSender.close()
                        val updates = File(cacheDir, "esp32-navride-updates")
                        if (updates.exists() && !updates.deleteRecursively()) {
                            result.error("clear_failed", "Could not delete cached updates. Try again.", null)
                        } else result.success(true)
                    }
                    "openAppPrivacySettings" -> {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName")))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "getCacheDirectory" -> result.success(cacheDir.absolutePath)
                        "getAppVersion" -> result.success(currentVersion())
                        "installApk" -> {
                            val path = call.argument<String>("path")
                            require(!path.isNullOrBlank()) { "APK path is missing." }
                            installApk(path)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("install_failed", error.message, null)
                }
            }
    }

    private fun notificationAccessGranted(): Boolean =
        OsmAndNotificationListener.hasAccess(this)

    private fun osmandBridgeStatus(): Map<String, Boolean> {
        val configured = !NavigationBridgeStore.deviceId(this).isNullOrBlank()
        val bluetoothPermission = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED
        val bluetoothEnabled = bluetoothPermission &&
            getSystemService(BluetoothManager::class.java)?.adapter?.isEnabled == true
        val notificationAccess = notificationAccessGranted()
        val listenerConnected = OsmAndNotificationListener.isListening()
        val osmandInstalled = OsmAndPackages.installed(this) != null
        return mapOf(
            "configured" to configured,
            "notificationAccess" to notificationAccess,
            "listenerConnected" to listenerConnected,
            "listenerRecovering" to OsmAndNotificationListener.isRecovering(),
            "osmandInstalled" to osmandInstalled,
            "bluetoothReady" to bluetoothEnabled,
            "aidlConnected" to OsmAndAidlState.connected,
            "aidlSubscribed" to OsmAndAidlState.subscribed,
            "osmandDataRecent" to OsmAndAidlState.directionReceivedRecently(),
            "bleConnected" to NavigationBleSender.isConnected(),
            "bleConnecting" to NavigationBleSender.isConnecting(),
            "blePairing" to NavigationBleSender.isPairing(),
            "lastNavigationConfirmed" to NavigationBleSender.lastNavigationConfirmed(),
            "modeCommandConfirmed" to NavigationBleSender.modeCommandConfirmed(),
            "wifiCommandConfirmed" to NavigationBleSender.wifiCommandConfirmed(),
            "popupCommandConfirmed" to NavigationBleSender.popupCommandConfirmed(),
            "ready" to (
                configured && notificationAccess && listenerConnected && osmandInstalled && bluetoothEnabled
            ),
        )
    }

    @Suppress("DEPRECATION")
    private fun currentVersion(): Map<String, Any> {
        val info = packageManager.getPackageInfo(packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            info.versionCode.toLong()
        }
        return mapOf(
            "versionName" to (info.versionName ?: ""),
            "versionCode" to code.toInt(),
        )
    }

    @Suppress("DEPRECATION")
    private fun fingerprints(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners
        } else {
            info.signatures
        }
        return signatures?.map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
                .joinToString("") { "%02x".format(it) }
        }?.toSet() ?: emptySet()
    }

    @Suppress("DEPRECATION")
    private fun installApk(path: String) {
        val apk = File(path).canonicalFile
        val allowedDirectory = File(cacheDir, "esp32-navride-updates").canonicalFile
        require(apk.parentFile == allowedDirectory && apk.extension == "apk" && apk.isFile) {
            "Download and verify the update before installing."
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        val candidate = packageManager.getPackageArchiveInfo(apk.path, flags)
            ?: throw IllegalArgumentException("The downloaded APK is invalid.")
        val installed = packageManager.getPackageInfo(packageName, flags)
        require(candidate.packageName == packageName) {
            "This update is not for ESP32-NavRide."
        }
        val candidateCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            candidate.longVersionCode
        } else {
            candidate.versionCode.toLong()
        }
        val installedCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            installed.longVersionCode
        } else {
            installed.versionCode.toLong()
        }
        require(candidateCode > installedCode) {
            "This APK is not newer than the installed version."
        }
        val candidateSigners = fingerprints(candidate)
        require(candidateSigners.isNotEmpty() && candidateSigners == fingerprints(installed)) {
            "The APK signature does not match the installed app."
        }
        require((candidate.applicationInfo?.flags ?: 0) and ApplicationInfo.FLAG_DEBUGGABLE == 0) {
            "A debug build cannot be installed as an update."
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ),
            )
            throw IllegalStateException(
                "Allow ESP32-NavRide to install unknown apps, then try again.",
            )
        }
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            apk,
        )
        startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
    }
}
