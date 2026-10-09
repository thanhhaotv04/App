package com.thanhhao.esp32_navride

import org.junit.Assert.*
import org.junit.Test

class SpeedReadingTest {
    @Test fun convertsMetersPerSecondToKmh() {
        assertEquals(36, SpeedReading.kmh(true, 10f, 0))
        assertEquals(0, SpeedReading.kmh(true, 0f, 100))
        assertEquals(50, SpeedReading.kmh(true, 13.9f, 1_000, 0.4f))
    }
    @Test fun missingAndStaleSpeedAreNotZero() {
        assertNull(SpeedReading.kmh(false, 0f, 0))
        assertNull(SpeedReading.kmh(true, 10f, 5_001))
        assertNull(SpeedReading.kmh(true, 10f, -1))
    }
    @Test fun invalidOrUnreliableSpeedIsRejected() {
        for (value in listOf(-1f, Float.NaN, Float.POSITIVE_INFINITY, 100f)) {
            assertNull(SpeedReading.kmh(true, value, 0))
        }
        assertNull(SpeedReading.kmh(true, 10f, 0, 3.1f))
        assertNull(SpeedReading.kmh(true, 10f, 0, Float.NaN))
    }
    @Test fun packetsAreSmallAndExplicitAboutUnknown() {
        assertEquals("""{"apiVersion":1,"command":"speed","kmh":36}""", SpeedReading.packet(36))
        assertTrue(SpeedReading.packet(null).contains("\"kmh\":null"))
        assertTrue(SpeedReading.packet(300).toByteArray().size <= 180)
        assertFalse(SpeedReading.packet(null).contains("limit"))
    }
}
