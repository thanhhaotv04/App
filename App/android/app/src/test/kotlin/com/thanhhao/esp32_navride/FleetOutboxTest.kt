package com.thanhhao.esp32_navride

import android.app.Application
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.IOException

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class FleetOutboxTest {
    private lateinit var app: Application
    private lateinit var queue: FleetOutbox
    private val trip = "fleets/test/vehicles/test/trips/550e8400-e29b-41d4-a716-446655440001"
    private val point = "fleets/test/vehicles/test/track_points/550e8400-e29b-41d4-a716-446655440002"

    @Before fun open() {
        app = RuntimeEnvironment.getApplication()
        app.deleteDatabase("fleet-outbox.db")
        queue = FleetOutbox(app)
    }
    @After fun close() { queue.close(); app.deleteDatabase("fleet-outbox.db") }

    @Test fun restartPreservesPendingPointsAndTheirStableIds() {
        queue.add("owner", "point", point, JSONObject().put("test", "value"))
        queue.close()
        queue = FleetOutbox(app)
        assertEquals(1, queue.count("owner", true))
        queue.flush("owner") { assertEquals(point, it.path) }
        assertEquals(0, queue.count())
    }

    @Test fun offlineOrFailedUploadNeverDeletesPendingData() {
        queue.add("owner", "point", point, JSONObject())
        queue.flush("owner", mayContinue = { false }) { fail("Offline must not upload") }
        try {
            queue.flush("owner") { throw IOException("No server ACK") }
            fail("Expected failed upload")
        } catch (_: IOException) { }
        assertEquals(1, queue.count("owner", true))
    }

    @Test fun ackRemovesOnlyThatEntryAndFailureKeepsRemainingEventsInOrder() {
        queue.add("owner", "start", trip, JSONObject())
        queue.add("owner", "point", point, JSONObject())
        queue.add("owner", "end", trip, JSONObject())
        val sent = mutableListOf<String>()
        try {
            queue.flush("owner") {
                sent.add(it.kind)
                if (it.kind == "point") throw IOException("Lost ACK")
            }
        } catch (_: IOException) { }
        assertEquals(listOf("start", "point"), sent)
        assertEquals(2, queue.count("owner"))
        sent.clear()
        queue.flush("owner") { sent.add(it.kind) }
        assertEquals(listOf("point", "end"), sent)
        assertEquals(0, queue.count())
    }

    @Test fun accountChangeCannotUploadOrDeleteAnotherOwnersPoints() {
        queue.add("first", "point", point, JSONObject())
        queue.add("second", "point", point, JSONObject())
        assertEquals(2, queue.count())
        queue.flush("second") { assertEquals("second", it.uid) }
        assertEquals(1, queue.count("first"))
        assertEquals(0, queue.count("second"))
    }

    @Test fun deletesLocalCoordinatesAndReclaimsPagesAfterAcknowledgment() {
        queue.add("owner", "point", point, JSONObject().put("private-marker", "synthetic-coordinate-marker"))
        queue.readableDatabase.rawQuery("PRAGMA secure_delete", null).use {
            it.moveToFirst(); assertEquals(1, it.getInt(0))
        }
        queue.readableDatabase.rawQuery("PRAGMA auto_vacuum", null).use {
            it.moveToFirst(); assertEquals(1, it.getInt(0))
        }
        queue.flush("owner") { }
        assertEquals(0, queue.count())
        val bytes = app.getDatabasePath("fleet-outbox.db").readBytes().toString(Charsets.ISO_8859_1)
        assertFalse(bytes.contains("synthetic-coordinate-marker"))
    }

    @Test fun rejectUntrustedPathsBeforeSaving() {
        try {
            queue.add("owner", "point", "fleets/../../system/access", JSONObject())
            fail("Invalid path must be rejected")
        } catch (_: IllegalArgumentException) { }
        assertEquals(0, queue.count())
    }

    @Test fun threeHoursAtOneMinuteIntervalsHaveOneHundredEightyOnePointsIncludingStart() {
        val origin = 1_000L
        var previous = 0L
        var points = 0
        for (minute in 0..180) {
            val now = origin + minute * 60_000L
            if (FleetLocationPolicy.shouldRecordTrack(now, previous, if (points == 0) 0.0 else 150.0)) {
                previous = now
                points++
                val id = java.util.UUID.randomUUID()
                queue.add("owner", "point", "fleets/test/vehicles/test/track_points/$id", JSONObject())
            }
        }
        assertEquals(181, points)
        assertEquals(181, queue.count("owner", true))
        queue.flush("owner") { }
        assertEquals(81, queue.count("owner", true))
        queue.flush("owner") { }
        assertEquals(0, queue.count())
    }
}
