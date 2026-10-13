package com.thanhhao.esp32_navride

import android.location.Location
import android.os.SystemClock
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseUser
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.*
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowSystemClock
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class FleetMarkersTest {
    @After fun cleanup() = FleetMarkers.end()

    private fun fix() = Location("gps").apply {
        latitude = 10.0; longitude = 106.0; accuracy = 5f
        elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos()
        time = System.currentTimeMillis()
    }

    private fun withAccount(body: (FirebaseAuth) -> Unit) {
        val auth = mock(FirebaseAuth::class.java)
        val user = mock(FirebaseUser::class.java)
        `when`(auth.currentUser).thenReturn(user)
        `when`(user.uid).thenReturn("owner")
        mockStatic(FirebaseAuth::class.java).use { firebase ->
            firebase.`when`<FirebaseAuth> { FirebaseAuth.getInstance() }.thenReturn(auth)
            FleetMarkers.begin("owner", "test", "test", "trip")
            body(auth)
        }
    }

    @Test fun markerReadinessFollowsFreshGpsAndResetsBetweenTrips() = withAccount {
        assertTrue(FleetMarkers.message.contains("Waiting"))
        FleetMarkers.update(fix())
        assertEquals("Ready to save a marker", FleetMarkers.message)
        ShadowSystemClock.advanceBy(Duration.ofSeconds(16))
        assertTrue(FleetMarkers.message.contains("Waiting"))
        FleetMarkers.end()
        assertTrue(FleetMarkers.message.contains("Start a Fleet trip"))
        FleetMarkers.begin("owner", "test", "test", "next-trip")
        assertTrue(FleetMarkers.message.contains("Waiting"))
    }

    @Test fun tripAccountAndGpsFailuresAreDistinguishedForTheDisplay() = withAccount { auth ->
        fun expectStatus(status: String) {
            val error = assertThrows(FleetMarkers.Failure::class.java) {
                FleetMarkers.prepare("food", "esp32")
            }
            assertEquals(status, error.status)
        }
        expectStatus("gps")
        FleetMarkers.update(fix())
        `when`(auth.currentUser).thenReturn(null)
        expectStatus("account")
        FleetMarkers.end()
        expectStatus("trip")
    }

    @Test fun cameraDraftKeepsThePositionFromWhenTheUserPressedSave() = withAccount {
        FleetMarkers.update(fix())
        val draft = FleetMarkers.prepare("save_point", "phone")
        FleetMarkers.update(fix().apply { latitude = 11.0 })
        val fields = draft.getJSONObject("fields")
        assertEquals(10.0, fields.getJSONObject("latitude").getDouble("doubleValue"), 0.0)
        assertEquals("save_point", fields.getJSONObject("kind").getString("stringValue"))
        ShadowSystemClock.advanceBy(Duration.ofSeconds(16))
        assertEquals("gps", assertThrows(FleetMarkers.Failure::class.java) {
            FleetMarkers.prepare("food", "esp32")
        }.status)
    }
}
