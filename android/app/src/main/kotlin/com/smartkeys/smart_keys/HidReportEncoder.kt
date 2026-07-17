package com.smartkeys.smart_keys

data class HidReport(val id: Int, val data: ByteArray)

data class HidActionData(
    val type: String,
    val keyCode: String?,
    val modifiers: List<String>,
    val value: String?,
) {
    companion object {
        fun from(arguments: Any?): HidActionData {
            val map = arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
            return HidActionData(
                type = map["type"]?.toString() ?: "none",
                keyCode = map["keyCode"]?.toString(),
                modifiers = (map["modifiers"] as? List<*>)
                    ?.mapNotNull { it?.toString() }
                    ?: emptyList(),
                value = map["value"]?.toString(),
            )
        }
    }
}

class HidReportEncoder {
    private val keyCounts = mutableMapOf<Int, Int>()
    private val modifierCounts = mutableMapOf<Int, Int>()

    fun press(action: HidActionData): HidReport? = when (action.type) {
        "keyboard" -> {
            keyUsage(action.keyCode)?.let { usage ->
                keyCounts[usage] = (keyCounts[usage] ?: 0) + 1
            }
            action.modifiers.mapNotNull(::modifierBit).forEach { bit ->
                modifierCounts[bit] = (modifierCounts[bit] ?: 0) + 1
            }
            keyboardReport()
        }
        "consumerControl" -> consumerReport(consumerUsage(action.value))
        "mouseWheel" -> mouseReport(wheel = wheelDelta(action.value))
        "mouseMove" -> mouseDelta(action.value).let { (x, y) -> mouseReport(x = x, y = y) }
        else -> null
    }

    fun release(action: HidActionData): HidReport? = when (action.type) {
        "keyboard" -> {
            keyUsage(action.keyCode)?.let(::decrementKey)
            action.modifiers.mapNotNull(::modifierBit).forEach(::decrementModifier)
            keyboardReport()
        }
        "consumerControl" -> consumerReport(0)
        "mouseWheel", "mouseMove" -> mouseReport()
        else -> null
    }

    fun step(action: HidActionData): List<HidReport> {
        val pressed = press(action) ?: return emptyList()
        val released = release(action) ?: return listOf(pressed)
        return listOf(pressed, released)
    }

    fun releaseAll(): List<HidReport> {
        keyCounts.clear()
        modifierCounts.clear()
        return listOf(keyboardReport(), consumerReport(0), mouseReport())
    }

    fun reportForId(id: Int): HidReport? = when (id) {
        KEYBOARD_REPORT_ID -> keyboardReport()
        CONSUMER_REPORT_ID -> consumerReport(0)
        MOUSE_REPORT_ID -> mouseReport()
        else -> null
    }

    private fun decrementKey(usage: Int) {
        val remaining = (keyCounts[usage] ?: 0) - 1
        if (remaining <= 0) keyCounts.remove(usage) else keyCounts[usage] = remaining
    }

    private fun decrementModifier(bit: Int) {
        val remaining = (modifierCounts[bit] ?: 0) - 1
        if (remaining <= 0) modifierCounts.remove(bit) else modifierCounts[bit] = remaining
    }

    private fun keyboardReport(): HidReport {
        var modifiers = 0
        modifierCounts.keys.forEach { bit -> modifiers = modifiers or (1 shl bit) }
        val usages = keyCounts.keys.sorted().take(6)
        val data = ByteArray(8)
        data[0] = modifiers.toByte()
        usages.forEachIndexed { index, usage -> data[index + 2] = usage.toByte() }
        return HidReport(KEYBOARD_REPORT_ID, data)
    }

    private fun consumerReport(usage: Int): HidReport = HidReport(
        CONSUMER_REPORT_ID,
        byteArrayOf((usage and 0xff).toByte(), ((usage shr 8) and 0xff).toByte()),
    )

    private fun mouseReport(x: Int = 0, y: Int = 0, wheel: Int = 0): HidReport = HidReport(
        MOUSE_REPORT_ID,
        byteArrayOf(
            0,
            x.coerceIn(-127, 127).toByte(),
            y.coerceIn(-127, 127).toByte(),
            wheel.coerceIn(-127, 127).toByte(),
        ),
    )

    private fun modifierBit(name: String): Int? = MODIFIER_BITS[name.uppercase()]

    private fun keyUsage(rawName: String?): Int? {
        val name = rawName?.uppercase()?.removePrefix("KEY_") ?: return null
        if (name.length == 1 && name[0] in 'A'..'Z') return 0x04 + (name[0] - 'A')
        if (name.length == 1 && name[0] in '1'..'9') return 0x1e + (name[0] - '1')
        if (name == "0") return 0x27
        if (name.startsWith("F")) {
            val number = name.removePrefix("F").toIntOrNull()
            if (number in 1..12) return 0x3a + (number!! - 1)
        }
        return KEY_USAGES[name]
    }

    private fun consumerUsage(rawName: String?): Int = CONSUMER_USAGES[
        rawName?.uppercase()?.removePrefix("CONSUMER_")
    ] ?: 0

    private fun wheelDelta(rawName: String?): Int = when (rawName?.uppercase()) {
        "WHEEL_UP", "UP" -> 1
        "WHEEL_DOWN", "DOWN" -> -1
        else -> rawName?.toIntOrNull()?.coerceIn(-127, 127) ?: 0
    }

    private fun mouseDelta(rawName: String?): Pair<Int, Int> = when (rawName?.uppercase()) {
        "UP" -> 0 to -8
        "DOWN" -> 0 to 8
        "LEFT" -> -8 to 0
        "RIGHT" -> 8 to 0
        else -> 0 to 0
    }

    companion object {
        const val KEYBOARD_REPORT_ID = 1
        const val CONSUMER_REPORT_ID = 2
        const val MOUSE_REPORT_ID = 3

        private val MODIFIER_BITS = mapOf(
            "LEFT_CTRL" to 0,
            "LEFT_SHIFT" to 1,
            "LEFT_ALT" to 2,
            "LEFT_META" to 3,
            "LEFT_GUI" to 3,
            "RIGHT_CTRL" to 4,
            "RIGHT_SHIFT" to 5,
            "RIGHT_ALT" to 6,
            "RIGHT_META" to 7,
            "RIGHT_GUI" to 7,
        )

        private val KEY_USAGES = mapOf(
            "ENTER" to 0x28,
            "RETURN" to 0x28,
            "ESCAPE" to 0x29,
            "ESC" to 0x29,
            "BACKSPACE" to 0x2a,
            "TAB" to 0x2b,
            "SPACE" to 0x2c,
            "MINUS" to 0x2d,
            "EQUALS" to 0x2e,
            "LEFT_BRACKET" to 0x2f,
            "RIGHT_BRACKET" to 0x30,
            "BACKSLASH" to 0x31,
            "SEMICOLON" to 0x33,
            "APOSTROPHE" to 0x34,
            "GRAVE" to 0x35,
            "COMMA" to 0x36,
            "PERIOD" to 0x37,
            "DOT" to 0x37,
            "SLASH" to 0x38,
            "CAPS_LOCK" to 0x39,
            "PRINT_SCREEN" to 0x46,
            "SCROLL_LOCK" to 0x47,
            "PAUSE" to 0x48,
            "INSERT" to 0x49,
            "HOME" to 0x4a,
            "PAGE_UP" to 0x4b,
            "DELETE" to 0x4c,
            "END" to 0x4d,
            "PAGE_DOWN" to 0x4e,
            "RIGHT" to 0x4f,
            "ARROW_RIGHT" to 0x4f,
            "LEFT" to 0x50,
            "ARROW_LEFT" to 0x50,
            "DOWN" to 0x51,
            "ARROW_DOWN" to 0x51,
            "UP" to 0x52,
            "ARROW_UP" to 0x52,
            "NUM_LOCK" to 0x53,
            "KEYPAD_DIVIDE" to 0x54,
            "KEYPAD_MULTIPLY" to 0x55,
            "KEYPAD_MINUS" to 0x56,
            "KEYPAD_PLUS" to 0x57,
            "KEYPAD_ENTER" to 0x58,
        )

        private val CONSUMER_USAGES = mapOf(
            "PLAY" to 0x00b0,
            "PAUSE" to 0x00b1,
            "RECORD" to 0x00b2,
            "NEXT_TRACK" to 0x00b5,
            "PREVIOUS_TRACK" to 0x00b6,
            "STOP" to 0x00b7,
            "PLAY_PAUSE" to 0x00cd,
            "MUTE" to 0x00e2,
            "VOLUME_UP" to 0x00e9,
            "VOLUME_DOWN" to 0x00ea,
        )

        val REPORT_DESCRIPTOR: ByteArray = intArrayOf(
            // Report 1: boot-style keyboard (modifier, reserved, six keys).
            0x05, 0x01, 0x09, 0x06, 0xa1, 0x01, 0x85, 0x01,
            0x05, 0x07, 0x19, 0xe0, 0x29, 0xe7, 0x15, 0x00,
            0x25, 0x01, 0x75, 0x01, 0x95, 0x08, 0x81, 0x02,
            0x95, 0x01, 0x75, 0x08, 0x81, 0x01,
            0x95, 0x05, 0x75, 0x01, 0x05, 0x08, 0x19, 0x01,
            0x29, 0x05, 0x91, 0x02, 0x95, 0x01, 0x75, 0x03, 0x91, 0x01,
            0x95, 0x06, 0x75, 0x08, 0x15, 0x00, 0x25, 0x65,
            0x05, 0x07, 0x19, 0x00, 0x29, 0x65, 0x81, 0x00, 0xc0,
            // Report 2: one 16-bit consumer-control usage.
            0x05, 0x0c, 0x09, 0x01, 0xa1, 0x01, 0x85, 0x02,
            0x15, 0x00, 0x26, 0xff, 0x03, 0x19, 0x00, 0x2a, 0xff, 0x03,
            0x75, 0x10, 0x95, 0x01, 0x81, 0x00, 0xc0,
            // Report 3: mouse buttons, X/Y and wheel.
            0x05, 0x01, 0x09, 0x02, 0xa1, 0x01, 0x85, 0x03,
            0x09, 0x01, 0xa1, 0x00, 0x05, 0x09, 0x19, 0x01, 0x29, 0x03,
            0x15, 0x00, 0x25, 0x01, 0x95, 0x03, 0x75, 0x01, 0x81, 0x02,
            0x95, 0x01, 0x75, 0x05, 0x81, 0x01,
            0x05, 0x01, 0x09, 0x30, 0x09, 0x31, 0x09, 0x38,
            0x15, 0x81, 0x25, 0x7f, 0x75, 0x08, 0x95, 0x03, 0x81, 0x06,
            0xc0, 0xc0,
        ).map { it.toByte() }.toByteArray()
    }
}
