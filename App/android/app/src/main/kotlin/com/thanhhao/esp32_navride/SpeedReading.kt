package com.thanhhao.esp32_navride

import kotlin.math.roundToInt

/** Pure validation shared by the GPS service and JVM tests. No position is stored. */
internal object SpeedReading {
    const val MAX_AGE_MS = 5_000L

    fun kmh(hasSpeed: Boolean, metersPerSecond: Float, ageMs: Long,
            accuracyMps: Float? = null): Int? {
        if (!hasSpeed || !metersPerSecond.isFinite() || metersPerSecond < 0 ||
            ageMs !in 0..MAX_AGE_MS || metersPerSecond * 3.6f > 300 ||
            accuracyMps != null && (!accuracyMps.isFinite() || accuracyMps !in 0f..3f)
        ) return null
        return (metersPerSecond * 3.6f).roundToInt()
    }

    fun packet(kmh: Int?): String =
        """{"apiVersion":1,"command":"speed","kmh":${kmh ?: "null"}}"""
}
