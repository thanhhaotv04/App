package com.thanhhao.esp32_navride

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.json.JSONObject

class OsmAndNotificationParserTest {
    @Test
    fun readsBothTurnsFromTheSameOfficialSnapshotWithoutAddingPrimaryDistance() {
        val info = mapOf(
            "next_turn_type" to "TR", "next_turn_distance" to 250,
            "next_turn_name" to "Nguyen Thi Minh Khai",
            // The unusual key prefix and leg distance are from ExternalApiHelper.
            "after_nextturn_type" to "TL", "after_nextturn_distance" to 1600,
        )
        val navigation = OsmAndDirectionMapper.fromTurnInfo(info::get)!!
        assertEquals("right", navigation.maneuver)
        assertEquals(250, navigation.distanceMeters)
        assertEquals("Nguyen Thi Minh Khai", navigation.streetName)
        assertEquals(OsmAndTurnPreview(2, 1600), navigation.afterNext)
        val packet = JSONObject(NavigationBleSender.encodeNavigationPacket(navigation, 1, 1790900000L))
        assertEquals(2, packet.getInt("apiVersion"))
        assertEquals(5, packet.getInt("m"))
        assertEquals(250, packet.getInt("d"))
        assertEquals(navigation.streetName, packet.getString("s"))
        assertEquals(2, packet.getJSONArray("then").getInt(0))
        assertEquals(1600, packet.getJSONArray("then").getInt(1))
    }

    @Test
    fun missingOrInvalidSecondTurnNeverReusesAPreviousPreviewOrCurrentRoad() {
        val primary = mapOf<String, Any?>("next_turn_type" to "TR", "next_turn_distance" to 250)
        for (extra in listOf(
            emptyMap(),
            mapOf("after_nextturn_type" to "TL"),
            mapOf("after_nextturn_type" to "TL", "after_nextturn_distance" to -1),
            mapOf("after_nextturn_type" to "TL", "after_nextturn_distance" to 0),
            mapOf("after_nextturn_type" to "unknown", "after_nextturn_distance" to 300),
            mapOf("after_nextturn_type" to "OFFR", "after_nextturn_distance" to 300),
            mapOf("current_turn_type" to "TL", "current_turn_distance" to 300),
        )) {
            val info = primary + extra
            val navigation = OsmAndDirectionMapper.fromTurnInfo(info::get)!!
            assertNull(navigation.afterNext)
            assertEquals("", navigation.streetName)
            val packet = JSONObject(NavigationBleSender.encodeNavigationPacket(navigation, 1, 1790900000L))
            assertEquals(1, packet.getInt("apiVersion"))
            assertTrue(!packet.has("then"))
        }
        assertNull(OsmAndDirectionMapper.fromTurnInfo(emptyMap<String, Any?>()::get))
        assertNull(OsmAndNotificationParser.parse("250 m • Turn right onto Road")?.afterNext)
    }

    @Test
    fun secondRoundaboutPreservesItsOwnExitAndAngleAndAllPacketsFitAtt() {
        for (primaryType in 1..14) for (nextType in 1..14) {
            val navigation = OsmAndDirectionMapper.map(primaryType, 999999, false)!!.copy(
                streetName = "\\\"".repeat(80), exitNumber = 99, turnAngle = -180,
                afterNext = OsmAndTurnPreview(nextType, 999999, 99, -180),
            )
            val encoded = NavigationBleSender.encodeNavigationPacket(navigation, Int.MAX_VALUE, 1790900000L)
            assertTrue(encoded.toByteArray(Charsets.UTF_8).size <= 180)
            val packet = JSONObject(encoded)
            if (primaryType != 12 && nextType != 12) {
                assertEquals(primaryType, packet.getInt("m"))
                assertEquals(nextType, packet.getJSONArray("then").getInt(0))
                if (nextType == 13 || nextType == 14) {
                    assertEquals(99, packet.getJSONArray("then").getInt(2))
                    assertEquals(-180, packet.getJSONArray("then").getInt(3))
                }
            } else assertTrue(!packet.has("then"))
        }
        val info = mapOf("next_turn_type" to "TL", "next_turn_distance" to 500,
            "after_nextturn_type" to "RNDB4", "after_nextturn_distance" to 1200,
            "after_nextturn_angle" to -90f)
        assertEquals(OsmAndTurnPreview(13, 1200, 4, -90),
            OsmAndDirectionMapper.fromTurnInfo(info::get)?.afterNext)
        val bothRoundabouts = info + mapOf("next_turn_type" to "RNDB2", "next_turn_angle" to 0f)
        val snapshot = OsmAndDirectionMapper.fromTurnInfo(bothRoundabouts::get)!!
        assertEquals(2, snapshot.exitNumber)
        assertEquals(0, snapshot.turnAngle)
        assertEquals(OsmAndTurnPreview(13, 1200, 4, -90), snapshot.afterNext)
        val offRoute = info + mapOf("next_turn_type" to "OFFR")
        assertNull(OsmAndDirectionMapper.fromTurnInfo(offRoute::get)?.afterNext)
    }

    @Test
    fun invalidPreviewCannotBreakAnOtherwiseValidPrimaryPacket() {
        for (preview in listOf(
            OsmAndTurnPreview(0, 300), OsmAndTurnPreview(15, 300),
            OsmAndTurnPreview(2, -1), OsmAndTurnPreview(2, 1_000_000),
            OsmAndTurnPreview(13, 300, 100, 0), OsmAndTurnPreview(13, 300, 2, 181),
        )) {
            val packet = JSONObject(NavigationBleSender.encodeNavigationPacket(
                OsmAndNavigation("left", 250, "Nguyen Hue", afterNext = preview), 1, 1790900000L,
            ))
            assertEquals(1, packet.getInt("apiVersion"))
            assertEquals("left", packet.getString("maneuver"))
            assertEquals("Nguyen Hue", packet.getString("street"))
            assertTrue(!packet.has("then"))
        }
    }

    @Test
    fun longStreetUsesMoreThanThirtyTwoCharactersWithoutExceedingBleBudget() {
        val street = "Duong Nguyen Thi Minh Khai Quan Mot";
        val encoded = NavigationBleSender.encodeNavigationPacket(
            OsmAndNavigation("left", 250, street), 1, 1_791_700_000L,
        )
        assertEquals(street, JSONObject(encoded).getString("street"))
        assertTrue(encoded.toByteArray(Charsets.UTF_8).size <= 180)
    }

    @Test
    fun roundaboutAngleAcceptsNumericBundleTypesWithoutGuessingMissingAngle() {
        assertEquals(-90, OsmAndDirectionMapper.angleFromBundle(-90f))
        assertEquals(75, OsmAndDirectionMapper.angleFromBundle(75.4))
        assertEquals(120, OsmAndDirectionMapper.angleFromBundle(120))
        assertNull(OsmAndDirectionMapper.angleFromBundle(null))
        assertNull(OsmAndDirectionMapper.angleFromBundle("90"))
        assertNull(OsmAndDirectionMapper.angleFromBundle(Double.NaN))
        assertNull(OsmAndDirectionMapper.fromNextTurn("RNDB3", 250, "Road")?.turnAngle)
    }

    @Test
    fun roundaboutExitsOneThroughSixKeepRealAngleAndRoadInBlePacket() {
        for (exit in 1..6) {
            // Exit ordinal is not an angle: the same physical direction can
            // be exit 2 or exit 6 on different roundabouts.
            val navigation = OsmAndDirectionMapper.fromNextTurn(
                "RNDB$exit", 250, "Đường Võ Nguyên Giáp", -90,
            )!!
            val encoded = NavigationBleSender.encodeNavigationPacket(
                navigation, Int.MAX_VALUE, 1790900000L,
            )
            val packet = JSONObject(encoded)
            assertEquals(exit, packet.getInt("exit"))
            assertEquals(-90, packet.getInt("angle"))
            assertEquals("Duong Vo Nguyen Giap", packet.getString("street"))
            assertTrue(encoded.toByteArray(Charsets.UTF_8).size <= 180)
        }
    }

    @Test
    fun parsesOsmAnd54NotificationWithoutConfusingNextLegAndTotalDistances() {
        val result = OsmAndNotificationParser.parse(
            "60 m • Turn right and go\n" +
                "Turn right and go ĐT.43 Tỉnh lộ 43 1.6 km\n6.6 km • 8 min • 09:07",
        )
        assertEquals("right", result?.maneuver)
        assertEquals(60, result?.distanceMeters)
        assertEquals("ĐT.43 Tỉnh lộ 43", result?.streetName)
    }

    @Test
    fun keepsRoadNumbersAndAbbreviationsButNotTheFollowingLegDistance() {
        assertEquals("ĐT.43", OsmAndNotificationParser.parseStreet("Turn left onto ĐT.43"))
        assertEquals("Đường 3/2", OsmAndNotificationParser.parseStreet(
            "Turn left and go Đường 3/2 800 m\n2.1 km • 4 min"))
        assertEquals("", OsmAndNotificationParser.parseStreet("60 m • Turn right and go"))
        assertEquals("", OsmAndNotificationParser.parseStreet("Turn right and go 1.6 km"))
    }

    @Test
    fun navigationPacketFitsBleEvenWithEscapedStreetAndLargestRequestId() {
        for (street in listOf("Nguyễn Huệ", "\"".repeat(50), "\\".repeat(50), "🛵".repeat(50))) {
            val encoded = NavigationBleSender.encodeNavigationPacket(
                OsmAndNavigation("straight", 999999, street), Int.MAX_VALUE, 1790900000L,
            )
            assertTrue(encoded.toByteArray(Charsets.UTF_8).size <= 180)
            val packet = JSONObject(encoded)
            assertEquals(Int.MAX_VALUE, packet.getInt("requestId"))
            assertEquals("navigation", packet.getString("command"))
            assertEquals(999999, packet.getInt("distance_m"))
            assertEquals(1, packet.getInt("apiVersion"))
            if (street == "Nguyễn Huệ") assertEquals("Nguyen Hue", packet.getString("street"))
        }
    }

    @Test
    fun parsesVietnameseRightTurnInMeters() {
        val result = OsmAndNotificationParser.parse("Trong 250 m, rẽ phải")

        assertNotNull(result)
        assertEquals("right", result?.maneuver)
        assertEquals(250, result?.distanceMeters)
    }

    @Test
    fun parsesStreetNameFromEnglishTurnInstruction() {
        val result = OsmAndNotificationParser.parse(
            "In 250 m, turn right onto Main Street",
        )

        assertEquals("right", result?.maneuver)
        assertEquals(250, result?.distanceMeters)
        assertEquals("Main Street", result?.streetName)
    }

    @Test
    fun parsesStreetNameWithoutDirectionNotificationForAidlUpdates() {
        assertEquals(
            "Main Street",
            OsmAndNotificationParser.parseStreet("Next turn onto Main Street"),
        )
    }

    @Test
    fun usesTheRoadBeingTurnedOntoNotTheCurrentRoad() {
        assertEquals(
            "đường Nguyễn Huệ",
            OsmAndNotificationParser.parseStreet(
                "Đang trên đường Lê Lợi, sau 2 km rẽ phải vào đường Nguyễn Huệ",
            ),
        )
        assertEquals(
            "",
            OsmAndNotificationParser.parseStreet("Đang trên đường Lê Lợi"),
        )
    }

    @Test
    fun parsesVietnameseStreetName() {
        val result = OsmAndNotificationParser.parse(
            "Sau 0,5 km, rẽ trái vào đường Nguyễn Huệ",
        )

        assertEquals("left", result?.maneuver)
        assertEquals(500, result?.distanceMeters)
        assertEquals("đường Nguyễn Huệ", result?.streetName)
    }

    @Test
    fun parsesEnglishLeftTurnInKilometers() {
        val result = OsmAndNotificationParser.parse("Turn left in 1.2 km")

        assertNotNull(result)
        assertEquals("left", result?.maneuver)
        assertEquals(1200, result?.distanceMeters)
    }

    @Test
    fun ignoresUnrelatedNotifications() {
        assertEquals(null, OsmAndNotificationParser.parse("Battery 80 percent"))
    }

    @Test
    fun parsesVietnameseUTurnWithDecimalKilometers() {
        val result = OsmAndNotificationParser.parse("Sau 1,5 km, quay đầu")

        assertNotNull(result)
        assertEquals("u_turn", result?.maneuver)
        assertEquals(1500, result?.distanceMeters)
    }

    @Test
    fun parsesStraightAndArrivalWithoutDistance() {
        assertEquals(
            "straight",
            OsmAndNotificationParser.parse("Đi thẳng 300 m")?.maneuver,
        )
        assertEquals(
            "arrive",
            OsmAndNotificationParser.parse("Bạn đã đến nơi")?.maneuver,
        )
    }

    @Test
    fun parsesKeepRightAndVietnameseDistanceUnits() {
        val keepRight = OsmAndNotificationParser.parse("Keep right in 400 metres")
        val vietnamese = OsmAndNotificationParser.parse("Sau 1,2 kilômét, chếch trái")

        assertEquals("keep_right", keepRight?.maneuver)
        assertEquals(400, keepRight?.distanceMeters)
        assertEquals("slight_left", vietnamese?.maneuver)
        assertEquals(1200, vietnamese?.distanceMeters)
    }

    @Test
    fun notificationFallbackPreservesSpecificOsmAndTurnWords() {
        assertEquals("sharp_right", OsmAndNotificationParser.parse("Turn sharply right in 250 m")?.maneuver)
        assertEquals("slight_left", OsmAndNotificationParser.parse("Turn slightly left in 250 m")?.maneuver)
        assertEquals("u_turn_right", OsmAndNotificationParser.parse("Right U-turn in 250 m")?.maneuver)
        assertEquals("off_route", OsmAndNotificationParser.parse("Off route 250 m")?.maneuver)
    }

    @Test
    fun mapsOfficialOsmAndTurnTypes() {
        val allTypes = listOf(
            "straight", "left", "slight_left", "sharp_left", "right",
            "slight_right", "sharp_right", "keep_left", "keep_right",
            "u_turn", "u_turn_right", "off_route", "roundabout", "roundabout_left",
        )
        allTypes.forEachIndexed { index, expected ->
            assertEquals(expected, OsmAndDirectionMapper.map(index + 1, 400, false)?.maneuver)
        }
        assertEquals("roundabout_left", OsmAndDirectionMapper.map(13, 100, true)?.maneuver)
        assertEquals(null, OsmAndDirectionMapper.map(5, -1, false))
    }

    @Test
    fun snapshotKeepsNextStreetAndDistanceTogether() {
        assertEquals(OsmAndNavigation("roundabout", 1630, "Đường số 11", 4),
            OsmAndDirectionMapper.fromNextTurn("RNDB4", 1630, "Đường số 11"))
        assertEquals("", OsmAndDirectionMapper.fromNextTurn("TR", 250, null)?.streetName)
        assertEquals("off_route", OsmAndDirectionMapper.fromNextTurn("OFFR", 250, "Old road")?.maneuver)
        assertEquals(null, OsmAndDirectionMapper.fromNextTurn("TR", -1, "Old road"))
        assertEquals("roundabout_left", OsmAndDirectionMapper.fromNextTurn("RNLB2", 250, "Road")?.maneuver)
        assertEquals(OsmAndNavigation("roundabout", 250, "Road", 2, 0),
            OsmAndDirectionMapper.fromNextTurn("RNDB2", 250, "Road", 0))
        assertEquals(OsmAndNavigation("roundabout_left", 250, "Road", 1, 110),
            OsmAndDirectionMapper.fromNextTurn("RNLB1", 250, "Road", 110))
        assertEquals(-90, OsmAndDirectionMapper.fromNextTurn("RNDB3", 250, "Road", 270)?.turnAngle)
        assertEquals(null, OsmAndDirectionMapper.fromNextTurn("TR", 250, "Road", 90)?.turnAngle)
    }

    @Test
    fun officialTurnCodesRetainDistinctShapesAndFitBle() {
        val cases = mapOf(
            "TSLL" to "slight_left", "TSHL" to "sharp_left", "KL" to "keep_left",
            "TSLR" to "slight_right", "TSHR" to "sharp_right", "KR" to "keep_right",
            "TRU" to "u_turn_right", "OFFR" to "off_route",
        )
        cases.forEach { (code, expected) ->
            val turn = OsmAndDirectionMapper.fromNextTurn(code, 250, "Nguyen Hue")!!
            assertEquals(expected, turn.maneuver)
            assertEquals(expected, JSONObject(NavigationBleSender.encodeNavigationPacket(
                turn, 1, 1790900000L,
            )).getString("maneuver"))
        }
    }

    @Test
    fun roundaboutNotificationNeverBecomesRightTurn() {
        val parsed = OsmAndNotificationParser.parse("500 m • Take 4 exit\nTake 4 exit and go Đường số 11 1.2 km")
        assertEquals(OsmAndNavigation("roundabout", 500, "Đường số 11", 4), parsed)
        val encoded = NavigationBleSender.encodeNavigationPacket(
            OsmAndNavigation("roundabout_left", 999999, "\\\"".repeat(50)), Int.MAX_VALUE, 1790900000L)
        assertTrue(encoded.toByteArray(Charsets.UTF_8).size <= 180)
        val withAngle = NavigationBleSender.encodeNavigationPacket(
            OsmAndNavigation("roundabout", 250, "Nguyễn Huệ", 3, -110), Int.MAX_VALUE, 1790900000L)
        val packet = JSONObject(withAngle)
        assertEquals(-110, packet.getInt("angle"))
        assertEquals(3, packet.getInt("exit"))
        assertTrue(withAngle.toByteArray(Charsets.UTF_8).size <= 180)
    }
}
