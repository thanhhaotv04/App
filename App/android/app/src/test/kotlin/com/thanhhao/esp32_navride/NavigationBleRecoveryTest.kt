package com.thanhhao.esp32_navride

import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.junit.Assert.*
import org.junit.Test
import org.mockito.ArgumentCaptor
import org.mockito.Mockito.*

@Suppress("DEPRECATION")
class NavigationBleRecoveryTest {
    private fun field(name: String) = NavigationBleSender::class.java.getDeclaredField(name)
        .apply { isAccessible = true }

    private fun set(name: String, value: Any?) = field(name).set(NavigationBleSender, value)
    private fun get(name: String): Any? = field(name).get(NavigationBleSender)

    private fun withSender(body: (BluetoothGatt, BluetoothGattCharacteristic, Handler) -> Unit) {
        mockStatic(Looper::class.java).use {
            mockStatic(Log::class.java).use {
                mockConstruction(Handler::class.java).use {
                    // Handler is lazy and kept by the singleton between tests.
                    NavigationBleSender.close()
                    val handlerMethod = NavigationBleSender::class.java
                        .getDeclaredMethod("getReconnectHandler").apply { isAccessible = true }
                    val handler = handlerMethod.invoke(NavigationBleSender) as Handler
                    reset(handler)
                    val gatt = mock(BluetoothGatt::class.java)
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

    private fun write(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic): Boolean {
        val method = NavigationBleSender::class.java.getDeclaredMethod(
            "writePending", BluetoothGatt::class.java, BluetoothGattCharacteristic::class.java,
        ).apply { isAccessible = true }
        return method.invoke(NavigationBleSender, gatt, characteristic) as Boolean
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
}
