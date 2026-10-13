package com.thanhhao.esp32_navride

import android.content.Context
import android.location.Location
import android.os.Build
import android.os.SystemClock
import com.google.firebase.auth.FirebaseAuth
import org.json.JSONObject
import java.util.Date
import java.util.UUID

/** Marker là thao tác chủ động, không chịu ngưỡng 1 phút/100 m của lịch sử. */
internal object FleetMarkers {
    val kinds = setOf("save_point", "food", "danger")
    class Failure(val status: String, message: String) : IllegalStateException(message)
    private data class Session(val uid: String, val base: String, val trip: String)
    private var session: Session? = null
    private var location: Location? = null
    private var lastSave = -10_000L
    private var lastResult: String? = null
    val message: String
        @Synchronized get() = lastResult ?: when {
            session == null -> "Start a Fleet trip to save markers"
            location?.let(::usableFix) == true -> "Ready to save a marker"
            else -> "Waiting for a fresh, accurate GPS fix"
        }

    @Synchronized fun begin(uid: String, fleet: String, vehicle: String, trip: String) {
        session = Session(uid, "fleets/$fleet/vehicles/$vehicle/markers", trip)
        location = null
        lastSave = -10_000L
        lastResult = null
    }
    @Synchronized fun end() {
        session = null; location = null
        lastResult = null
    }
    @Synchronized fun update(fix: Location) { location = Location(fix) }

    @Suppress("DEPRECATION")
    private fun usableFix(fix: Location): Boolean {
        val age = (SystemClock.elapsedRealtimeNanos() - fix.elapsedRealtimeNanos) / 1_000_000
        val mock = if (Build.VERSION.SDK_INT >= 31) fix.isMock else fix.isFromMockProvider
        return FleetLocationPolicy.accepts(age, fix.accuracy.takeIf { fix.hasAccuracy() }, mock,
            fix.latitude, fix.longitude)
    }

    @Synchronized fun prepare(kind: String, source: String): JSONObject {
        require(kind in kinds && source in setOf("phone", "esp32")) { "Choose a valid marker type" }
        val active = session ?: throw Failure("trip", "Start a Fleet trip first")
        if (FirebaseAuth.getInstance().currentUser?.uid != active.uid)
            throw Failure("account", "Sign in to the Fleet account again")
        val fix = location?.takeIf(::usableFix)
            ?: throw Failure("gps", "Wait for a fresh, accurate GPS fix")
        if (SystemClock.elapsedRealtime() - lastSave < 3_000)
            throw Failure("busy", "Please wait a moment before saving another marker")
        val now = System.currentTimeMillis()
        val captured = fix.time.takeIf { it in now - 15_000..now + 5_000 } ?: now
        return JSONObject().put("uid", active.uid).put("path", "${active.base}/${UUID.randomUUID()}")
            .put("fields", JSONObject().put("driverUid", FleetHistoryUpload.string(active.uid))
                .put("kind", FleetHistoryUpload.string(kind)).put("source", FleetHistoryUpload.string(source))
                .put("tripId", FleetHistoryUpload.string(active.trip))
                .put("latitude", FleetHistoryUpload.number(fix.latitude))
                .put("longitude", FleetHistoryUpload.number(fix.longitude))
                .put("accuracyMeters", FleetHistoryUpload.number(fix.accuracy.toDouble()))
                .put("capturedAt", FleetHistoryUpload.timestamp(Date(captured))))
    }

    @Synchronized fun save(context: Context, draft: JSONObject, jpeg: ByteArray? = null): Boolean {
        val uid = draft.getString("uid")
        if (FirebaseAuth.getInstance().currentUser?.uid != uid)
            throw Failure("account", "Fleet account changed; marker was not saved")
        val fields = draft.getJSONObject("fields")
        fields.put("hasPhoto", JSONObject().put("booleanValue", jpeg != null))
        val photo = jpeg?.let {
            require(it.size in 1..MarkerPhoto.MAX_BYTES) { "Photo is too large" }
            JSONObject().put("driverUid", FleetHistoryUpload.string(uid))
                .put("contentType", FleetHistoryUpload.string("image/jpeg"))
                .put("data", FleetHistoryUpload.string(android.util.Base64.encodeToString(it, android.util.Base64.NO_WRAP)))
        }
        val saved = FleetHistorySync.get(context).enqueueMarker(uid, draft.getString("path"), fields, photo)
        if (saved) lastSave = SystemClock.elapsedRealtime()
        lastResult = if (saved) "Marker saved on phone · syncs when online" else "Marker not saved. Check phone storage and retry"
        return saved
    }
}
