package com.thanhhao.esp32_navride

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.After
import org.junit.Before
import org.junit.Test
import java.io.IOException
import java.net.ServerSocket
import java.util.Date
import java.util.concurrent.Executors
import java.util.concurrent.Future

class FleetHistoryUploadTest {
    private lateinit var server: ServerSocket
    private lateinit var serverTask: Future<*>
    private val executor = Executors.newSingleThreadExecutor()
    private lateinit var uploader: FleetHistoryUpload
    private var remote: JSONObject? = null
    private var writes = 0
    private var requests = 0
    private var commitStatus = 200
    private var getStatus: Int? = null
    private var sameAccount = true
    private lateinit var entry: FleetOutbox.Entry

    @Before fun start() {
        val fields = JSONObject()
            .put("latitude", FleetHistoryUpload.number(0.0))
            .put("longitude", FleetHistoryUpload.number(0.0))
            .put("accuracyMeters", FleetHistoryUpload.number(10.0))
            .put("speedKmh", FleetHistoryUpload.nullableSpeed(42))
            .put("tripId", FleetHistoryUpload.string("550e8400-e29b-41d4-a716-446655440001"))
            .put("capturedAt", FleetHistoryUpload.timestamp(Date(0)))
        entry = FleetOutbox.Entry(1, "owner", "point",
            "fleets/test/vehicles/test/track_points/550e8400-e29b-41d4-a716-446655440002", fields)
        server = ServerSocket(0, 10, java.net.InetAddress.getByName("127.0.0.1"))
        serverTask = executor.submit {
        while (!server.isClosed) {
            val socket = try { server.accept() } catch (_: java.net.SocketException) { break }
            socket.use {
            val reader = socket.getInputStream().bufferedReader()
            val method = reader.readLine().substringBefore(' ')
            val headers = mutableMapOf<String, String>()
            while (true) {
                val line = reader.readLine()
                if (line.isEmpty()) break
                headers[line.substringBefore(':').lowercase()] = line.substringAfter(':').trim()
            }
            requests++
            assertEquals("Bearer test-token", headers["authorization"])
            var response = JSONObject()
            val code = if (method == "GET") {
                response = remote ?: JSONObject()
                getStatus ?: if (remote == null) 404 else 200
            } else {
                val chars = CharArray(headers.getValue("content-length").toInt())
                var offset = 0
                while (offset < chars.size) offset += reader.read(chars, offset, chars.size - offset)
                val body = JSONObject(String(chars))
                val write = body.getJSONArray("writes").getJSONObject(0)
                if (entry.kind == "marker_delete") {
                    assertEquals(2, body.getJSONArray("writes").length())
                    assertTrue(write.getString("delete").endsWith("/photos/image"))
                    remote = null
                } else {
                assertEquals(entry.kind in setOf("end", "marker_edit"), write.getJSONObject("currentDocument").getBoolean("exists"))
                assertEquals("REQUEST_TIME", write.getJSONArray("updateTransforms")
                    .getJSONObject(0).getString("setToServerValue"))
                if (entry.kind == "end") assertEquals("endedAt",
                    write.getJSONObject("updateMask").getJSONArray("fieldPaths").getString(0))
                if (entry.kind == "marker_edit") assertEquals(listOf("kind", "note"),
                    write.getJSONObject("updateMask").getJSONArray("fieldPaths").let { fields ->
                        (0 until fields.length()).map { fields.getString(it) }
                    })
                remote = write.getJSONObject("update")
                }
                writes++
                val results = JSONArray().put(JSONObject())
                if (entry.kind == "marker_delete") results.put(JSONObject())
                response = JSONObject().put("writeResults", results)
                    .put("commitTime", "1970-01-01T00:00:01Z")
                commitStatus
            }
            val bytes = response.toString().toByteArray()
            socket.getOutputStream().use { output ->
                val redirect = if (code == 307) "Location: /must-not-follow\r\n" else ""
                output.write(("HTTP/1.1 $code Test\r\nContent-Type: application/json\r\n" +
                    "Content-Length: ${bytes.size}\r\nConnection: close\r\n$redirect\r\n").toByteArray())
                output.write(bytes)
            }
            }
        }
        }
        uploader = FleetHistoryUpload("demo-navride", { "test-token" }, { sameAccount },
            "http://127.0.0.1:${server.localPort}/v1")
    }
    @After fun stop() { server.close(); executor.shutdownNow(); serverTask.get() }

    @Test fun createsPointWithServerTimestampAndAcknowledgesOnlySuccessfulCommit() {
        uploader.upload(entry)
        assertEquals(1, writes)
        assertEquals(entry.fields.toString(), remote!!.getJSONObject("fields").toString())
    }

    @Test fun markerEditUsesPartialUpdateAndLostAckIsIdempotent() {
        entry = FleetOutbox.Entry(4, "owner", "marker_edit", entry.path.replace("track_points", "markers"),
            JSONObject().put("driverUid", FleetHistoryUpload.string("owner"))
                .put("kind", FleetHistoryUpload.string("food")).put("note", FleetHistoryUpload.string("Lunch")))
        remote = JSONObject().put("fields", JSONObject().put("driverUid", FleetHistoryUpload.string("owner")))
        commitStatus = 503
        try { uploader.upload(entry); fail("Lost ACK") } catch (_: IOException) { }
        uploader.upload(entry)
        assertEquals(1, writes)
    }

    @Test fun markerDeleteIsAtomicAndMissingMarkerConfirmsLostAck() {
        entry = FleetOutbox.Entry(4, "owner", "marker_delete", entry.path.replace("track_points", "markers"), JSONObject())
        remote = JSONObject().put("fields", JSONObject().put("driverUid", FleetHistoryUpload.string("owner")))
        commitStatus = 503
        try { uploader.upload(entry); fail("Lost ACK") } catch (_: IOException) { }
        uploader.upload(entry)
        assertEquals(1, writes)
    }

    @Test fun markerEditCannotRecreateDeletedRecord() {
        entry = FleetOutbox.Entry(4, "owner", "marker_edit", entry.path.replace("track_points", "markers"), JSONObject())
        uploader.upload(entry)
        assertEquals(0, writes)
    }

    @Test fun markerWithPhotoFlagUsesServerTimeAndIdempotentRead() {
        entry = FleetOutbox.Entry(2, "owner", "marker",
            "fleets/test/vehicles/test/markers/550e8400-e29b-41d4-a716-446655440003",
            JSONObject().put("driverUid", FleetHistoryUpload.string("owner"))
                .put("kind", FleetHistoryUpload.string("food"))
                .put("hasPhoto", JSONObject().put("booleanValue", true)))
        uploader.upload(entry)
        uploader.upload(entry)
        assertEquals(1, writes)
        assertEquals(true, remote!!.getJSONObject("fields").getJSONObject("hasPhoto").getBoolean("booleanValue"))
    }

    @Test fun privatePhotoUsesCreateOnlyAndRetryDoesNotDuplicateBytes() {
        entry = FleetOutbox.Entry(3, "owner", "photo",
            "fleets/test/vehicles/test/markers/550e8400-e29b-41d4-a716-446655440003/photos/image",
            JSONObject().put("driverUid", FleetHistoryUpload.string("owner"))
                .put("contentType", FleetHistoryUpload.string("image/jpeg"))
                .put("data", FleetHistoryUpload.string("/9j/2Q==")))
        uploader.upload(entry)
        uploader.upload(entry)
        assertEquals(1, writes)
        assertEquals("/9j/2Q==", remote!!.getJSONObject("fields").getJSONObject("data").getString("stringValue"))
    }

    @Test fun lostAckRetriesSameIdWithoutSecondWrite() {
        commitStatus = 503
        try { uploader.upload(entry); fail("Lost ACK must keep the row") } catch (_: IOException) { }
        assertEquals(1, writes)
        uploader.upload(entry)
        assertEquals(1, writes)
    }

    @Test fun remoteConflictCannotBeAcknowledged() {
        remote = JSONObject().put("fields", JSONObject(entry.fields.toString())
            .put("latitude", FleetHistoryUpload.number(1.0)))
        try { uploader.upload(entry); fail("Different point must not be deleted") } catch (_: IOException) { }
        assertEquals(0, writes)
    }

    @Test fun permissionDeniedKeepsQueueAndDoesNotAttemptWrite() {
        getStatus = 403
        try { uploader.upload(entry); fail("Access denied") } catch (_: IOException) { }
        assertEquals(0, writes)
    }

    @Test fun redirectCannotForwardTokenOrLocation() {
        getStatus = 307
        try { uploader.upload(entry); fail("Redirect must be rejected") } catch (_: IOException) { }
        assertEquals(1, requests)
        assertEquals(0, writes)
    }

    @Test fun accountChangeStopsRequestBeforeSendingCredentials() {
        sameAccount = false
        try { uploader.upload(entry); fail("Account changed") } catch (_: IllegalStateException) { }
        assertEquals(0, requests)
    }

    @Test fun equivalentTimestampAndNumericEncodingsMatch() {
        remote = JSONObject().put("fields", JSONObject(entry.fields.toString())
            .put("capturedAt", JSONObject().put("timestampValue", "1970-01-01T00:00:00Z"))
            .put("speedKmh", JSONObject().put("doubleValue", 42.0)))
        uploader.upload(entry)
        assertEquals(0, writes)
    }

    @Test fun completedTripStartDoesNotReopenTripOnRetry() {
        entry = FleetOutbox.Entry(1, "owner", "start", entry.path.replace("track_points", "trips"),
            JSONObject().put("driverUid", FleetHistoryUpload.string("owner"))
                .put("startedAt", FleetHistoryUpload.timestamp(Date(0)))
                .put("endedAt", FleetHistoryUpload.nullValue()))
        remote = JSONObject().put("fields", JSONObject(entry.fields.toString())
            .put("endedAt", FleetHistoryUpload.timestamp(Date(120_000))))
        uploader.upload(entry)
        assertEquals(0, writes)
    }

    @Test fun tripEndIsIdempotentAndUsesPartialUpdate() {
        entry = FleetOutbox.Entry(1, "owner", "end", entry.path.replace("track_points", "trips"),
            JSONObject().put("endedAt", FleetHistoryUpload.timestamp(Date(120_000))))
        remote = JSONObject().put("fields", JSONObject()
            .put("driverUid", FleetHistoryUpload.string("owner"))
            .put("endedAt", FleetHistoryUpload.nullValue()))
        uploader.upload(entry)
        assertEquals(1, writes)
        remote!!.getJSONObject("fields").put("driverUid", FleetHistoryUpload.string("owner"))
        uploader.upload(entry)
        assertEquals(1, writes)
    }
}
