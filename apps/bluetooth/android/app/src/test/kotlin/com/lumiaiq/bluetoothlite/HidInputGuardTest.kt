package com.lumiaiq.bluetoothlite

import org.junit.Assert.*
import org.junit.Test

class HidInputGuardTest {
    @Test fun missingOrStaleDartHostNeverReceivesPermit() {
        val gate = HidInputGuard()
        gate.resume()
        assertNull(gate.capture(null, "A"))
        assertNull(gate.capture("", "A"))
        assertNull(gate.capture("A", "B"))
        assertNull(gate.capture("A", null))
        assertNotNull(gate.capture("A", "A"))
    }
    @Test fun pressAndDelayedReleaseRemainBoundToTheCapturedHost() {
        val gate = HidInputGuard()
        gate.resume()
        val permit = gate.capture("A", "A")!!
        assertTrue(gate.accepts(permit, "A"))
        assertFalse(gate.accepts(permit, "B"))
        assertFalse(gate.accepts(permit, null))
    }
    @Test fun pauseRejectsInputAndResumeDoesNotReviveQueuedKeys() {
        val gate = HidInputGuard()
        assertNull(gate.capture("A", "A"))
        gate.resume()
        val permit = gate.capture("A", "A")!!
        gate.pause()
        assertFalse(gate.accepts(permit, "A"))
        assertNull(gate.capture("A", "A"))
        gate.resume()
        assertFalse(gate.accepts(permit, "A"))
        assertTrue(gate.accepts(gate.capture("A", "A")!!, "A"))
    }
    @Test fun navigationInvalidatesOldPressAndReleaseEvenOnSameHost() {
        val gate = HidInputGuard()
        gate.resume()
        val permit = gate.capture("A", "A")!!
        gate.invalidate()
        assertFalse(gate.accepts(permit, "A"))
        assertNotNull(gate.capture("A", "A"))
    }
    @Test fun launchProfileTransitionCanCancelEpochOnlyAfterTheReleaseWasSent() {
        val gate = HidInputGuard()
        gate.resume()
        val permit = gate.capture("A", "A")!!
        val order = mutableListOf<String>()
        val completion = HidStepCompletion { success ->
            assertTrue(success)
            order.add("profile-change")
            gate.invalidate() // Same releaseInput sent by a linked-profile change.
        }
        order.add("press")
        assertTrue(completion.completeAfterRelease {
            assertTrue(gate.accepts(permit, "A"))
            order.add("release")
            true
        })
        assertEquals(listOf("press", "release", "profile-change"), order)
        assertFalse(gate.accepts(permit, "A"))
        completion.finish(false) // Later epoch cancellation cannot reply twice.
        assertEquals(3, order.size)
    }
    @Test fun queuedCancellationRepliesFailureOnceAndCannotReleaseOrSucceedLater() {
        val replies = mutableListOf<Boolean>()
        val completion = HidStepCompletion { replies.add(it) }
        assertTrue(replies.isEmpty()) // Queue insertion does not acknowledge.
        completion.finish(false)
        assertFalse(completion.completeAfterRelease { error("Cancelled key must never release on another host") })
        completion.finish(true)
        assertEquals(listOf(false), replies)
    }
    @Test fun rejectedReleaseNeverAcknowledgesSuccess() {
        val replies = mutableListOf<Boolean>()
        val completion = HidStepCompletion { replies.add(it) }
        assertFalse(completion.completeAfterRelease { false })
        assertEquals(listOf(false), replies)
    }
    @Test fun proxyDisconnectAndSameAddressReconnectCannotRevivePendingInput() {
        val gate = HidInputGuard()
        gate.resume()
        val old = gate.capture("A", "A")!!
        gate.invalidate() // Service disconnect cancels queue before dropping proxy.
        assertFalse(gate.accepts(old, null))
        assertFalse(gate.accepts(old, "A"))
        assertTrue(gate.accepts(gate.capture("A", "A")!!, "A"))
    }
}
