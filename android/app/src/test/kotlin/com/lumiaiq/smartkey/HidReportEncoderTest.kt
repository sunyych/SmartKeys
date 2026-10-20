package com.lumiaiq.smartkey

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HidReportEncoderTest {
    @Test
    fun asciiTextStrokePressAndReleaseUseUsKeyboardUsageAndShiftBit() {
        val encoder = HidReportEncoder()
        val uppercaseA = HidTextStroke(usage = 0x04, shift = true)

        val pressed = encoder.pressTextStroke(uppercaseA)!!
        assertEquals(HidReportEncoder.KEYBOARD_REPORT_ID, pressed.id)
        assertArrayEquals(byteArrayOf(0x02, 0, 0x04, 0, 0, 0, 0, 0), pressed.data)
        assertTrue(encoder.hasHeldInput)

        val released = encoder.releaseTextStroke(uppercaseA)!!
        assertArrayEquals(ByteArray(8), released.data)
        assertFalse(encoder.hasHeldInput)
        assertNull(encoder.pressTextStroke(HidTextStroke(usage = 0x03, shift = false)))
        assertNull(encoder.pressTextStroke(HidTextStroke(usage = 0x28, shift = false)))
        assertNull(encoder.pressTextStroke(HidTextStroke(usage = 0x2b, shift = false)))
        assertNull(encoder.pressTextStroke(HidTextStroke(usage = 0x39, shift = false)))
    }

    @Test
    fun unicodeHexFramesHoldAndReleaseOnlyLeftAltAndKeypadKeys() {
        val encoder = HidReportEncoder()
        val frames = WindowsHexNumpadEncoder.strokesFor(0x4e2d)
        assertEquals(5, frames.size)
        frames.forEachIndexed { index, stroke ->
            val pressed = encoder.pressUnicodeHexStroke(stroke)!!
            assertEquals(HidReportEncoder.KEYBOARD_REPORT_ID, pressed.id)
            assertEquals(4, pressed.data[0].toInt())
            assertEquals(stroke.usage, pressed.data[2].toInt())
            val released = encoder.releaseUnicodeHexStroke(stroke)!!
            if (index == frames.lastIndex) {
                assertArrayEquals(ByteArray(8), released.data)
            } else {
                assertEquals(4, released.data[0].toInt())
            }
        }
        assertFalse(encoder.hasHeldInput)
        assertNull(
            encoder.pressUnicodeHexStroke(
                HidTextKeyStroke(usage = 0x28, unicodeHex = true, altStart = true),
            ),
        )
    }

    @Test
    fun textBatchBoundaryRejectsMalformedBoundsAndNonPrintableUsages() {
        fun request(strokes: Any? = listOf(mapOf("usage" to 0x04, "shift" to false))) =
            mapOf(
                "sessionToken" to "session-a",
                "expectedAddress" to "00:11:22:33:44:55",
                "profile" to "usAscii",
                "strokes" to strokes,
                "codePoints" to emptyList<Int>(),
            )

        val valid = HidTextBatchValidator.parse(request())!!
        assertEquals("session-a", valid.sessionToken)
        assertEquals("00:11:22:33:44:55", valid.expectedAddress)
        assertEquals(listOf(HidTextKeyStroke(0x04, false)), valid.strokes)

        assertNull(HidTextBatchValidator.parse(null))
        assertNull(HidTextBatchValidator.parse(request(emptyList<Any>())))
        assertNull(
            HidTextBatchValidator.parse(
                request(List(HidTextBatchValidator.MAX_STROKES + 1) {
                    mapOf("usage" to 0x04, "shift" to false)
                }),
            ),
        )
        assertNull(
            HidTextBatchValidator.parse(
                request(listOf(mapOf("usage" to 0x28, "shift" to false))),
            ),
        )
        assertNull(
            HidTextBatchValidator.parse(
                request(listOf(mapOf("usage" to 4.5, "shift" to false))),
            ),
        )
        assertNull(
            HidTextBatchValidator.parse(
                request().toMutableMap().apply { put("expectedAddress", "bad-address") },
            ),
        )
        assertNull(
            HidTextBatchValidator.parse(
                request(listOf(mapOf("usage" to 0x04, "shift" to false, "extra" to true))),
            ),
        )
    }

    @Test
    fun windowsUnicodeBatchGeneratesOnlyAltHexNumpadFrames() {
        val request = HidTextBatchValidator.parse(
            mapOf(
                "sessionToken" to "windows-session",
                "expectedAddress" to "00:11:22:33:44:55",
                "profile" to "windowsHexNumpad",
                "strokes" to emptyList<Any>(),
                "codePoints" to listOf(0x41, 0x4e2d),
            ),
        )!!
        assertEquals(HidTextProfile.WINDOWS_HEX_NUMPAD, request.profile)
        // U+0041 is 0, 0, keypad-4, keypad-1; U+4E2D is keypad-4, E, keypad-2, D.
        assertEquals(
            listOf(0x57, 0x62, 0x62, 0x5c, 0x59, 0x57, 0x5c, 0x08, 0x5a, 0x07),
            request.strokes.map { it.usage },
        )
        assertTrue(request.strokes.first().altStart)
        assertTrue(request.strokes[4].altEnd)
        assertTrue(request.strokes[5].altStart)
        assertTrue(request.strokes.last().altEnd)
        assertTrue(request.strokes.all { it.unicodeHex && !it.shift })

        fun accepted(vararg codePoints: Int): Boolean = HidTextBatchValidator.parse(
            mapOf(
                "sessionToken" to "windows-session",
                "expectedAddress" to "00:11:22:33:44:55",
                "profile" to "windowsHexNumpad",
                "strokes" to emptyList<Any>(),
                "codePoints" to codePoints.toList(),
            ),
        ) != null
        fun rejected(codePoint: Int): Boolean = !accepted(codePoint)
        assertTrue(accepted(0x4f60, 0x597d, 0xff0c, 0x4e16, 0x754c, 0xff01, 0x3042, 0xd55c))
        assertTrue(rejected(0x0a))
        assertTrue(rejected(0x80))
        assertTrue(rejected(0x1f600))
        assertTrue(rejected(0xd800))
        assertTrue(rejected(0x2028))
        assertTrue(rejected(0xfeff))
        assertTrue(rejected(0xfffe))
    }

    @Test
    fun navigationInputCancelsAnActiveTextBatchBeforeInterleaving() {
        val gate = HidTextBatchGate()
        assertTrue(gate.begin("dictation-1"))
        assertFalse(gate.allowsNavigationInput())
        assertFalse(gate.begin("dictation-2"))
        assertFalse(gate.cancel("another-session"))

        // sendPress/sendRelease/sendStep call releaseAllInput before emitting
        // their report; this gate is the controller's native exclusivity state.
        assertTrue(gate.cancelForNavigation())
        assertTrue(gate.allowsNavigationInput())
        assertFalse(gate.isActive())
        assertFalse(gate.finish("dictation-1"))
    }

    @Test
    fun ctrlCPressAndReleaseProduceKeyboardReports() {
        val encoder = HidReportEncoder()
        val action = HidActionData("keyboard", "KEY_C", listOf("LEFT_CTRL"), null)

        val pressed = encoder.press(action)!!
        assertEquals(HidReportEncoder.KEYBOARD_REPORT_ID, pressed.id)
        assertArrayEquals(byteArrayOf(1, 0, 6, 0, 0, 0, 0, 0), pressed.data)

        val released = encoder.release(action)!!
        assertArrayEquals(ByteArray(8), released.data)
    }

    @Test
    fun commandCUsesTheLeftMetaModifierBit() {
        val encoder = HidReportEncoder()
        val action = HidActionData("keyboard", "KEY_C", listOf("LEFT_META"), null)

        val pressed = encoder.press(action)!!

        assertArrayEquals(byteArrayOf(8, 0, 6, 0, 0, 0, 0, 0), pressed.data)
    }

    @Test
    fun overlappingModifiersAreReferenceCounted() {
        val encoder = HidReportEncoder()
        val copy = HidActionData("keyboard", "KEY_C", listOf("LEFT_CTRL"), null)
        val save = HidActionData("keyboard", "KEY_S", listOf("LEFT_CTRL"), null)
        encoder.press(copy)
        encoder.press(save)

        val afterCopyRelease = encoder.release(copy)!!
        assertEquals(1, afterCopyRelease.data[0].toInt())
        assertEquals(22, afterCopyRelease.data[2].toInt())
    }

    @Test
    fun consumerAndWheelStepsSendActiveThenNeutralReports() {
        val encoder = HidReportEncoder()
        val volume = encoder.step(HidActionData("consumerControl", null, emptyList(), "VOLUME_UP"))
        assertArrayEquals(byteArrayOf(0xe9.toByte(), 0), volume[0].data)
        assertArrayEquals(byteArrayOf(0, 0), volume[1].data)

        val wheel = encoder.step(HidActionData("mouseWheel", null, emptyList(), "WHEEL_DOWN"))
        assertArrayEquals(byteArrayOf(0, 0, 0, -1), wheel[0].data)
        assertArrayEquals(byteArrayOf(0, 0, 0, 0), wheel[1].data)
    }

    @Test
    fun brightnessStepsUseDisplayAndKeyboardConsumerUsages() {
        val encoder = HidReportEncoder()

        val displayDown = encoder.step(
            HidActionData("consumerControl", null, emptyList(), "BRIGHTNESS_DOWN"),
        )
        val displayUp = encoder.step(
            HidActionData("consumerControl", null, emptyList(), "BRIGHTNESS_UP"),
        )
        val keyboardDown = encoder.step(
            HidActionData("consumerControl", null, emptyList(), "KEYBOARD_BRIGHTNESS_DOWN"),
        )
        val keyboardUp = encoder.step(
            HidActionData("consumerControl", null, emptyList(), "KEYBOARD_BRIGHTNESS_UP"),
        )
        val keyboardMinimum = encoder.step(
            HidActionData("consumerControl", null, emptyList(), "KEYBOARD_BACKLIGHT_MINIMUM"),
        )
        val keyboardMaximum = encoder.step(
            HidActionData("consumerControl", null, emptyList(), "KEYBOARD_BACKLIGHT_MAXIMUM"),
        )

        assertArrayEquals(byteArrayOf(0x70, 0), displayDown[0].data)
        assertArrayEquals(byteArrayOf(0x6f, 0), displayUp[0].data)
        assertArrayEquals(byteArrayOf(0x7a, 0), keyboardDown[0].data)
        assertArrayEquals(byteArrayOf(0x79, 0), keyboardUp[0].data)
        assertArrayEquals(byteArrayOf(0x7d, 0), keyboardMinimum[0].data)
        assertArrayEquals(byteArrayOf(0x7e, 0), keyboardMaximum[0].data)
        assertArrayEquals(byteArrayOf(0, 0), keyboardMaximum[1].data)
    }

    @Test
    fun mouseDirectionsProduceRelativeMovementAndNeutralRelease() {
        val encoder = HidReportEncoder()

        val up = encoder.press(HidActionData("mouseMove", null, emptyList(), "UP"))!!
        val right = encoder.press(HidActionData("mouseMove", null, emptyList(), "RIGHT"))!!
        val released = encoder.release(HidActionData("mouseMove", null, emptyList(), "RIGHT"))!!

        assertArrayEquals(byteArrayOf(0, 0, -8, 0), up.data)
        assertArrayEquals(byteArrayOf(0, 8, 0, 0), right.data)
        assertArrayEquals(byteArrayOf(0, 0, 0, 0), released.data)
    }

    @Test
    fun touchpadMovementAndMouseButtonsUseTheRelativeMouseReport() {
        val encoder = HidReportEncoder()

        val moved = encoder.press(HidActionData("mouseMove", null, emptyList(), "12,-7"))!!
        val leftDown = encoder.press(HidActionData("mouseButton", null, emptyList(), "LEFT"))!!
        val rightDown = encoder.press(HidActionData("mouseButton", null, emptyList(), "RIGHT"))!!
        val leftUp = encoder.release(HidActionData("mouseButton", null, emptyList(), "LEFT"))!!
        val rightUp = encoder.release(HidActionData("mouseButton", null, emptyList(), "RIGHT"))!!

        assertArrayEquals(byteArrayOf(0, 12, -7, 0), moved.data)
        assertArrayEquals(byteArrayOf(1, 0, 0, 0), leftDown.data)
        assertArrayEquals(byteArrayOf(3, 0, 0, 0), rightDown.data)
        assertArrayEquals(byteArrayOf(2, 0, 0, 0), leftUp.data)
        assertArrayEquals(byteArrayOf(0, 0, 0, 0), rightUp.data)
    }

    @Test
    fun releaseAllClearsEveryReportType() {
        val encoder = HidReportEncoder()
        encoder.press(HidActionData("keyboard", "KEY_A", listOf("LEFT_SHIFT"), null))
        val reports = encoder.releaseAll()

        assertEquals(listOf(1, 2, 3), reports.map { it.id })
        assertArrayEquals(ByteArray(8), reports[0].data)
    }
}
