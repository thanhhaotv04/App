package com.thanhhao.esp32_navride

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.IOException

/** Chỉ dùng DB test riêng, không bật GPS, không sửa hàng đợi hoặc Firebase thật. */
@RunWith(AndroidJUnit4::class)
class FleetOutboxDeviceTest {
    @Test fun offlineRestartAckAndAccountIsolationOnRealSQLite() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "fleet-outbox-device-test.db"
        val path = "fleets/test/vehicles/test/track_points/550e8400-e29b-41d4-a716-446655440002"
        context.deleteDatabase(name)
        var queue = FleetOutbox(context, name)
        try {
            queue.add("test-owner", "point", path, JSONObject().put("test-marker", "synthetic-only"))
            queue.flush("test-owner", mayContinue = { false }) { fail("Offline upload") }
            queue.close()
            queue = FleetOutbox(context, name)
            assertEquals(1, queue.count("test-owner", true))
            queue.flush("other-owner") { fail("Wrong account") }
            try {
                queue.flush("test-owner") { throw IOException("No ACK") }
                fail("Expected failed upload")
            } catch (_: IOException) { }
            assertEquals(1, queue.count())
            queue.flush("test-owner") { assertEquals(path, it.path) }
            assertEquals(0, queue.count())
            queue.readableDatabase.rawQuery("PRAGMA auto_vacuum", null).use {
                it.moveToFirst(); assertEquals(1, it.getInt(0))
            }
            val remaining = context.getDatabasePath(name).readBytes().toString(Charsets.ISO_8859_1)
            assertFalse(remaining.contains("synthetic-only"))
        } finally {
            queue.close()
            context.deleteDatabase(name)
        }
    }
}
