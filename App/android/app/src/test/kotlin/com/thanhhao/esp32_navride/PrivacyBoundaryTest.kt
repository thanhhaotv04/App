package com.thanhhao.esp32_navride

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PrivacyBoundaryTest {
    @Test
    fun notificationsOnlyAcceptExactOsmAndPackages() {
        for (name in listOf("net.osmand", "net.osmand.plus", "net.osmand.dev")) {
            assertTrue(OsmAndPackages.isAllowed(name))
        }
        for (name in listOf("net.osmand.fake", "net.osmandplus", "net.osmand.plus.clone", "other.app", "")) {
            assertFalse(OsmAndPackages.isAllowed(name))
        }
    }
}
