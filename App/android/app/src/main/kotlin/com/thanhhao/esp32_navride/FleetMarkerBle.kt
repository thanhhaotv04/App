package com.thanhhao.esp32_navride

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONObject

/** Khử trùng yêu cầu; ACK nghĩa là đã ghi bền vững vào hàng đợi, chưa chắc đã lên cloud. */
internal object FleetMarkerBle {
    private val handler = Handler(Looper.getMainLooper())
    private val replies = linkedMapOf<String, String>()
    fun receive(context: Context, value: String) {
        val parts = value.split(':')
        if (parts.size != 3 || parts[1] !in FleetMarkers.kinds ||
            !parts[2].matches(Regex("[0-9a-f]{1,8}-[0-9]{1,10}"))) return
        handler.post {
            val id = parts[2]
            val status = replies.getOrPut(id) {
                if (!SpeedService.fleetActive) "trip"
                else try {
                    if (FleetMarkers.save(context, FleetMarkers.prepare(parts[1], "esp32"))) "saved" else "storage"
                } catch (error: FleetMarkers.Failure) { error.status }
                catch (_: Exception) { "storage" }
            }
            while (replies.size > 64) replies.remove(replies.keys.first())
            val payload = JSONObject().put("apiVersion", 1).put("command", "marker_result")
                .put("id", id).put("status", status).toString()
            fun reply(attempt: Int) {
                if (!NavigationBleSender.sendMarkerResult(context, payload) && attempt < 100)
                    handler.postDelayed({ reply(attempt + 1) }, 100)
            }
            reply(0)
        }
    }
}
