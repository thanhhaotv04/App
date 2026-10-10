package com.thanhhao.esp32_navride

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothStatusCodes
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.text.Normalizer
import java.util.UUID
import kotlin.math.roundToInt

internal object NavigationBridgeStore {
    private const val preferencesName = "navigation_bridge"
    private const val deviceIdKey = "device_id"

    fun setDeviceId(context: Context, deviceId: String) {
        context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            .edit()
            .putString(deviceIdKey, deviceId)
            .apply()
    }

    fun deviceId(context: Context): String? = context
        .getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
        .getString(deviceIdKey, null)

    fun clear(context: Context) {
        context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .apply()
    }
}

internal object NavigationBleSender {
    private const val requestedMtu = 185
    private const val minimumPacketMtu = 183 // max 180-byte JSON + ATT header
    private const val reconnectWindowMs = 20_000L // matches ESP32 advertising timeout
    private val reconnectHandler by lazy { Handler(Looper.getMainLooper()) }
    private val serviceUuid = UUID.fromString("7e6d0001-5b1a-4d8f-9a2c-320001000001")
    private val commandUuid = UUID.fromString("7e6d0002-5b1a-4d8f-9a2c-320001000002")
    private val statusUuid = UUID.fromString("7e6d0003-5b1a-4d8f-9a2c-320001000003")
    private val cccdUuid = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    private var gatt: BluetoothGatt? = null
    private var commandCharacteristic: BluetoothGattCharacteristic? = null
    private var pendingPayload: ByteArray? = null
    private var pendingIsNavigation = false
    private var inFlightPayload: ByteArray? = null
    private var inFlightIsNavigation = false
    private var controlRequestId = 0
    private var writing = false
    private var servicesRequested = false
    private var channelReady = false
    private var negotiatedMtu = 23
    private var bondWaitStartedAt = 0L
    private var nextRequestId = 0
    private var wantedRequestId = 0
    private var acknowledgedRequestId = 0
    private var reconnectContext: Context? = null
    private var reconnectAttempt = 0
    private var reconnectScheduled = false
    private var reconnectStartedAt = -1L
    @Volatile private var reconnectEnabled = false
    @Volatile private var connected = false
    @Volatile private var streetName = ""
    @Volatile private var streetUpdatedAt = 0L
    @Volatile private var modeConfirmed = false
    @Volatile private var wifiSavedConfirmed = false
    @Volatile private var popupConfirmed = false

    private fun displayStreet(value: String): String = Normalizer
        .normalize(value.replace('đ', 'd').replace('Đ', 'D'), Normalizer.Form.NFD)
        .replace(Regex("\\p{M}+"), "")
        .replace(Regex("[^ -~]"), " ")
        .trim()
        .take(32)

    @Synchronized
    fun isConnected(): Boolean = connected && channelReady

    @Synchronized
    fun isConnecting(): Boolean = !isConnected() && (gatt != null || reconnectScheduled)

    @Synchronized
    fun isPairing(): Boolean = bondWaitStartedAt != 0L

    // Một chủ sở hữu BLE trên Android; quyền OsmAnd không quyết định kết nối ESP32.
    @Synchronized
    fun connectSaved(context: Context, deviceId: String, restartPending: Boolean = false): Boolean {
        val changedDevice = NavigationBridgeStore.deviceId(context) != deviceId
        if (changedDevice || (restartPending && !isConnected() && !isPairing())) {
            close()
        }
        if (changedDevice) {
            NavigationBridgeStore.setDeviceId(context, deviceId)
        }
        retryConnection()
        // Reconnect không được phá kênh tốt hoặc ngắt hộp thoại nhập PIN đang mở.
        if (isConnected() || gatt != null) return true
        return send(context, "{\"apiVersion\":1,\"command\":\"ping\",\"timestamp\":${System.currentTimeMillis() / 1000}}")
    }
    fun modeCommandConfirmed(): Boolean = modeConfirmed
    fun wifiCommandConfirmed(): Boolean = wifiSavedConfirmed
    fun popupCommandConfirmed(): Boolean = popupConfirmed

    @Synchronized
    fun lastNavigationConfirmed(): Boolean =
        // A stationary route may not change for minutes. Its matching ACK
        // remains valid until a new direction or a disconnection, not 60 s.
        connected && wantedRequestId > 0 && acknowledgedRequestId == wantedRequestId

    @SuppressLint("MissingPermission")
    fun sendSample(
        context: Context,
        maneuver: String,
        distanceMeters: Int,
        streetName: String,
    ): Boolean {
        val roundaboutSample = when (maneuver) {
            "roundabout_1" -> OsmAndNavigation("roundabout", distanceMeters, streetName, 1, 110)
            "roundabout_2", "roundabout" -> OsmAndNavigation("roundabout", distanceMeters, streetName, 2, 0)
            "roundabout_3" -> OsmAndNavigation("roundabout", distanceMeters, streetName, 3, -80)
            "roundabout_4" -> OsmAndNavigation("roundabout", distanceMeters, streetName, 4, -100)
            "roundabout_5" -> OsmAndNavigation("roundabout", distanceMeters, streetName, 5, -115)
            "roundabout_6" -> OsmAndNavigation("roundabout", distanceMeters, streetName, 6, -125)
            else -> null
        }
        if (roundaboutSample == null && maneuver !in setOf(
                "left", "slight_left", "sharp_left", "keep_left",
                "right", "slight_right", "sharp_right", "keep_right",
                "straight", "u_turn", "u_turn_right", "off_route",
            )) return false
        if (distanceMeters !in 0..999_999) return false
        val sent = sendNavigation(
            context,
            roundaboutSample ?: OsmAndNavigation(maneuver, distanceMeters, streetName),
        )
        if (sent) {
            val sampleRequestId = synchronized(this) { wantedRequestId }
            val appContext = context.applicationContext
            reconnectHandler.postDelayed({
                synchronized(NavigationBleSender) {
                    // Never erase a live OsmAnd turn that arrived after this demo.
                    if (wantedRequestId == sampleRequestId && isConnected()) {
                        clearNavigation(appContext)
                    }
                }
            }, 15_000)
        }
        return sent
    }

    @Synchronized
    fun sendNavigation(context: Context, navigation: OsmAndNavigation): Boolean {
        if (navigation.streetName.isNotBlank()) {
            updateStreetName(navigation.streetName)
        }
        val requestId = if (nextRequestId == Int.MAX_VALUE) 1 else nextRequestId + 1
        nextRequestId = requestId
        val payload = encodeNavigationPacket(
            navigation,
            requestId,
            System.currentTimeMillis() / 1000,
        )
        val queued = send(context, payload)
        if (queued) wantedRequestId = requestId
        return queued
    }

    internal fun encodeNavigationPacket(navigation: OsmAndNavigation, requestId: Int, timestamp: Long): String {
        val packet = JSONObject()
            .put("apiVersion", 1)
            .put("command", "navigation")
            .put("maneuver", navigation.maneuver)
            .put("distance_m", navigation.distanceMeters.coerceIn(0, 999_999))
            .put("street", displayStreet(navigation.streetName))
            .put("requestId", requestId)
            .put("timestamp", timestamp)
        navigation.exitNumber?.takeIf { it in 1..99 }?.let { packet.put("exit", it) }
        navigation.turnAngle?.takeIf { it in -180..180 }?.let { packet.put("angle", it) }
        // JSON escapes (quotes/backslashes) count toward the actual ATT limit.
        var payload = packet.toString()
        while (payload.toByteArray(StandardCharsets.UTF_8).size > 180 &&
            packet.getString("street").isNotEmpty()) {
            packet.put("street", packet.getString("street").dropLast(1))
            payload = packet.toString()
        }
        return payload
    }

    fun updateStreetName(value: String) {
        if (value.isNotBlank()) {
            streetName = displayStreet(value)
            streetUpdatedAt = SystemClock.elapsedRealtime()
        }
    }

    fun currentStreetName(): String =
        if (SystemClock.elapsedRealtime() - streetUpdatedAt < 30_000) streetName else ""

    fun clearNavigation(context: Context): Boolean =
        send(context, "{\"apiVersion\":1,\"command\":\"clear_navigation\"}")

    // Telemetry is disposable and must never replace queued directions/settings.
    @Synchronized
    fun sendSpeed(context: Context, payload: String): Boolean {
        if (!isConnected() || writing || pendingPayload != null) return false
        return send(context, payload)
    }

    private fun discardStaleSpeed() {
        if (pendingPayload?.toString(StandardCharsets.UTF_8)?.contains("\"command\":\"speed\"") == true)
            pendingPayload = null
    }

    @SuppressLint("MissingPermission")
    @Synchronized
    fun send(context: Context, payload: String): Boolean {
        // GPS heartbeats and route updates must not restart an expired retry window.
        if (!reconnectEnabled && reconnectContext != null) return false
        val deviceId = NavigationBridgeStore.deviceId(context) ?: return false
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val bytes = payload.toByteArray(StandardCharsets.UTF_8)
        if (bytes.size > requestedMtu - 3) {
            Log.w("NavRide", "BLE command exceeds configured MTU limit: ${bytes.size}/$requestedMtu")
            return false
        }
        if (channelReady && bytes.size > negotiatedMtu - 3) {
            Log.w("NavRide", "BLE command too large for negotiated MTU: ${bytes.size}/$negotiatedMtu")
            return false
        }
        val packet = runCatching { JSONObject(payload) }.getOrNull() ?: return false
        val command = packet.optString("command")
        val isNavigation = command == "navigation"
        // Keep at most one pending command. A newer direction can replace an
        // older direction, but must never replace settings or a notification.
        if (pendingPayload != null && !pendingIsNavigation) return false
        when (command) {
            "set_mode" -> modeConfirmed = false
            "configure_wifi" -> wifiSavedConfirmed = false
            "push_notification", "push_task" -> popupConfirmed = false
            "clear_popup", "clear_navigation" -> {
                wantedRequestId = 0
                acknowledgedRequestId = 0
                streetName = ""
                streetUpdatedAt = 0L
            }
        }
        if (command in setOf("set_mode", "configure_wifi", "push_notification", "push_task")) {
            controlRequestId = packet.optInt("requestId")
        }
        pendingPayload = bytes
        pendingIsNavigation = isNavigation
        reconnectContext = context.applicationContext
        reconnectEnabled = true

        val characteristic = commandCharacteristic
        if (gatt != null && characteristic != null && channelReady) {
            return writing || writePending(gatt!!, characteristic)
        }
        if (gatt != null) return true
        return connectGatt(context.applicationContext, deviceId)
    }

    @SuppressLint("MissingPermission")
    private fun connectGatt(context: Context, deviceId: String): Boolean {
        if (!reconnectEnabled || gatt != null) return gatt != null
        if (reconnectStartedAt >= 0 &&
            SystemClock.elapsedRealtime() - reconnectStartedAt >= reconnectWindowMs) {
            stopAutoReconnect()
            return false
        }
        val manager = context.getSystemService(BluetoothManager::class.java)
        val adapter = manager?.adapter ?: run {
            scheduleReconnect()
            return false
        }
        val device = runCatching { adapter.getRemoteDevice(deviceId) }.getOrNull()
            ?: run {
                scheduleReconnect()
                return false
            }
        val connection = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
            } else {
                device.connectGatt(context, false, callback)
            }
        }.getOrNull()
        if (connection == null) {
            Log.w("NavRide", "BLE connectGatt returned null; scheduling retry")
            scheduleReconnect()
            return false
        }
        gatt = connection
        Log.i("NavRide", "BLE connecting to saved ESP32 device")
        reconnectHandler.postDelayed({
            synchronized(NavigationBleSender) {
                if (gatt === connection && !channelReady) {
                    connection.disconnect()
                    connection.close()
                    gatt = null
                    connected = false
                    servicesRequested = false
                    negotiatedMtu = 23
                    scheduleReconnect()
                }
            }
        }, 15_000)
        return true
    }

    private fun scheduleReconnect() {
        if (!reconnectEnabled || reconnectScheduled) return
        val now = SystemClock.elapsedRealtime()
        if (reconnectStartedAt < 0) reconnectStartedAt = now
        val remaining = reconnectWindowMs - (now - reconnectStartedAt)
        if (remaining <= 0) {
            stopAutoReconnect()
            return
        }
        val delay = minOf(4_000L, 1_000L shl reconnectAttempt.coerceAtMost(2), remaining)
        reconnectAttempt = (reconnectAttempt + 1).coerceAtMost(2)
        reconnectScheduled = true
        reconnectHandler.postDelayed({
            synchronized(NavigationBleSender) {
                reconnectScheduled = false
                if (!reconnectEnabled || gatt != null) return@postDelayed
                if (SystemClock.elapsedRealtime() - reconnectStartedAt >= reconnectWindowMs) {
                    stopAutoReconnect()
                    return@postDelayed
                }
                val context = reconnectContext ?: return@postDelayed
                val deviceId = NavigationBridgeStore.deviceId(context)
                    ?: return@postDelayed
                connectGatt(context, deviceId)
            }
        }, delay)
    }

    private fun stopAutoReconnect() {
        reconnectEnabled = false
        reconnectScheduled = false
        reconnectAttempt = 0
        pendingPayload = null // do not replay stale navigation/settings later
        inFlightPayload = null
        Log.i("NavRide", "BLE auto-reconnect stopped after 20 seconds; retry from the app")
    }

    @Synchronized
    fun retryConnection() {
        if (gatt != null || reconnectEnabled) return
        reconnectEnabled = true
        reconnectStartedAt = -1L
        reconnectAttempt = 0
    }

    @SuppressLint("MissingPermission")
    @Suppress("DEPRECATION")
    private fun writePending(
        bluetoothGatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
    ): Boolean {
        val payload = pendingPayload ?: return false
        if (bluetoothGatt.device.bondState != BluetoothDevice.BOND_BONDED) {
            awaitBond(bluetoothGatt)
            return true
        }
        val started = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                bluetoothGatt.writeCharacteristic(
                    characteristic,
                    payload,
                    BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
                ) == BluetoothStatusCodes.SUCCESS
            } else {
                characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                characteristic.value = payload
                bluetoothGatt.writeCharacteristic(characteristic)
            }
        }.getOrDefault(false)
        if (started) {
            pendingPayload = null
            inFlightPayload = payload
            inFlightIsNavigation = pendingIsNavigation
            writing = true
            reconnectHandler.postDelayed({
                synchronized(NavigationBleSender) {
                    if (gatt === bluetoothGatt && writing && inFlightPayload === payload) {
                        Log.w("NavRide", "BLE write callback timed out; reconnecting")
                        recoverGattWrite(bluetoothGatt)
                    }
                }
            }, 5_000)
            return true
        }
        // No callback follows a rejected write. Reconnect explicitly, keeping
        // the queued command; otherwise it blocks every later command forever.
        recoverGattWrite(bluetoothGatt)
        return true
    }

    @SuppressLint("MissingPermission")
    private fun awaitBond(bluetoothGatt: BluetoothGatt) {
        if (gatt !== bluetoothGatt || !channelReady || bondWaitStartedAt != 0L) return
        bondWaitStartedAt = SystemClock.elapsedRealtime()
        if (bluetoothGatt.device.bondState == BluetoothDevice.BOND_NONE) {
            Log.i("NavRide", "BLE pairing requested; waiting for the PIN confirmation")
            runCatching { bluetoothGatt.device.createBond() }
        }
        fun poll() {
            synchronized(NavigationBleSender) {
                if (gatt !== bluetoothGatt || !channelReady || bondWaitStartedAt == 0L) return
                if (bluetoothGatt.device.bondState == BluetoothDevice.BOND_BONDED) {
                    bondWaitStartedAt = 0L
                    connected = true
                    Log.i("NavRide", "BLE paired; command channel ready")
                    commandCharacteristic?.let { writePending(bluetoothGatt, it) }
                    return
                }
                if (SystemClock.elapsedRealtime() - bondWaitStartedAt >= 90_000) {
                    Log.w("NavRide", "BLE pairing timed out; reconnecting")
                    bondWaitStartedAt = 0L
                    recoverGattWrite(bluetoothGatt)
                    return
                }
                reconnectHandler.postDelayed(::poll, 1_000)
            }
        }
        reconnectHandler.postDelayed(::poll, 1_000)
    }

    @SuppressLint("MissingPermission")
    private fun recoverGattWrite(bluetoothGatt: BluetoothGatt) {
        if (gatt !== bluetoothGatt) return
        if (inFlightPayload != null && pendingPayload == null) {
            pendingPayload = inFlightPayload
            pendingIsNavigation = inFlightIsNavigation
        }
        inFlightPayload = null
        discardStaleSpeed()
        commandCharacteristic = null
        writing = false
        servicesRequested = false
        channelReady = false
        negotiatedMtu = 23
        bondWaitStartedAt = 0L
        connected = false
        acknowledgedRequestId = 0
        gatt = null
        runCatching { bluetoothGatt.disconnect() }
        runCatching { bluetoothGatt.close() }
        scheduleReconnect()
    }

    @SuppressLint("MissingPermission")
    @Synchronized
    fun close() {
        reconnectEnabled = false
        reconnectAttempt = 0
        reconnectStartedAt = -1L
        reconnectHandler.removeCallbacksAndMessages(null)
        reconnectScheduled = false
        reconnectContext = null
        commandCharacteristic = null
        pendingPayload = null
        inFlightPayload = null
        writing = false
        servicesRequested = false
        channelReady = false
        negotiatedMtu = 23
        bondWaitStartedAt = 0L
        connected = false
        wantedRequestId = 0
        acknowledgedRequestId = 0
        modeConfirmed = false
        wifiSavedConfirmed = false
        popupConfirmed = false
        controlRequestId = 0
        streetName = ""
        streetUpdatedAt = 0L
        val previousGatt = gatt
        gatt = null
        // Revoking Bluetooth access must not interrupt privacy cleanup.
        runCatching { previousGatt?.disconnect() }
        runCatching { previousGatt?.close() }
    }

    private val callback = object : BluetoothGattCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(bluetoothGatt: BluetoothGatt, status: Int, newState: Int) {
            synchronized(NavigationBleSender) {
                if (gatt != bluetoothGatt) {
                    bluetoothGatt.close()
                    return
                }
                if (status != BluetoothGatt.GATT_SUCCESS || newState == BluetoothGatt.STATE_DISCONNECTED) {
                    Log.w("NavRide", "BLE disconnected: status=$status state=$newState; scheduling retry")
                    if (inFlightPayload != null && pendingPayload == null) {
                        pendingPayload = inFlightPayload
                        pendingIsNavigation = inFlightIsNavigation
                    }
                    inFlightPayload = null
                    discardStaleSpeed()
                    commandCharacteristic = null
                    writing = false
                    servicesRequested = false
                    channelReady = false
                    negotiatedMtu = 23
                    bondWaitStartedAt = 0L
                    connected = false
                    bluetoothGatt.close()
                    gatt = null
                    scheduleReconnect()
                    return
                }
                if (newState == BluetoothGatt.STATE_CONNECTED) {
                    Log.i("NavRide", "BLE link established; requesting MTU $requestedMtu")
                    if (!bluetoothGatt.requestMtu(requestedMtu)) {
                        Log.w("NavRide", "BLE MTU request rejected; reconnecting instead of opening an unusable link")
                        bluetoothGatt.disconnect()
                    }
                }
            }
        }

        @SuppressLint("MissingPermission")
        override fun onMtuChanged(bluetoothGatt: BluetoothGatt, mtu: Int, status: Int) {
            synchronized(NavigationBleSender) {
                if (gatt != bluetoothGatt) return
                if (status == BluetoothGatt.GATT_SUCCESS && mtu >= minimumPacketMtu) {
                    negotiatedMtu = mtu
                    Log.i("NavRide", "BLE MTU negotiated: $mtu")
                    discoverServices(bluetoothGatt)
                } else {
                    Log.w("NavRide", "BLE MTU unusable: mtu=$mtu status=$status; reconnecting")
                    bluetoothGatt.disconnect()
                }
            }
        }

        @SuppressLint("MissingPermission")
        override fun onServicesDiscovered(bluetoothGatt: BluetoothGatt, status: Int) {
            synchronized(NavigationBleSender) {
                if (gatt != bluetoothGatt) return
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    pendingPayload = null
                    bluetoothGatt.disconnect()
                    return
                }
                commandCharacteristic = bluetoothGatt.getService(serviceUuid)
                    ?.getCharacteristic(commandUuid)
                val statusCharacteristic = bluetoothGatt.getService(serviceUuid)
                    ?.getCharacteristic(statusUuid)
                val characteristic = commandCharacteristic
                if (characteristic == null) {
                    pendingPayload = null
                    bluetoothGatt.disconnect()
                    return
                }
                val descriptor = statusCharacteristic?.getDescriptor(cccdUuid)
                if (statusCharacteristic != null && descriptor != null &&
                    bluetoothGatt.setCharacteristicNotification(statusCharacteristic, true)
                ) {
                    val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        bluetoothGatt.writeDescriptor(
                            descriptor,
                            BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE,
                        ) == BluetoothStatusCodes.SUCCESS
                    } else {
                        @Suppress("DEPRECATION")
                        descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                        @Suppress("DEPRECATION")
                        bluetoothGatt.writeDescriptor(descriptor)
                    }
                    if (started) return
                }
                // Delivery cannot be confirmed without the status subscription.
                bluetoothGatt.disconnect()
            }
        }

        @SuppressLint("MissingPermission")
        override fun onDescriptorWrite(
            bluetoothGatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
        ) {
            synchronized(NavigationBleSender) {
                if (gatt == bluetoothGatt && descriptor.uuid == cccdUuid) {
                    if (status != BluetoothGatt.GATT_SUCCESS) {
                        bluetoothGatt.disconnect()
                        return
                    }
                    channelReady = true
                    reconnectAttempt = 0
                    reconnectStartedAt = -1L
                    reconnectScheduled = false
                    if (bluetoothGatt.device.bondState == BluetoothDevice.BOND_BONDED) {
                        connected = true
                        commandCharacteristic?.let { writePending(bluetoothGatt, it) }
                    } else {
                        awaitBond(bluetoothGatt)
                    }
                    OsmAndNotificationListener.replayActiveNavigation()
                }
            }
        }

        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(
            bluetoothGatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
        ) {
            onStatusChanged(bluetoothGatt, characteristic.uuid, characteristic.value)
        }

        override fun onCharacteristicChanged(
            bluetoothGatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            onStatusChanged(bluetoothGatt, characteristic.uuid, value)
        }

        override fun onCharacteristicWrite(
            bluetoothGatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            synchronized(NavigationBleSender) {
                if (gatt != bluetoothGatt) return
                writing = false
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    inFlightPayload = null
                    commandCharacteristic?.let { writePending(bluetoothGatt, it) }
                } else {
                    recoverGattWrite(bluetoothGatt)
                }
            }
        }
    }

    private fun onStatusChanged(bluetoothGatt: BluetoothGatt, uuid: UUID, value: ByteArray) {
        synchronized(this) {
            if (gatt != bluetoothGatt || uuid != statusUuid) return
            val response = String(value, StandardCharsets.UTF_8)
            if (response == "ok:speed") {
                if (SpeedService.acknowledgedAt == 0L) Log.i("NavRide", "Speed telemetry acknowledged by ESP32")
                SpeedService.acknowledgedAt = android.os.SystemClock.elapsedRealtime()
            }
            if (controlRequestId > 0) {
                if (response == "ok:mode:$controlRequestId") modeConfirmed = true
                if (response == "ok:wifi_saved:$controlRequestId") wifiSavedConfirmed = true
                if (response == "ok:popup:$controlRequestId") popupConfirmed = true
            }
            if (!response.startsWith("ok:navigation:")) return
            val id = response.removePrefix("ok:navigation:").toIntOrNull() ?: return
            if (id == wantedRequestId) {
                acknowledgedRequestId = id
                Log.d("NavRide", "Navigation acknowledged: requestId=$id")
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun discoverServices(bluetoothGatt: BluetoothGatt) {
        if (servicesRequested) return
        servicesRequested = true
        if (!bluetoothGatt.discoverServices()) bluetoothGatt.disconnect()
    }
}

internal data class OsmAndNavigation(
    val maneuver: String,
    val distanceMeters: Int,
    val streetName: String = "",
    val exitNumber: Int? = null,
    val turnAngle: Int? = null,
)

internal object OsmAndNotificationParser {
    private val distancePattern = Regex(
        "(\\d+(?:[.,]\\d+)?)\\s*(km|kilometres?|kilometers?|kilomet|kilômét|m|metres?|meters?|mét)",
    )
    private val streetPattern = Regex(
        "(?:\\bonto\\b|\\bon\\b|\\bvào\\b|\\bsang\\b)[ \\t]+(.+?)(?=\\s+(?:in|for|sau)\\s+\\d|[,;!\\r\\n•]|$)",
        RegexOption.IGNORE_CASE,
    )
    private val andGoStreetPattern = Regex(
        "\\band go[ \\t]+([^\\r\\n•]+)", RegexOption.IGNORE_CASE,
    )
    private val trailingLegDistance = Regex("(?:^|\\s+)${distancePattern.pattern}\\s*$", RegexOption.IGNORE_CASE)
    private val roundaboutExit = Regex(
        "(?:take|exit)\\s+(?:the\\s+)?(\\d+)(?:st|nd|rd|th)?\\s+exit",
        RegexOption.IGNORE_CASE,
    )

    fun parseStreet(raw: String): String {
        // OsmAnd 5.4: the title has distance to the turn; the first body line
        // has "Turn right and go <road> <next leg distance>". Keep road refs
        // such as ĐT.43 and never display the next leg or trip summary as road.
        val normalized = raw.replace('\u00a0', ' ')
        val match = streetPattern.find(normalized) ?: andGoStreetPattern.find(normalized)
        return match?.groupValues?.getOrNull(1)
            ?.trim()?.replace(trailingLegDistance, "")?.trim()
            ?.trimEnd(',', '.', ';', '!')?.take(48).orEmpty()
    }

    fun parse(raw: String): OsmAndNavigation? {
        val text = raw.lowercase().replace('\u00a0', ' ').replace(',', '.')
        val maneuver = when {
            Regex("\\btake (?:the )?\\d+(?:st|nd|rd|th)? exit\\b").containsMatchIn(text) ||
                listOf("roundabout", "vòng xuyến", "vong xuyen").any(text::contains) -> "roundabout"
            listOf("right u-turn", "right u turn", "u-turn right", "quay đầu phải").any(text::contains) -> "u_turn_right"
            listOf("quay đầu", "quay dau", "u-turn", "u turn", "make a u-turn").any(text::contains) -> "u_turn"
            listOf("sharp right", "sharply right", "rẽ gắt phải").any(text::contains) -> "sharp_right"
            listOf("sharp left", "sharply left", "rẽ gắt trái").any(text::contains) -> "sharp_left"
            listOf("slight right", "slightly right", "bear right", "chếch phải", "chech phai").any(text::contains) -> "slight_right"
            listOf("slight left", "slightly left", "bear left", "chếch trái", "chech trai").any(text::contains) -> "slight_left"
            listOf("keep right", "giữ bên phải", "giu ben phai").any(text::contains) -> "keep_right"
            listOf("keep left", "giữ bên trái", "giu ben trai").any(text::contains) -> "keep_left"
            listOf("rẽ phải", "re phai", "turn right", "right turn").any(text::contains) -> "right"
            listOf("rẽ trái", "re trai", "turn left", "left turn").any(text::contains) -> "left"
            listOf("đi thẳng", "di thang", "go straight", "continue straight", "continue on").any(text::contains) -> "straight"
            listOf("đã đến", "da den", "arrived", "destination").any(text::contains) -> "arrive"
            listOf("off route", "off-route", "lệch tuyến").any(text::contains) -> "off_route"
            else -> return null
        }
        val match = distancePattern.find(text)
        val distance = when (match?.groupValues?.get(2)) {
            "km", "kilometre", "kilometres", "kilometer", "kilometers", "kilomet", "kilômét" ->
                ((match.groupValues[1].toDouble()) * 1000).toInt()
            else -> match?.groupValues?.get(1)?.toDoubleOrNull()?.toInt() ?: 0
        }
        val exit = roundaboutExit.find(raw)?.groupValues?.get(1)?.toIntOrNull()
        return OsmAndNavigation(maneuver, distance, parseStreet(raw), exit)
    }
}

internal object OsmAndDirectionMapper {
    private val roundaboutTypePattern = Regex("^(RNDB|RNLB)(\\d+)$")

    fun angleFromBundle(value: Any?): Int? = (value as? Number)?.toDouble()
        ?.takeIf(Double::isFinite)?.roundToInt()

    fun map(turnType: Int, distanceMeters: Int, leftSide: Boolean): OsmAndNavigation? {
        if (distanceMeters < 0) return null
        val maneuver = when (turnType) {
            1 -> "straight"
            2 -> "left"
            3 -> "slight_left"
            4 -> "sharp_left"
            5 -> "right"
            6 -> "slight_right"
            7 -> "sharp_right"
            8 -> "keep_left"
            9 -> "keep_right"
            10 -> "u_turn"
            11 -> "u_turn_right"
            12 -> "off_route"
            13 -> if (leftSide) "roundabout_left" else "roundabout"
            14 -> "roundabout_left"
            else -> return null
        }
        return OsmAndNavigation(maneuver, distanceMeters.coerceIn(0, 999_999))
    }

    // All three fields come from the same next-turn snapshot, never current_ or
    // after_next. A blank next road must stay blank, not reuse the previous road.
    fun fromNextTurn(turn: String?, distanceMeters: Int, street: String?, angle: Int? = null): OsmAndNavigation? {
        val roundaboutType = turn?.let(roundaboutTypePattern::matchEntire)
        val type = when (turn) {
            "C" -> 1
            "TL" -> 2
            "TSLL" -> 3
            "TSHL" -> 4
            "TR" -> 5
            "TSLR" -> 6
            "TSHR" -> 7
            "KL" -> 8
            "KR" -> 9
            "TU" -> 10
            "TRU" -> 11
            "OFFR" -> 12
            else -> when {
                roundaboutType?.groupValues?.get(1) == "RNDB" -> 13
                roundaboutType?.groupValues?.get(1) == "RNLB" -> 14
                else -> return null
            }
        }
        val wrappedAngle = angle?.rem(360)
        val roundaboutAngle = wrappedAngle?.let {
            when {
                it <= -180 -> it + 360
                it > 180 -> it - 360
                else -> it
            }
        }
        return map(type, distanceMeters, false)?.copy(
            streetName = street.orEmpty().trim(),
            exitNumber = roundaboutType?.groupValues?.get(2)?.toIntOrNull(),
            turnAngle = roundaboutAngle?.takeIf { roundaboutType != null },
        )
    }
}
