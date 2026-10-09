package com.thanhhao.esp32_navride

import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import org.junit.Assert.*
import org.junit.Test
import org.mockito.ArgumentCaptor
import org.mockito.Mockito.*

@Suppress("DEPRECATION")
class NavigationBleRecoveryTest {
    private var nowMs = 10_000L

    private fun field(name: String) = NavigationBleSender::class.java.getDeclaredField(name)
        .apply { isAccessible = true }

    private fun set(name: String, value: Any?) = field(name).set(NavigationBleSender, value)
    private fun get(name: String): Any? = field(name).get(NavigationBleSender)

    private fun withSender(body: (BluetoothGatt, BluetoothGattCharacteristic, Handler) -> Unit) {
        mockStatic(Looper::class.java).use {
            mockStatic(Log::class.java).use {
                mockStatic(SystemClock::class.java).use { clock ->
                    nowMs = 10_000L
                    clock.`when`<Long> { SystemClock.elapsedRealtime() }.thenAnswer { nowMs }
                    mockConstruction(Handler::class.java).use {
                    // Handler is lazy and kept by the singleton between tests.
                    NavigationBleSender.close()
                    val handlerMethod = NavigationBleSender::class.java
                        .getDeclaredMethod("getReconnectHandler").apply { isAccessible = true }
                    val handler = handlerMethod.invoke(NavigationBleSender) as Handler
                    reset(handler)
                    val gatt = mock(BluetoothGatt::class.java)
                    val device = mock(BluetoothDevice::class.java)
                    `when`(gatt.device).thenReturn(device)
                    `when`(device.bondState).thenReturn(BluetoothDevice.BOND_BONDED)
                    val characteristic = mock(BluetoothGattCharacteristic::class.java)
                    set("gatt", gatt)
                    set("commandCharacteristic", characteristic)
                    set("channelReady", true)
                    set("connected", true)
                    set("reconnectEnabled", true)
                    set("pendingPayload", "popup".toByteArray())
                    set("pendingIsNavigation", false)
                    try { body(gatt, characteristic, handler) }
                    finally { NavigationBleSender.close() }
                    }
                }
            }
        }
    }

    private fun write(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic): Boolean {
        val method = NavigationBleSender::class.java.getDeclaredMethod(
            "writePending", BluetoothGatt::class.java, BluetoothGattCharacteristic::class.java,
        ).apply { isAccessible = true }
        return method.invoke(NavigationBleSender, gatt, characteristic) as Boolean
    }

    @Test
    fun closingAfterPermissionRevocationStillReleasesTheLink() = withSender { gatt, _, _ ->
        doThrow(SecurityException("Bluetooth permission revoked")).`when`(gatt).disconnect()
        NavigationBleSender.close()
        assertNull(get("gatt"))
        assertNull(get("pendingPayload"))
        verify(gatt).close()
        assertFalse(NavigationBleSender.isConnected())
    }

    @Test
    fun closingConnectionDropsPrivatePayloadsAndStreetCache() = withSender { _, _, _ ->
        set("streetName", "Private destination")
        set("streetUpdatedAt", nowMs)
        set("inFlightPayload", "private content".toByteArray())
        NavigationBleSender.close()
        assertEquals("", get("streetName"))
        assertEquals(0L, get("streetUpdatedAt"))
        assertNull(get("pendingPayload"))
        assertNull(get("inFlightPayload"))
        assertFalse(NavigationBleSender.isConnected())
    }

    @Test
    fun rejectedWriteKeepsCommandAndSchedulesReconnectWithoutWaitingForCallback() = withSender { gatt, characteristic, handler ->
        // Local JVM SDK_INT is 0; this exercises the legacy Boolean API.
        `when`(gatt.writeCharacteristic(characteristic)).thenReturn(false)
        val pending = get("pendingPayload")
        assertTrue(write(gatt, characteristic))
        assertSame(pending, get("pendingPayload"))
        assertNull(get("gatt"))
        assertFalse(NavigationBleSender.isConnected())
        verify(gatt).disconnect()
        verify(gatt).close()
        verify(handler).postDelayed(any(Runnable::class.java), eq(1_000L))
    }

    @Test
    fun absentWriteCallbackTimesOutAndRetainsPayloadForRetry() = withSender { gatt, characteristic, handler ->
        `when`(gatt.writeCharacteristic(characteristic)).thenReturn(true)
        val pending = get("pendingPayload")
        assertTrue(write(gatt, characteristic))
        assertNull(get("pendingPayload"))
        val timeout = ArgumentCaptor.forClass(Runnable::class.java)
        verify(handler).postDelayed(timeout.capture(), eq(5_000L))
        timeout.value.run()
        assertSame(pending, get("pendingPayload"))
        assertNull(get("gatt"))
        assertEquals(false, get("writing"))
        verify(handler).postDelayed(any(Runnable::class.java), eq(1_000L))
    }

    @Test
    fun thrownWriteErrorAlsoRecoversTheQueue() = withSender { gatt, characteristic, handler ->
        `when`(gatt.writeCharacteristic(characteristic)).thenThrow(SecurityException("Permission changed"))
        val pending = get("pendingPayload")
        assertTrue(write(gatt, characteristic))
        assertSame(pending, get("pendingPayload"))
        assertNull(get("gatt"))
        verify(handler).postDelayed(any(Runnable::class.java), eq(1_000L))
    }

    @Test
    fun rejectedSpeedIsDiscardedInsteadOfReplayingStaleTelemetry() = withSender { gatt, characteristic, _ ->
        set("pendingPayload", SpeedReading.packet(42).toByteArray())
        `when`(gatt.writeCharacteristic(characteristic)).thenReturn(false)
        assertTrue(write(gatt, characteristic))
        assertNull(get("pendingPayload"))
        assertFalse(NavigationBleSender.isConnected())
    }

    @Test
    fun timedOutSpeedIsDiscardedAndCannotBlockDirections() = withSender { gatt, characteristic, handler ->
        set("pendingPayload", SpeedReading.packet(42).toByteArray())
        `when`(gatt.writeCharacteristic(characteristic)).thenReturn(true)
        assertTrue(write(gatt, characteristic))
        val timeout = ArgumentCaptor.forClass(Runnable::class.java)
        verify(handler).postDelayed(timeout.capture(), eq(5_000L))
        timeout.value.run()
        assertNull(get("pendingPayload"))
        assertNull(get("inFlightPayload"))
    }

    @Test
    fun speedCannotReplacePendingControlOrNavigation() = withSender { _, _, _ ->
        val context = mock(android.content.Context::class.java)
        val queued = get("pendingPayload")
        assertFalse(NavigationBleSender.sendSpeed(context, SpeedReading.packet(42)))
        assertSame(queued, get("pendingPayload"))
        set("pendingIsNavigation", true)
        assertFalse(NavigationBleSender.sendSpeed(context, SpeedReading.packet(42)))
        assertSame(queued, get("pendingPayload"))
    }

    @Test
    fun completedWriteIgnoresOldWatchdog() = withSender { gatt, characteristic, handler ->
        `when`(gatt.writeCharacteristic(characteristic)).thenReturn(true)
        assertTrue(write(gatt, characteristic))
        val timeout = ArgumentCaptor.forClass(Runnable::class.java)
        verify(handler).postDelayed(timeout.capture(), eq(5_000L))
        (get("callback") as BluetoothGattCallback).onCharacteristicWrite(gatt, characteristic, BluetoothGatt.GATT_SUCCESS)
        timeout.value.run()
        assertSame(gatt, get("gatt"))
        assertTrue(NavigationBleSender.isConnected())
        verify(gatt, never()).disconnect()
    }

    @Test
    fun autoReconnectStopsAfterEspAdvertisingWindowUntilExplicitRetry() = withSender { _, _, handler ->
        set("gatt", null)
        val context = mock(android.content.Context::class.java)
        set("reconnectContext", context)
        val schedule = NavigationBleSender::class.java.getDeclaredMethod("scheduleReconnect")
            .apply { isAccessible = true }
        schedule.invoke(NavigationBleSender)
        val retry = ArgumentCaptor.forClass(Runnable::class.java)
        verify(handler).postDelayed(retry.capture(), eq(1_000L))
        assertEquals(10_000L, get("reconnectStartedAt"))

        // A delayed Android callback must not revive BLE after ESP32 stops advertising.
        nowMs = 30_000L
        retry.value.run()
        assertFalse(get("reconnectEnabled") as Boolean)
        assertNull(get("pendingPayload"))
        assertFalse(NavigationBleSender.send(context, "{\"command\":\"ping\"}"))
        verifyNoInteractions(context)

        NavigationBleSender.retryConnection()
        assertTrue(get("reconnectEnabled") as Boolean)
        assertEquals(-1L, get("reconnectStartedAt"))
    }

    @Test
    fun unpairedDeviceWaitsForPinBeforeWritingWithoutFiveSecondWatchdog() = withSender { gatt, characteristic, handler ->
        val device = gatt.device
        `when`(device.bondState).thenReturn(
            BluetoothDevice.BOND_NONE,
            BluetoothDevice.BOND_NONE,
            BluetoothDevice.BOND_BONDED,
        )
        val pending = get("pendingPayload")
        assertTrue(write(gatt, characteristic))
        verify(device).createBond()
        verify(gatt, never()).writeCharacteristic(characteristic)
        assertSame(pending, get("pendingPayload"))
        val poll = ArgumentCaptor.forClass(Runnable::class.java)
        verify(handler).postDelayed(poll.capture(), eq(1_000L))
        `when`(gatt.writeCharacteristic(characteristic)).thenReturn(true)
        poll.value.run()
        assertNull(get("pendingPayload"))
        verify(gatt).writeCharacteristic(characteristic)
        verify(handler).postDelayed(any(Runnable::class.java), eq(5_000L))
    }
}
