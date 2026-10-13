package com.thanhhao.esp32_navride

import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Firestore REST dùng ID token tài xế, vẫn chịu Security Rules; không dùng khóa admin. */
internal class FleetHistoryUpload(
    projectId: String,
    private val token: () -> String,
    private val ownsSession: () -> Boolean,
    private val endpoint: String = "https://firestore.googleapis.com/v1",
) {
    private val documents: String

    init {
        require(projectId.matches(Regex("[a-z0-9-]{1,63}")))
        documents = "projects/$projectId/databases/(default)/documents"
    }

    companion object {
        fun timestamp(time: Date): JSONObject = JSONObject().put("timestampValue",
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }.format(time))
        fun string(value: String): JSONObject = JSONObject().put("stringValue", value)
        fun number(value: Double): JSONObject = JSONObject().put("doubleValue", value)
        fun nullableSpeed(value: Int?): JSONObject = if (value == null) nullValue()
            else JSONObject().put("integerValue", value.toString())
        fun nullValue(): JSONObject = JSONObject().put("nullValue", JSONObject.NULL)

        private fun normalizedTime(value: String): String = value.replace(
            Regex("(?:\\.(\\d{1,9}))?Z$"),
        ) { "." + it.groupValues[1].padEnd(3, '0').take(3) + "Z" }

        private fun sameValue(expected: JSONObject, actual: JSONObject): Boolean = when {
            expected.has("timestampValue") -> normalizedTime(expected.getString("timestampValue")) ==
                normalizedTime(actual.optString("timestampValue"))
            expected.has("nullValue") -> actual.has("nullValue")
            expected.has("booleanValue") -> actual.has("booleanValue") &&
                expected.getBoolean("booleanValue") == actual.getBoolean("booleanValue")
            expected.has("stringValue") -> expected.getString("stringValue") == actual.optString("stringValue")
            else -> {
                val wanted = expected.opt("doubleValue") ?: expected.opt("integerValue")
                val found = actual.opt("doubleValue") ?: actual.opt("integerValue")
                wanted.toString().toDoubleOrNull() != null &&
                    wanted.toString().toDoubleOrNull() == found.toString().toDoubleOrNull()
            }
        }

        fun matches(entry: FleetOutbox.Entry, remote: JSONObject): Boolean {
            val fields = remote.optJSONObject("fields") ?: return false
            if (entry.kind != "point" && fields.optJSONObject("driverUid")?.optString("stringValue") != entry.uid) return false
            return entry.fields.keys().asSequence().all { key ->
                // start có thể đã được gửi trước khi app đóng, sau đó chuyến đã kết thúc.
                if (entry.kind == "start" && key == "endedAt") true
                else fields.optJSONObject(key)?.let { sameValue(entry.fields.getJSONObject(key), it) } == true
            }
        }
    }

    private fun request(method: String, path: String, body: JSONObject? = null): Pair<Int, JSONObject> {
        check(ownsSession()) { "Fleet account changed" }
        val bearer = token()
        check(ownsSession()) { "Fleet account changed" }
        val connection = URL("$endpoint/$documents$path").openConnection() as HttpURLConnection
        try {
            connection.requestMethod = method
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            connection.connectTimeout = 15_000
            connection.readTimeout = 15_000
            connection.setRequestProperty("Authorization", "Bearer $bearer")
            connection.setRequestProperty("Accept", "application/json")
            if (body != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            }
            val status = connection.responseCode
            val input = if (status in 200..299) connection.inputStream else connection.errorStream
            // Không đưa URL, tọa độ, token hoặc nội dung lỗi server vào log/UI.
            val text = input?.bufferedReader()?.use { it.readText() }.orEmpty()
            return status to if (text.isEmpty()) JSONObject() else JSONObject(text)
        } finally { connection.disconnect() }
    }

    fun upload(entry: FleetOutbox.Entry) {
        val (status, existing) = request("GET", "/${entry.path}")
        if (entry.kind == "marker_delete") {
            if (status == 404) return
            if (status != 200 || existing.optJSONObject("fields")?.optJSONObject("driverUid")?.optString("stringValue") != entry.uid)
                throw IOException("Marker deletion could not be confirmed")
            val writes = JSONArray()
                .put(JSONObject().put("delete", "$documents/${entry.path}/photos/image"))
                .put(JSONObject().put("delete", "$documents/${entry.path}"))
            val (code, reply) = request("POST", ":commit", JSONObject().put("writes", writes))
            if (code != 200 || reply.optJSONArray("writeResults")?.length() != 2 || !reply.has("commitTime"))
                throw IOException("Marker deletion could not be confirmed")
            return
        }
        if (status == 200 && matches(entry, existing)) return
        // Xóa trên thiết bị khác thắng bản sửa offline; không tái tạo điểm đã xóa
        // và không để bản sửa này chặn mọi điểm/ảnh phía sau trong hàng đợi.
        if (entry.kind == "marker_edit" && status == 404) return
        if (entry.kind == "marker_edit" && (status != 200 ||
                existing.optJSONObject("fields")?.optJSONObject("driverUid")?.optString("stringValue") != entry.uid))
            throw IOException("Marker edit could not be confirmed")
        if (entry.kind != "marker_edit" && status != 404 && !(status == 200 && entry.kind == "end" &&
                existing.optJSONObject("fields")?.optJSONObject("endedAt")?.has("nullValue") == true)) {
            throw IOException("Route sync could not be confirmed")
        }
        val transform = if (entry.kind in setOf("point", "marker", "photo")) "uploadedAt" else "updatedAt"
        val write = JSONObject().put("update", JSONObject()
            .put("name", "$documents/${entry.path}").put("fields", entry.fields))
            .put("updateTransforms", JSONArray().put(JSONObject()
                .put("fieldPath", transform).put("setToServerValue", "REQUEST_TIME")))
            .put("currentDocument", JSONObject().put("exists", entry.kind in setOf("end", "marker_edit")))
        if (entry.kind == "marker_edit") {
            write.put("updateMask", JSONObject().put("fieldPaths", JSONArray().put("kind").put("note")))
        }
        if (entry.kind == "end") {
            write.put("updateMask", JSONObject().put("fieldPaths", JSONArray().put("endedAt")))
        }
        val (commitStatus, result) = request("POST", ":commit",
            JSONObject().put("writes", JSONArray().put(write)))
        if (commitStatus != 200 || result.optJSONArray("writeResults")?.length() != 1 || !result.has("commitTime")) {
            // Không xóa bản chờ; lần sau GET sẽ xác minh nếu server đã nhận mà ACK bị mất.
            throw IOException("Route sync could not be confirmed")
        }
    }

    fun listMarkers(base: String): List<JSONObject> {
        require(base.matches(Regex("fleets/[A-Za-z0-9_-]{1,64}/vehicles/[A-Za-z0-9_-]{1,64}")))
        val (code, reply) = request("GET", "/$base/markers?pageSize=200&orderBy=capturedAt%20desc")
        if (code !in 200..299) throw IOException("Cloud markers unavailable")
        val docs = reply.optJSONArray("documents") ?: return emptyList()
        return (0 until docs.length()).map { docs.getJSONObject(it) }
    }

    fun photo(path: String): String? {
        val (code, reply) = request("GET", "/$path/photos/image")
        if (code == 404) return null
        if (code != 200) throw IOException("Photo unavailable")
        return reply.optJSONObject("fields")?.optJSONObject("data")?.optString("stringValue")
    }

    fun listTrips(base: String): List<JSONObject> {
        require(base.matches(Regex("fleets/[A-Za-z0-9_-]{1,64}/vehicles/[A-Za-z0-9_-]{1,64}")))
        val (code, reply) = request("GET", "/$base/trips?pageSize=100&orderBy=startedAt%20desc")
        if (code !in 200..299) throw IOException("Trip history unavailable")
        val docs = reply.optJSONArray("documents") ?: return emptyList()
        return (0 until docs.length()).map { docs.getJSONObject(it) }
    }
}
