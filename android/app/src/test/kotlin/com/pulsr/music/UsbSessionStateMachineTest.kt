package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Every edge and invariant of [UsbSessionStateMachine], plus the two long
 * simulations the production plugin relies on: 1,000 start/stop cycles and 500
 * unplug/replug cycles, each with a per-cycle recovery budget.
 */
class UsbSessionStateMachineTest {

    // ---------------------------------------------------------------- helpers

    private fun idle() = UsbSessionStateMachine()

    private fun streaming(startAt: Long = 1_000L): UsbSessionStateMachine = idle().also { sm ->
        sm.onPermissionRequested(startAt)
        sm.onPermissionGranted(startAt + 10)
        sm.onOpenSucceeded(startAt + 20)
        sm.onClaimSucceeded(startAt + 30)
        sm.onConfigureSucceeded(startAt + 40)
        sm.onStreamStarted(startAt + 50)
    }

    private fun machineIn(target: UsbSessionState): UsbSessionStateMachine = when (target) {
        UsbSessionState.IDLE -> idle()
        UsbSessionState.PERMISSION -> idle().also { it.onPermissionRequested(0) }
        UsbSessionState.OPENING -> idle().also {
            it.onPermissionRequested(0)
            it.onPermissionGranted(1)
        }

        UsbSessionState.CLAIMING -> idle().also {
            it.onPermissionRequested(0)
            it.onPermissionGranted(1)
            it.onOpenSucceeded(2)
        }

        UsbSessionState.CONFIGURING -> idle().also {
            it.onPermissionRequested(0)
            it.onPermissionGranted(1)
            it.onOpenSucceeded(2)
            it.onClaimSucceeded(3)
        }

        UsbSessionState.STREAMING -> streaming()
        UsbSessionState.DRAINING -> streaming().also { it.onStopRequested(2_000) }
        UsbSessionState.ABANDONED -> streaming().also {
            it.onStopRequested(2_000)
            it.onDrainFailed(2_100)
            it.onAbandon(2_200)
        }

        UsbSessionState.ERROR -> idle().also {
            it.onPermissionRequested(0)
            it.onPermissionDenied(1)
        }
    }

    private inline fun expectIllegalState(label: String, block: () -> Unit): IllegalStateException {
        try {
            block()
        } catch (e: IllegalStateException) {
            return e
        } catch (e: Throwable) {
            throw AssertionError(
                "$label: expected IllegalStateException, got ${e::class.java.name}: ${e.message}", e
            )
        }
        throw AssertionError("$label: expected IllegalStateException, nothing was thrown")
    }

    private fun assertRejected(sm: UsbSessionStateMachine, block: (UsbSessionStateMachine) -> Unit) {
        val beforeState = sm.state
        val beforeTransitions = sm.transitionCount
        val beforeStartStop = sm.startStopCount
        val beforeUnplug = sm.unplugCount
        val beforeUrbs = sm.outstandingUrbCount
        expectIllegalState("rejected event in $beforeState") { block(sm) }
        assertEquals("state must not change after a rejected event", beforeState, sm.state)
        assertEquals("transitionCount must not change", beforeTransitions, sm.transitionCount)
        assertEquals("startStopCount must not change", beforeStartStop, sm.startStopCount)
        assertEquals("unplugCount must not change", beforeUnplug, sm.unplugCount)
        assertEquals("outstandingUrbCount must not change", beforeUrbs, sm.outstandingUrbCount)
    }

    // ------------------------------------------------------------ fresh state

    @Test
    fun freshMachineIsIdleWithCleanCounters() {
        val sm = UsbSessionStateMachine(1_000L)
        assertEquals(UsbSessionState.IDLE, sm.state)
        assertEquals(UsbSessionState.IDLE, sm.previousState)
        assertEquals(0, sm.transitionCount)
        assertNull(sm.lastErrorCode)
        assertFalse(sm.drainPending)
        assertEquals(0, sm.outstandingUrbCount)
        assertEquals(0, sm.recoveryCount)
        assertEquals(0, sm.unplugCount)
        assertEquals(0, sm.startStopCount)
        assertEquals(0L, sm.elapsedInStateMs(1_000L))
        assertEquals(750L, sm.elapsedInStateMs(1_750L))
        // A clock that jumps backwards must not report negative time.
        assertEquals(0L, sm.elapsedInStateMs(10L))
    }

    // -------------------------------------------------------------- open path

    @Test
    fun happyPathWalksEveryStateInOrder() {
        val sm = idle()

        assertTrue(sm.onPermissionRequested(1_000))
        assertEquals(UsbSessionState.PERMISSION, sm.state)
        assertEquals(UsbSessionState.IDLE, sm.previousState)
        assertEquals(1, sm.transitionCount)

        assertTrue(sm.onPermissionGranted(1_050))
        assertEquals(UsbSessionState.OPENING, sm.state)
        assertEquals(2, sm.transitionCount)

        assertTrue(sm.onOpenSucceeded(1_100))
        assertEquals(UsbSessionState.CLAIMING, sm.state)
        assertEquals(3, sm.transitionCount)

        assertTrue(sm.onClaimSucceeded(1_140))
        assertEquals(UsbSessionState.CONFIGURING, sm.state)
        assertEquals(4, sm.transitionCount)

        assertTrue(sm.onConfigureSucceeded(1_200))
        assertEquals("configuration alone must not start the stream", UsbSessionState.CONFIGURING, sm.state)
        assertEquals("flag-only feedback is not a transition", 4, sm.transitionCount)
        assertEquals(1_200L - 1_140L, sm.elapsedInStateMs(1_200))

        assertTrue(sm.onStreamStarted(1_230))
        assertEquals(UsbSessionState.STREAMING, sm.state)
        assertEquals(5, sm.transitionCount)
        assertEquals(1, sm.startStopCount)
        assertEquals(UsbSessionStateMachine.URBS_PER_STREAM, sm.outstandingUrbCount)
        assertFalse(sm.drainPending)
        assertEquals(0, sm.recoveryCount)

        assertTrue(sm.onStopRequested(5_000))
        assertEquals(UsbSessionState.DRAINING, sm.state)
        assertEquals(UsbSessionState.STREAMING, sm.previousState)
        assertTrue("a stop always owes a drain", sm.drainPending)
        assertEquals(2, sm.startStopCount)
        assertEquals(UsbSessionStateMachine.URBS_PER_STREAM, sm.outstandingUrbCount)

        assertTrue(sm.onDrainSucceeded(5_200))
        assertEquals(UsbSessionState.IDLE, sm.state)
        assertFalse(sm.drainPending)
        assertEquals(0, sm.outstandingUrbCount)
        assertEquals(7, sm.transitionCount)
    }

    @Test
    fun streamingRequiresAConfiguredEndpoint() {
        val sm = machineIn(UsbSessionState.CONFIGURING)
        val error = expectIllegalState("start before configure") { sm.onStreamStarted(10) }
        assertTrue("message must name the missing step", error.message!!.contains("CONFIGURING"))
        assertEquals(UsbSessionState.CONFIGURING, sm.state)
        assertEquals(0, sm.startStopCount)

        assertTrue(sm.onConfigureSucceeded(11))
        assertFalse("a second configure callback is a no-op", sm.onConfigureSucceeded(12))
        assertTrue(sm.onStreamStarted(13))
        assertEquals(UsbSessionState.STREAMING, sm.state)
    }

    @Test
    fun permissionRequestIsOnlyAllowedFromIdleErrorOrAbandoned() {
        // IDLE
        assertTrue(idle().onPermissionRequested(0))

        // ERROR (permission denied)
        val errored = machineIn(UsbSessionState.ERROR)
        assertEquals(UsbSessionState.ERROR, errored.state)
        assertTrue(errored.onPermissionRequested(10))
        assertEquals(UsbSessionState.PERMISSION, errored.state)

        // ABANDONED
        val abandoned = machineIn(UsbSessionState.ABANDONED)
        assertTrue(abandoned.onPermissionRequested(20))
        assertEquals(UsbSessionState.PERMISSION, abandoned.state)

        for (state in listOf(
            UsbSessionState.PERMISSION,
            UsbSessionState.OPENING,
            UsbSessionState.CLAIMING,
            UsbSessionState.CONFIGURING,
            UsbSessionState.STREAMING,
            UsbSessionState.DRAINING,
        )) {
            val sm = machineIn(state)
            val error = expectIllegalState("permission request in $state") { sm.onPermissionRequested(99_000) }
            assertTrue(error.message!!.contains("onPermissionRequested"))
            assertTrue("message must name the state: ${error.message}", error.message!!.contains(state.name))
            assertEquals(state, sm.state)
        }
    }

    @Test
    fun abandonedSessionAllowsAFreshOpeningWithoutASecondPrompt() {
        val sm = machineIn(UsbSessionState.ABANDONED)
        assertTrue(sm.onPermissionGranted(3_000))
        assertEquals(UsbSessionState.OPENING, sm.state)
        assertEquals(UsbSessionState.ABANDONED, sm.previousState)
        assertTrue(sm.onOpenSucceeded(3_100))
        assertEquals(UsbSessionState.CLAIMING, sm.state)
    }

    @Test
    fun permissionDeniedEndsInErrorWithAPreciseCode() {
        val sm = machineIn(UsbSessionState.PERMISSION)
        assertEquals(1, sm.transitionCount)
        assertTrue(sm.onPermissionDenied(50))
        assertEquals(UsbSessionState.ERROR, sm.state)
        assertEquals(UsbSessionStateMachine.ERR_PERMISSION_DENIED, sm.lastErrorCode)
        assertFalse(sm.drainPending)
        assertEquals(0, sm.outstandingUrbCount)
        assertEquals(0, sm.recoveryCount)
    }

    // ---------------------------------------------------------------- draining

    @Test
    fun drainingIsReachableOnlyFromStreamingOrError() {
        for (state in listOf(
            UsbSessionState.IDLE,
            UsbSessionState.PERMISSION,
            UsbSessionState.OPENING,
            UsbSessionState.CLAIMING,
            UsbSessionState.CONFIGURING,
        )) {
            val sm = machineIn(state)
            val error = expectIllegalState("stop from $state") { sm.onStopRequested(9_000) }
            assertTrue(error.message!!.contains("onStopRequested"))
            assertEquals(state, sm.state)
        }

        assertTrue(streaming().onStopRequested(2_000))
        val errored = streaming().also { it.onError("io_failure", 2_500) }
        assertTrue(errored.drainPending)
        assertTrue(errored.onStopRequested(2_600))
        assertEquals(UsbSessionState.DRAINING, errored.state)
    }

    @Test
    fun drainSuccessReturnsToIdleAndReleasesUrbs() {
        val sm = machineIn(UsbSessionState.DRAINING)
        assertEquals(UsbSessionStateMachine.URBS_PER_STREAM, sm.outstandingUrbCount)
        assertTrue(sm.onDrainSucceeded(3_000))
        assertEquals(UsbSessionState.IDLE, sm.state)
        assertFalse(sm.drainPending)
        assertEquals(0, sm.outstandingUrbCount)
    }

    @Test
    fun drainFailureKeepsDrainingWithPendingFlagAndError() {
        val sm = machineIn(UsbSessionState.DRAINING)
        val transitionsBefore = sm.transitionCount

        assertTrue(sm.onDrainFailed(3_000))
        assertEquals(UsbSessionState.DRAINING, sm.state)
        assertTrue(sm.drainPending)
        assertEquals(UsbSessionStateMachine.ERR_DRAIN_INCOMPLETE, sm.lastErrorCode)
        assertEquals(UsbSessionStateMachine.URBS_PER_STREAM, sm.outstandingUrbCount)
        assertEquals("a failed drain is feedback, not a transition", transitionsBefore, sm.transitionCount)

        // The caller may retry the drain afterwards.
        assertTrue(sm.onDrainSucceeded(3_500))
        assertEquals(UsbSessionState.IDLE, sm.state)
        assertEquals(0, sm.outstandingUrbCount)
    }

    @Test
    fun abandonRequiresAPendingDrainAndClearsIt() {
        val streaming = streaming()
        val fromStreaming = expectIllegalState("abandon while streaming") { streaming.onAbandon(3_000) }
        assertTrue(fromStreaming.message!!.contains("onAbandon"))
        assertEquals(UsbSessionState.STREAMING, streaming.state)

        val drained = machineIn(UsbSessionState.DRAINING).also { it.onDrainSucceeded(3_100) }
        assertEquals(UsbSessionState.IDLE, drained.state)
        expectIllegalState("abandon from idle") { drained.onAbandon(3_200) }

        val failing = machineIn(UsbSessionState.DRAINING)
        assertTrue(failing.onDrainFailed(3_300))
        assertTrue(failing.onAbandon(3_400))
        assertEquals(UsbSessionState.ABANDONED, failing.state)
        assertEquals(UsbSessionState.DRAINING, failing.previousState)
        assertFalse("abandon clears the pending drain", failing.drainPending)
        assertEquals("abandon releases every URB", 0, failing.outstandingUrbCount)
    }

    @Test
    fun rebindIsRefusedWhileADrainIsPending() {
        val sm = streaming()
        assertTrue(sm.onError("transport_stalled", 3_000))
        assertEquals(UsbSessionState.ERROR, sm.state)
        assertTrue("an error mid-stream still owes a drain", sm.drainPending)
        assertEquals(UsbSessionStateMachine.URBS_PER_STREAM, sm.outstandingUrbCount)

        val error = expectIllegalState("rebind with live URBs") { sm.onPermissionRequested(3_100) }
        assertTrue("message must explain the URB hazard: ${error.message}", error.message!!.contains("drainPending"))
        assertTrue(error.message!!.contains("URB"))
        assertEquals(UsbSessionState.ERROR, sm.state)

        assertTrue(sm.onStopRequested(3_200))
        assertEquals(UsbSessionState.DRAINING, sm.state)
        assertTrue(sm.onDrainSucceeded(3_400))
        assertEquals(UsbSessionState.IDLE, sm.state)
        assertTrue(sm.onPermissionRequested(3_500))
    }

    @Test
    fun errorFromPreStreamStatesDoesNotMarkADrainPending() {
        for (state in listOf(
            UsbSessionState.PERMISSION,
            UsbSessionState.OPENING,
            UsbSessionState.CLAIMING,
            UsbSessionState.CONFIGURING,
        )) {
            val sm = machineIn(state)
            assertTrue(sm.onError("open_failed", 1_000))
            assertEquals(UsbSessionState.ERROR, sm.state)
            assertFalse("no stream existed in $state", sm.drainPending)
            assertEquals(0, sm.outstandingUrbCount)
            assertEquals("open_failed", sm.lastErrorCode)
            assertTrue("a clean error may be retried immediately", sm.onPermissionRequested(1_100))
        }
    }

    @Test
    fun errorIsRefusedWhereItCannotDescribeAnything() {
        assertRejected(idle()) { it.onError("nothing_to_fail", 1) }
        assertRejected(machineIn(UsbSessionState.ABANDONED)) { it.onError("terminal", 1) }
        assertRejected(machineIn(UsbSessionState.DRAINING)) { it.onError("use_drain_failed", 1) }
        try {
            streaming().onError("   ", 1)
            throw AssertionError("a blank error code must be rejected")
        } catch (_: IllegalArgumentException) {
            // expected
        }
    }

    @Test
    fun reErrorOnlyUpdatesTheCodeWithoutDoubleCounting() {
        val sm = streaming().also { it.onError("first", 2_000) }
        val transitions = sm.transitionCount
        assertFalse("same code is a no-op", sm.onError("first", 2_100))
        assertEquals(transitions, sm.transitionCount)
        assertTrue("a different code is recorded", sm.onError("second", 2_200))
        assertEquals("second", sm.lastErrorCode)
        assertEquals(transitions, sm.transitionCount)
        assertEquals(UsbSessionState.ERROR, sm.state)
    }

    // ----------------------------------------------------------------- detach

    @Test
    fun detachFromStreamingAlwaysDrainsAndNeverReturnsToIdle() {
        val sm = streaming()
        val transitionsBefore = sm.transitionCount

        assertTrue(sm.onDetached(4_000))
        assertEquals(UsbSessionState.DRAINING, sm.state)
        assertEquals("STREAMING may never short-circuit to IDLE", UsbSessionState.STREAMING, sm.previousState)
        assertTrue(sm.drainPending)
        assertEquals(UsbSessionStateMachine.URBS_PER_STREAM, sm.outstandingUrbCount)
        assertEquals(1, sm.unplugCount)
        assertEquals(transitionsBefore + 1, sm.transitionCount)

        // Only the drain decides when the endpoint is really free.
        assertTrue(sm.onDrainSucceeded(4_100))
        assertEquals(UsbSessionState.IDLE, sm.state)
        assertEquals(0, sm.outstandingUrbCount)
    }

    @Test
    fun detachWhileDrainingKeepsThePendingDrain() {
        val sm = machineIn(UsbSessionState.DRAINING)
        assertTrue(sm.onDetached(5_000))
        assertEquals(UsbSessionState.DRAINING, sm.state)
        assertTrue(sm.drainPending)
        assertEquals(1, sm.unplugCount)
    }

    @Test
    fun detachFromHandshakeFailsWithDeviceDetached() {
        for (state in listOf(
            UsbSessionState.OPENING,
            UsbSessionState.CLAIMING,
            UsbSessionState.CONFIGURING,
        )) {
            val sm = machineIn(state)
            assertTrue(sm.onDetached(6_000))
            assertEquals("detach during $state must fail", UsbSessionState.ERROR, sm.state)
            assertEquals(UsbSessionStateMachine.ERR_DEVICE_DETACHED, sm.lastErrorCode)
            assertEquals(1, sm.unplugCount)
            assertFalse(sm.drainPending)
        }
    }

    @Test
    fun detachWhilePromptingReturnsToIdleWithoutAFakeError() {
        val sm = machineIn(UsbSessionState.PERMISSION)
        assertTrue(sm.onDetached(7_000))
        assertEquals(UsbSessionState.IDLE, sm.state)
        assertNull(sm.lastErrorCode)
        assertEquals(1, sm.unplugCount)
        assertEquals(2, sm.transitionCount)
    }

    @Test
    fun detachWhileIdleOrAbandonedIsIgnored() {
        val idle = idle()
        assertFalse(idle.onDetached(1))
        assertEquals(UsbSessionState.IDLE, idle.state)
        assertEquals(0, idle.unplugCount)
        assertEquals(0, idle.transitionCount)

        val abandoned = machineIn(UsbSessionState.ABANDONED)
        assertFalse(abandoned.onDetached(2))
        assertEquals(UsbSessionState.ABANDONED, abandoned.state)
        assertEquals(0, abandoned.unplugCount)
    }

    @Test
    fun recoveryIsCountedOnlyWhenAudioComesBack() {
        val sm = streaming()
        assertEquals(0, sm.recoveryCount)

        assertTrue(sm.onDetached(8_000))
        assertTrue(sm.onDrainSucceeded(8_100))
        assertEquals(UsbSessionState.IDLE, sm.state)
        assertEquals("a teardown alone is not a recovery", 0, sm.recoveryCount)

        sm.onPermissionRequested(8_200)
        sm.onPermissionGranted(8_260)
        sm.onOpenSucceeded(8_380)
        sm.onClaimSucceeded(8_420)
        sm.onConfigureSucceeded(8_480)
        assertEquals(0, sm.recoveryCount)

        sm.onStreamStarted(8_510)
        assertEquals(1, sm.recoveryCount)
        assertEquals(UsbSessionState.STREAMING, sm.state)
    }

    // ------------------------------------------------------------------ reset

    @Test
    fun resetRestoresTheInitialStateFromEveryState() {
        for (state in UsbSessionState.values()) {
            val sm = machineIn(state)
            sm.reset(50_000)

            assertEquals("reset from $state", UsbSessionState.IDLE, sm.state)
            assertEquals(UsbSessionState.IDLE, sm.previousState)
            assertEquals(0, sm.transitionCount)
            assertNull(sm.lastErrorCode)
            assertFalse(sm.drainPending)
            assertEquals(0, sm.outstandingUrbCount)
            assertEquals(0, sm.recoveryCount)
            assertEquals(0, sm.unplugCount)
            assertEquals(0, sm.startStopCount)
            assertEquals(0L, sm.elapsedInStateMs(50_000))

            // A reset machine behaves exactly like a fresh one.
            assertTrue(sm.onPermissionRequested(50_100))
            assertEquals(UsbSessionState.PERMISSION, sm.state)
        }
    }

    // -------------------------------------------------------- illegal events

    @Test
    fun eventsAreRejectedInStatesWhereTheyCannotApply() {
        assertRejected(idle()) { it.onPermissionGranted(1) }
        assertRejected(idle()) { it.onOpenSucceeded(1) }
        assertRejected(idle()) { it.onClaimSucceeded(1) }
        assertRejected(idle()) { it.onConfigureSucceeded(1) }
        assertRejected(idle()) { it.onStreamStarted(1) }
        assertRejected(idle()) { it.onStopRequested(1) }
        assertRejected(idle()) { it.onDrainSucceeded(1) }
        assertRejected(idle()) { it.onDrainFailed(1) }
        assertRejected(idle()) { it.onAbandon(1) }
        assertRejected(idle()) { it.onPermissionDenied(1) }

        assertRejected(machineIn(UsbSessionState.PERMISSION)) { it.onOpenSucceeded(1) }
        assertRejected(machineIn(UsbSessionState.OPENING)) { it.onClaimSucceeded(1) }
        assertRejected(machineIn(UsbSessionState.CLAIMING)) { it.onConfigureSucceeded(1) }
        assertRejected(machineIn(UsbSessionState.STREAMING)) { it.onDrainSucceeded(1) }
        assertRejected(machineIn(UsbSessionState.DRAINING)) { it.onConfigureSucceeded(1) }
        assertRejected(machineIn(UsbSessionState.ABANDONED)) { it.onDrainSucceeded(1) }
    }

    @Test
    fun illegalTransitionMessagesNameTheActionAndTheState() {
        val sm = machineIn(UsbSessionState.STREAMING)
        val error = expectIllegalState("claim after streaming") { sm.onClaimSucceeded(1) }
        val message = error.message!!
        assertTrue("must name the action: $message", message.contains("onClaimSucceeded"))
        assertTrue("must name the state: $message", message.contains("STREAMING"))
        assertEquals(UsbSessionState.STREAMING, sm.state)
    }

    // ------------------------------------------------------------- simulations

    @Test
    fun thousandStartStopCyclesStayLegalAndWithinBudget() {
        val sm = idle()
        var totalRecovery = 0L
        var firstRecovery = -1L

        repeat(1_000) { cycle ->
            val recovery = sm.simulateStartStop(1)
            assertTrue("cycle $cycle produced no recovery time", recovery > 0)
            assertTrue(
                "cycle $cycle recovery $recovery ms exceeded ${UsbSessionStateMachine.MAX_RECOVERY_MS} ms",
                recovery <= UsbSessionStateMachine.MAX_RECOVERY_MS,
            )
            if (firstRecovery < 0) firstRecovery = recovery else assertEquals(firstRecovery, recovery)
            totalRecovery += recovery

            assertEquals("cycle $cycle must end idle", UsbSessionState.IDLE, sm.state)
            assertFalse(sm.drainPending)
            assertEquals(0, sm.outstandingUrbCount)
            assertNull("a clean cycle must not record an error", sm.lastErrorCode)
            assertTrue("drainPending implies live URBs", !sm.drainPending || sm.outstandingUrbCount > 0)
        }

        assertEquals(2_000, sm.startStopCount)
        assertEquals("7 transitions per cycle", 7_000, sm.transitionCount)
        assertEquals("clean stops are not recoveries", 0, sm.recoveryCount)
        assertEquals(0, sm.unplugCount)
        assertEquals(firstRecovery * 1_000, totalRecovery)
    }

    @Test
    fun thousandStartStopCyclesInOneCall() {
        val sm = idle()
        val total = sm.simulateStartStop(1_000)
        assertTrue(total > 0)
        assertTrue(total <= 1_000L * UsbSessionStateMachine.MAX_RECOVERY_MS)
        assertEquals(1_000, sm.startStopCount / 2)
        assertEquals(2_000, sm.startStopCount)
        assertEquals(7_000, sm.transitionCount)
        assertEquals(UsbSessionState.IDLE, sm.state)
    }

    @Test
    fun fiveHundredUnplugReplugCyclesRecoverEveryTime() {
        val sm = idle()
        var totalRecovery = 0L
        var firstRecovery = -1L

        repeat(500) { cycle ->
            val recovery = sm.simulateUnplugReplug(1)
            assertTrue("cycle $cycle recovered instantly", recovery > 0)
            assertTrue(
                "cycle $cycle recovery $recovery ms exceeded ${UsbSessionStateMachine.MAX_RECOVERY_MS} ms",
                recovery <= UsbSessionStateMachine.MAX_RECOVERY_MS,
            )
            if (firstRecovery < 0) firstRecovery = recovery else assertEquals(firstRecovery, recovery)
            totalRecovery += recovery

            assertEquals("cycle $cycle must be streaming again", UsbSessionState.STREAMING, sm.state)
            assertFalse(sm.drainPending)
            assertEquals(UsbSessionStateMachine.URBS_PER_STREAM, sm.outstandingUrbCount)
            assertNull("an unplug is not an error code", sm.lastErrorCode)
        }

        assertEquals(500, sm.unplugCount)
        assertEquals(500, sm.recoveryCount)
        // One bootstrap start plus one restart per replug.
        assertEquals(501, sm.startStopCount)
        // 5 transitions to bootstrap + 7 per detach/replug cycle.
        assertEquals(5 + 500 * 7, sm.transitionCount)
        assertEquals(firstRecovery * 500, totalRecovery)
    }

    @Test
    fun fiveHundredUnplugReplugCyclesInOneCall() {
        val sm = idle()
        val total = sm.simulateUnplugReplug(500)
        assertTrue(total > 0)
        assertTrue(total <= 500L * UsbSessionStateMachine.MAX_RECOVERY_MS)
        assertEquals(500, sm.unplugCount)
        assertEquals(500, sm.recoveryCount)
        assertEquals(UsbSessionState.STREAMING, sm.state)
        assertEquals(5 + 500 * 7, sm.transitionCount)
    }

    @Test
    fun simulatorsRejectNonsenseArguments() {
        try {
            idle().simulateStartStop(-1)
            throw AssertionError("negative iterations must be rejected")
        } catch (_: IllegalArgumentException) {
            // expected
        }
        try {
            idle().simulateUnplugReplug(-1)
            throw AssertionError("negative iterations must be rejected")
        } catch (_: IllegalArgumentException) {
            // expected
        }

        // Start/stop must begin from IDLE.
        expectIllegalState("start/stop from STREAMING") { streaming().simulateStartStop(1) }
        // Unplug/replug must begin from IDLE or STREAMING.
        expectIllegalState("unplug/replug from PERMISSION") { machineIn(UsbSessionState.PERMISSION).simulateUnplugReplug(1) }
        expectIllegalState("unplug/replug from ERROR") { machineIn(UsbSessionState.ERROR).simulateUnplugReplug(1) }

        // Zero iterations is legal and changes nothing.
        val sm = idle()
        assertEquals(0L, sm.simulateStartStop(0))
        assertEquals(0, sm.transitionCount)
        assertEquals(0L, sm.simulateUnplugReplug(0))
    }

    @Test
    fun simulationsResumeFromTheVirtualClockInsteadOfRestartingIt() {
        val sm = idle()
        val first = sm.simulateStartStop(1)
        val second = sm.simulateStartStop(1)
        assertEquals("repeated cycles are deterministic", first, second)
        assertEquals("one teardown per cycle", UsbSessionStateMachine.DRAIN_MS, first)
    }
}
