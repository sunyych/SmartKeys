package com.lumiaiq.bluetoothlite

/** A queued HID action belongs to one resumed input epoch and one exact host. */
data class HidInputPermit(val address: String, val epoch: Long)

class HidInputGuard {
    private var epoch = 0L
    private var resumed = false
    fun resume() { epoch++; resumed = true }
    fun pause() { resumed = false; epoch++ }
    fun invalidate() { epoch++ }
    fun capture(expectedAddress: String?, currentAddress: String?): HidInputPermit? =
        if (resumed && !expectedAddress.isNullOrBlank() && expectedAddress == currentAddress)
            HidInputPermit(expectedAddress, epoch) else null
    fun accepts(permit: HidInputPermit, currentAddress: String?): Boolean =
        resumed && permit.epoch == epoch && permit.address == currentAddress
}

/** A native acknowledgement follows release, never queue insertion. */
class HidStepCompletion(private val reply: (Boolean) -> Unit) {
    private var completed = false
    fun finish(success: Boolean) {
        if (completed) return
        completed = true
        reply(success)
    }
    fun completeAfterRelease(sendRelease: () -> Boolean): Boolean {
        if (completed) return false
        val accepted = sendRelease()
        finish(accepted)
        return accepted
    }
}
