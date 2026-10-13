package com.thanhhao.esp32_navride

import android.content.Context
import com.google.android.gms.tasks.Tasks
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Lịch sử xem từ server chỉ ở RAM. SQLite chỉ giữ thao tác chưa được ACK. */
internal object FleetMarkerManagement {
    private val worker = Executors.newSingleThreadExecutor()
    private val idPattern = Regex("[A-Za-z0-9_-]{1,64}")
    private val markerPattern = Regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
    private var cacheKey = ""
    private val cloud = linkedMapOf<String, MutableMap<String, Any?>>()
    private var revision = -1L
    private var warning: String? = null
    private var wasOnline = false

    fun selection(context: Context): Map<String, String> {
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return emptyMap()
        val prefs = context.getSharedPreferences("fleet-selection", Context.MODE_PRIVATE)
        return mapOf("fleetId" to (prefs.getString("$uid/fleet", "demo") ?: "demo"),
            "vehicleId" to (prefs.getString("$uid/vehicle", "bike-01") ?: "bike-01"))
    }

    fun select(context: Context, fleet: String, vehicle: String) {
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: error("Sign in first")
        require(!SpeedService.fleetActive && idPattern.matches(fleet) && idPattern.matches(vehicle))
        check(context.getSharedPreferences("fleet-selection", Context.MODE_PRIVATE).edit()
            .putString("$uid/fleet", fleet).putString("$uid/vehicle", vehicle).commit())
    }

    private fun row(path: String, fields: JSONObject, uid: String): MutableMap<String, Any?> = mutableMapOf(
        "id" to path.substringAfterLast('/'), "path" to path,
        "kind" to fields.optJSONObject("kind")?.optString("stringValue"),
        "note" to (fields.optJSONObject("note")?.optString("stringValue") ?: ""),
        "capturedAt" to fields.optJSONObject("capturedAt")?.optString("timestampValue"),
        "hasPhoto" to (fields.optJSONObject("hasPhoto")?.optBoolean("booleanValue") == true),
        "editable" to (fields.optJSONObject("driverUid")?.optString("stringValue") == uid),
        "status" to "Synced",
    )

    fun handle(context: Context, method: String, args: Map<*, *>, reply: (Any?, String?) -> Unit) {
        val app = context.applicationContext
        val auth = FirebaseAuth.getInstance()
        val user = auth.currentUser ?: run { reply(null, "Sign in to your Fleet account first."); return }
        worker.execute {
            try {
                check(auth.currentUser?.uid == user.uid)
                val chosen = selection(app)
                val base = "fleets/${chosen["fleetId"]}/vehicles/${chosen["vehicleId"]}"
                val key = "${user.uid}/$base"
                if (cacheKey != key) { cloud.clear(); cacheKey = key; revision = -1; warning = null }
                val sync = FleetHistorySync.get(app)
                val api = FleetHistoryUpload(FirebaseApp.getInstance().options.projectId ?: error("Firebase unavailable"),
                    token = { Tasks.await(user.getIdToken(false), 15, TimeUnit.SECONDS).token ?: error("Sign in again") },
                    ownsSession = { auth.currentUser?.uid == user.uid })
                FleetOutbox(app).use { queue ->
                    if (method == "getFleetTrips") {
                        val trips = api.listTrips(base).map { doc ->
                            val fields = doc.getJSONObject("fields")
                            mapOf("id" to doc.getString("name").substringAfterLast('/'),
                                "startedAt" to fields.optJSONObject("startedAt")?.optString("timestampValue"),
                                "endedAt" to fields.optJSONObject("endedAt")?.optString("timestampValue"))
                        }
                        check(auth.currentUser?.uid == user.uid)
                        reply(trips, null)
                        return@execute
                    }
                    if (method == "getFleetMarkers" && (args["refresh"] == true || revision != sync.revision ||
                            (sync.online() && !wasOnline))) {
                        if (sync.online()) {
                            try {
                                val observedRevision = sync.revision
                                val docs = api.listMarkers(base)
                                cloud.clear()
                                docs.forEach { doc ->
                                    val path = doc.getString("name").substringAfter("/documents/")
                                    cloud[path] = row(path, doc.getJSONObject("fields"), user.uid)
                                }
                                revision = observedRevision
                                warning = null
                            } catch (_: Exception) {
                                // Không tiếp tục hiện cache khi quyền xe có thể đã bị thu hồi.
                                cloud.clear()
                                warning = "Cloud history unavailable. Check your connection and vehicle access, then refresh."
                                revision = sync.revision
                            }
                        } else {
                            warning = "Offline · showing saved markers on this phone. Refresh online to load cloud history."
                        }
                    }
                    wasOnline = sync.online()
                    if (!wasOnline) warning = "Offline · cloud history may be incomplete. Unsynced changes are saved on this phone."
                    val rows = cloud.mapValues { it.value.toMutableMap() }.toMutableMap()
                    queue.markers(user.uid).filter { it.path.startsWith("$base/markers/") }.forEach { entry ->
                        val path = entry.path.removeSuffix("/photos/image")
                        val item = rows.getOrPut(path) { row(path, entry.fields, user.uid) }
                        if (entry.kind == "marker") item.putAll(row(path, entry.fields, user.uid))
                        if (entry.kind == "photo") item["hasPhoto"] = true
                        if (entry.kind == "marker_edit") {
                            item["kind"] = entry.fields.getJSONObject("kind").getString("stringValue")
                            item["note"] = entry.fields.getJSONObject("note").getString("stringValue")
                        }
                        item["editable"] = entry.kind != "marker_delete"
                        item["deleting"] = entry.kind == "marker_delete"
                        item["status"] = when {
                            sync.uploadingPath?.removeSuffix("/photos/image") == path -> "Uploading"
                            sync.failedPath?.removeSuffix("/photos/image") == path -> "Upload failed"
                            else -> "Saved on phone"
                        }
                    }
                    val value: Any? = when (method) {
                        "getFleetMarkers" -> mapOf("items" to rows.values.sortedByDescending {
                            it["capturedAt"] as? String ?: ""
                        }.take(200), "warning" to warning, "online" to sync.online())
                        else -> {
                            val id = args["id"] as? String ?: error("Choose a marker")
                            require(markerPattern.matches(id))
                            val path = "$base/markers/$id"
                            val item = rows[path] ?: error("Refresh markers first")
                            when (method) {
                                "getFleetMarkerPhoto" -> {
                                    val photo = queue.photo(user.uid, path) ?: api.photo(path)
                                    require(photo != null && photo.length <= 204800 &&
                                        Regex("/9j/[A-Za-z0-9+/]*={0,2}").matches(photo))
                                    photo
                                }
                                "editFleetMarker", "deleteFleetMarker" -> {
                                    check(item["editable"] == true)
                                    val fields = JSONObject().put("driverUid", FleetHistoryUpload.string(user.uid))
                                    if (method == "editFleetMarker") {
                                        val kind = args["kind"] as? String ?: ""
                                        val note = (args["note"] as? String ?: "").trim()
                                        require(kind in FleetMarkers.kinds && note.length <= 500)
                                        fields.put("kind", FleetHistoryUpload.string(kind)).put("note", FleetHistoryUpload.string(note))
                                    }
                                    queue.mutateMarker(user.uid,
                                        if (method == "editFleetMarker") "marker_edit" else "marker_delete", path, fields)
                                    sync.requestSync(force = true)
                                    true
                                }
                                else -> error("Unknown marker action")
                            }
                        }
                    }
                    check(auth.currentUser?.uid == user.uid)
                    reply(value, null)
                }
            } catch (_: Exception) {
                if (auth.currentUser?.uid != user.uid) { cloud.clear(); cacheKey = "" }
                reply(null, "Could not complete this marker action. Check your account, connection and phone storage, then refresh.")
            }
        }
    }
}
