package com.thanhhao.esp32_navride

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.Test

class FleetLocationPolicyTest {
    @Test fun rejectsStaleInaccurateAndMockLocations() {
        assertTrue(FleetLocationPolicy.accepts(500, 12f, false, 10.77, 106.70))
        assertFalse(FleetLocationPolicy.accepts(15_001, 12f, false, 10.77, 106.70))
        assertFalse(FleetLocationPolicy.accepts(500, 51f, false, 10.77, 106.70))
        assertFalse(FleetLocationPolicy.accepts(500, null, false, 10.77, 106.70))
        assertFalse(FleetLocationPolicy.accepts(500, 12f, true, 10.77, 106.70))
        assertFalse(FleetLocationPolicy.accepts(500, 12f, false, 91.0, 106.70))
    }

    @Test fun limitsUploadsToOneEveryThirtySeconds() {
        assertTrue(FleetLocationPolicy.shouldUpload(1_000, 0, false))
        assertFalse(FleetLocationPolicy.shouldUpload(10_000, 1_000, false))
        assertFalse(FleetLocationPolicy.shouldUpload(31_000, 1_000, true))
        assertTrue(FleetLocationPolicy.shouldUpload(31_000, 1_000, false))
    }

    @Test fun recordsOnlyAfterFiveMinutesAndMeaningfulMovement() {
        val origin = 1_000L
        assertTrue(FleetLocationPolicy.shouldRecordTrack(origin, 0, 0.0, true))
        assertFalse(FleetLocationPolicy.shouldRecordTrack(origin + 299_999, origin, 250.0, true))
        assertFalse(FleetLocationPolicy.shouldRecordTrack(origin + 300_000, origin, 99.9, true))
        assertFalse(FleetLocationPolicy.shouldRecordTrack(origin + 300_000, origin, 100.0, true))
        assertTrue(FleetLocationPolicy.shouldRecordTrack(origin + 300_000, origin, 100.1, true))
        assertFalse(FleetLocationPolicy.shouldRecordTrack(origin + 599_999, origin, 200.0, false))
        assertFalse(FleetLocationPolicy.shouldRecordTrack(origin + 600_000, origin, 99.9, false))
        assertFalse(FleetLocationPolicy.shouldRecordTrack(origin + 600_000, origin, 100.0, false))
        assertTrue(FleetLocationPolicy.shouldRecordTrack(origin + 600_000, origin, 100.1, false))
        assertEquals(0.0, FleetLocationPolicy.distanceMeters(10.77, 106.70, 10.77, 106.70), 0.01)
        assertTrue(FleetLocationPolicy.distanceMeters(10.77, 106.70, 10.771, 106.70) > 100.0)
    }
}
