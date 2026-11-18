package com.lumiaiq.bluetoothlite

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class ModifierOnlyTest {
    @Test
    fun shiftOnlyNeverContainsAnAlphabeticKeyUsage() {
        val encoder = HidReportEncoder()
        val shift = HidActionData("keyboard", null, listOf("LEFT_SHIFT"), null)
        val pressed = encoder.press(shift)!!.data
        assertEquals(2.toByte(), pressed[0])
        assertArrayEquals(ByteArray(6), pressed.copyOfRange(2, 8))
        assertArrayEquals(ByteArray(8), encoder.release(shift)!!.data)
    }
}
