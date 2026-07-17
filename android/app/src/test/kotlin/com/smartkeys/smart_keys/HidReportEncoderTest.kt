package com.smartkeys.smart_keys

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class HidReportEncoderTest {
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
