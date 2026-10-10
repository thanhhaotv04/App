package com.thanhhao.esp32_navride

import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

internal object FleetLocationPolicy {
    const val UPLOAD_INTERVAL_MS = 30_000L
    const val TRACK_INTERVAL_MS = 60_000L
    const val TRACK_MIN_MOVE_METERS = 100.0

    fun accepts(
        ageMs: Long,
        accuracyMeters: Float?,
        mock: Boolean,
        latitude: Double,
        longitude: Double,
    ): Boolean = !mock && ageMs in 0..15_000 &&
        accuracyMeters != null && accuracyMeters in 0f..50f &&
        latitude.isFinite() && latitude in -90.0..90.0 &&
        longitude.isFinite() && longitude in -180.0..180.0

    fun shouldUpload(now: Long, previousAttempt: Long, pending: Boolean): Boolean =
        !pending && (previousAttempt == 0L || now - previousAttempt >= UPLOAD_INTERVAL_MS)

    fun shouldRecordTrack(now: Long, previousPointAt: Long, distanceMeters: Double): Boolean =
        previousPointAt == 0L ||
            (now - previousPointAt >= TRACK_INTERVAL_MS
                && distanceMeters > TRACK_MIN_MOVE_METERS)

    fun distanceMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = sin(dLat / 2) * sin(dLat / 2) +
            cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) *
            sin(dLon / 2) * sin(dLon / 2)
        return 2 * 6_371_000.0 * asin(sqrt(a.coerceIn(0.0, 1.0)))
    }
}
