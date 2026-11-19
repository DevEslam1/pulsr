package com.pulsr.music

/**
 * States of one USB Audio Class exclusive session.
 *
 * The order below is the normal open path; [DRAINING], [ABANDONED] and [ERROR]
 * are the teardown and fault states. A session never skips a step: the clock
 * and the alt setting are only programmable after the interface is claimed
 * ([CLAIMING]) and streams only after the configuration step succeeded
 * ([CONFIGURING]).
 */
enum class UsbSessionState {
    IDLE,
    PERMISSION,
    OPENING,
    CLAIMING,
    CONFIGURING,
    STREAMING,
    DRAINING,
    ABANDONED,
    ERROR,
}

/**
 * Lifecycle state machine for a single USB Audio Class exclusive session.
 *
 * The machine owns no Android objects and no I/O: every method takes the
 * caller's monotonic clock in milliseconds so the whole lifecycle is
 * replayable in a plain JVM unit test. The plugin drives it from its single USB
 * worker thread, so the class is deliberately **not** thread-safe; call it from
 * one thread.
 *
 * Contracts enforced here (each violation throws [IllegalStateException] with
 * the offending action, the current state and the reason):
 *
 *  * A new session may only be started from [UsbSessionState.IDLE],
 *    [UsbSessionState.ERROR] or [UsbSessionState.ABANDONED].
 *  * [UsbSessionState.ABANDONED] also permits a fresh OPENING (the forced
 *    teardown already ran, and the OS permission is still held), so
 *    `onPermissionGranted` from ABANDONED goes straight to OPENING.
 *  * [UsbSessionState.STREAMING] is only reachable after
 *    [onConfigureSucceeded]; `onStreamStarted` without it throws.
 *  * [UsbSessionState.DRAINING] is only reachable from
 *    [UsbSessionState.STREAMING] or [UsbSessionState.ERROR]. Drain success
 *    returns to IDLE; drain failure keeps DRAINING with `drainPending = true`.
 *  * [UsbSessionState.ABANDONED] is only allowed while `drainPending` is true,
 *    and clears both `drainPending` and `outstandingUrbCount`.
 *  * Opening/claiming is refused while `drainPending`: a rebind with
 *    outstanding isochronous URBs is exactly the bug this machine exists to
 *    prevent.
 *  * A detach while STREAMING always lands in DRAINING, never IDLE.
 *
 * `drainPending == true` therefore always implies `outstandingUrbCount > 0`,
 * and `state == DRAINING` always implies `drainPending == true`.
 */
class UsbSessionStateMachine(startMs: Long = 0L) {

    /** Current lifecycle state. */
    var state: UsbSessionState = UsbSessionState.IDLE
        private set

    /** State the session was in before the most recent transition. */
    var previousState: UsbSessionState = UsbSessionState.IDLE
        private set

    /** Number of accepted state changes (feedback that only sets flags is not a transition). */
    var transitionCount: Int = 0
        private set

    /** Last error code reported through [onError] (or a built-in teardown code). */
    var lastErrorCode: String? = null
        private set

    /** True while an endpoint drain/teardown is still owed. */
    var drainPending: Boolean = false
        private set

    /** Isochronous URBs the session still owns; non-zero while streaming or draining. */
    var outstandingUrbCount: Int = 0
        private set

    /** Sessions brought back to [UsbSessionState.STREAMING] after a fault or unplug. */
    var recoveryCount: Int = 0
        private set

    /** Detach events observed while a session was live. */
    var unplugCount: Int = 0
        private set

    /** Accepted start/stop transitions: +1 on `onStreamStarted`, +1 on `onStopRequested`. */
    var startStopCount: Int = 0
        private set

    private var lastTransitionMs: Long = startMs
    private var configureSucceeded: Boolean = false
    private var recovering: Boolean = false

    // ---------------------------------------------------------------- queries

    /** Milliseconds spent in [state] as of [nowMs]; clamped at 0 for clock skew. */
    fun elapsedInStateMs(nowMs: Long): Long = (nowMs - lastTransitionMs).coerceAtLeast(0L)

    // ------------------------------------------------------------- open path

    /**
     * Starts a new session by asking for device permission.
     *
     * Allowed from IDLE, ERROR and ABANDONED only, and never while
     * `drainPending` (the previous session still owns URBs).
     */
    fun onPermissionRequested(nowMs: Long): Boolean {
        requireState("onPermissionRequested", UsbSessionState.IDLE, UsbSessionState.ERROR, UsbSessionState.ABANDONED)
        if (drainPending) {
            throw IllegalStateException(
                "onPermissionRequested is not allowed with drainPending=true " +
                    "($outstandingUrbCount outstanding URB(s)); drain the endpoint or call onAbandon first"
            )
        }
        moveTo(UsbSessionState.PERMISSION, nowMs, "onPermissionRequested")
        return true
    }

    /**
     * Permission answered positively -> OPENING.
     *
     * ABANDONED is accepted as well: the forced teardown already released the
     * device, and the permission grant survives it, so a fresh OPENING needs no
     * second dialog.
     */
    fun onPermissionGranted(nowMs: Long): Boolean {
        requireState("onPermissionGranted", UsbSessionState.PERMISSION, UsbSessionState.ABANDONED)
        moveTo(UsbSessionState.OPENING, nowMs, "onPermissionGranted")
        return true
    }

    /** Permission denied by the user -> ERROR (no resources were opened). */
    fun onPermissionDenied(nowMs: Long): Boolean {
        requireState("onPermissionDenied", UsbSessionState.PERMISSION)
        lastErrorCode = ERR_PERMISSION_DENIED
        // A refusal is a normal user decision, not a fault to recover from.
        recovering = false
        moveTo(UsbSessionState.ERROR, nowMs, "onPermissionDenied")
        return true
    }

    /** `UsbDeviceConnection.open()` succeeded -> CLAIMING. */
    fun onOpenSucceeded(nowMs: Long): Boolean {
        requireState("onOpenSucceeded", UsbSessionState.OPENING)
        moveTo(UsbSessionState.CLAIMING, nowMs, "onOpenSucceeded")
        return true
    }

    /** `claimInterface()` succeeded -> CONFIGURING. */
    fun onClaimSucceeded(nowMs: Long): Boolean {
        requireState("onClaimSucceeded", UsbSessionState.CLAIMING)
        moveTo(UsbSessionState.CONFIGURING, nowMs, "onClaimSucceeded")
        return true
    }

    /**
     * Alt setting, clock selector and endpoint format are programmed.
     *
     * The state stays CONFIGURING (there is no separate CONFIGURED state) until
     * [onStreamStarted]. Returns false when configuration was already recorded,
     * which keeps a redundant callback from inflating the transition count.
     */
    fun onConfigureSucceeded(nowMs: Long): Boolean {
        requireState("onConfigureSucceeded", UsbSessionState.CONFIGURING)
        if (configureSucceeded) return false
        configureSucceeded = true
        return true
    }

    /** First isochronous URB submitted -> STREAMING. Requires a successful CONFIGURING step. */
    fun onStreamStarted(nowMs: Long): Boolean {
        requireState("onStreamStarted", UsbSessionState.CONFIGURING)
        if (!configureSucceeded) {
            throw IllegalStateException(
                "onStreamStarted requires a successful CONFIGURING step; " +
                    "call onConfigureSucceeded first (state=CONFIGURING, configureSucceeded=false)"
            )
        }
        moveTo(UsbSessionState.STREAMING, nowMs, "onStreamStarted")
        outstandingUrbCount = URBS_PER_STREAM
        startStopCount++
        if (recovering) {
            recoveryCount++
            recovering = false
        }
        return true
    }

    // --------------------------------------------------------------- teardown

    /**
     * Stop requested -> DRAINING for a streaming session, or a teardown for an
     * errored one. Both leave `drainPending = true` and at least one URB
     * outstanding, because only the drain callback may claim the endpoint is
     * really quiet.
     */
    fun onStopRequested(nowMs: Long): Boolean {
        requireState("onStopRequested", UsbSessionState.STREAMING, UsbSessionState.ERROR)
        if (state == UsbSessionState.STREAMING) {
            startStopCount++
        }
        outstandingUrbCount = maxOf(outstandingUrbCount, URBS_PER_STREAM)
        moveTo(UsbSessionState.DRAINING, nowMs, "onStopRequested")
        drainPending = true
        return true
    }

    /** Drain callback reaped every URB -> IDLE. */
    fun onDrainSucceeded(nowMs: Long): Boolean {
        requireState("onDrainSucceeded", UsbSessionState.DRAINING)
        outstandingUrbCount = 0
        drainPending = false
        moveTo(UsbSessionState.IDLE, nowMs, "onDrainSucceeded")
        return true
    }

    /**
     * The drain did not complete in time. The session stays in DRAINING with
     * `drainPending = true`; the caller may retry, or forced-teardown through
     * [onAbandon]. This is not a transition, so [transitionCount] is unchanged.
     */
    fun onDrainFailed(nowMs: Long): Boolean {
        requireState("onDrainFailed", UsbSessionState.DRAINING)
        drainPending = true
        lastErrorCode = ERR_DRAIN_INCOMPLETE
        recovering = true
        return true
    }

    /**
     * Forced teardown of a session whose drain is still pending. Only valid
     * while `drainPending` is true; releasing the interface with reaped URBs is
     * the whole point of the ABANDONED state.
     */
    fun onAbandon(nowMs: Long): Boolean {
        requireState("onAbandon", UsbSessionState.DRAINING)
        if (!drainPending) {
            throw IllegalStateException(
                "onAbandon requires drainPending=true, but the drain already completed " +
                    "(state=DRAINING, outstandingUrbCount=$outstandingUrbCount); use onDrainSucceeded"
            )
        }
        outstandingUrbCount = 0
        drainPending = false
        recovering = true
        moveTo(UsbSessionState.ABANDONED, nowMs, "onAbandon")
        return true
    }

    // ------------------------------------------------------------------ faults

    /**
     * Fault reported by the USB layer -> ERROR.
     *
     * Allowed from any live state and from ERROR itself (which only updates the
     * code). Refused from IDLE (nothing to fail), from DRAINING (report drain
     * failures through [onDrainFailed]) and from ABANDONED (terminal until
     * [reset] or a new session).
     *
     * A fault raised while STREAMING marks the drain pending: the URBs in
     * flight must still be reaped before anything rebinds.
     */
    fun onError(code: String, nowMs: Long): Boolean {
        require(code.isNotBlank()) { "error code must not be blank" }
        requireState(
            "onError",
            UsbSessionState.PERMISSION,
            UsbSessionState.OPENING,
            UsbSessionState.CLAIMING,
            UsbSessionState.CONFIGURING,
            UsbSessionState.STREAMING,
            UsbSessionState.ERROR,
        )
        val unchanged = state == UsbSessionState.ERROR && lastErrorCode == code
        if (state == UsbSessionState.STREAMING) {
            outstandingUrbCount = maxOf(outstandingUrbCount, URBS_PER_STREAM)
            drainPending = true
        }
        lastErrorCode = code
        recovering = true
        if (state == UsbSessionState.ERROR) return !unchanged
        moveTo(UsbSessionState.ERROR, nowMs, "onError")
        return true
    }

    /**
     * The device disappeared.
     *
     *  * STREAMING -> DRAINING (never IDLE): the stream was cut mid-flight.
     *  * DRAINING stays DRAINING with the pending flag set.
     *  * ERROR stays ERROR, ABANDONED and IDLE are unaffected (returns false).
     *  * PERMISSION returns to IDLE: nothing was opened, so there is no error.
     *  * OPENING/CLAIMING/CONFIGURING fail with [ERR_DEVICE_DETACHED].
     */
    fun onDetached(nowMs: Long): Boolean {
        return when (state) {
            UsbSessionState.STREAMING -> {
                unplugCount++
                outstandingUrbCount = maxOf(outstandingUrbCount, URBS_PER_STREAM)
                moveTo(UsbSessionState.DRAINING, nowMs, "onDetached")
                drainPending = true
                recovering = true
                true
            }

            UsbSessionState.DRAINING -> {
                unplugCount++
                drainPending = true
                recovering = true
                true
            }

            UsbSessionState.ERROR -> {
                unplugCount++
                true
            }

            UsbSessionState.PERMISSION -> {
                unplugCount++
                moveTo(UsbSessionState.IDLE, nowMs, "onDetached")
                true
            }

            UsbSessionState.OPENING, UsbSessionState.CLAIMING, UsbSessionState.CONFIGURING -> {
                unplugCount++
                lastErrorCode = ERR_DEVICE_DETACHED
                recovering = true
                moveTo(UsbSessionState.ERROR, nowMs, "onDetached")
                true
            }

            UsbSessionState.IDLE, UsbSessionState.ABANDONED -> false
        }
    }

    // ------------------------------------------------------------------- reset

    /**
     * Full reset to IDLE with every counter and flag cleared. Never throws:
     * it is the safe "throw the session away" exit (plugin teardown, unit test
     * setup) and must work from any state, including mid-drain.
     */
    fun reset(nowMs: Long) {
        state = UsbSessionState.IDLE
        previousState = UsbSessionState.IDLE
        transitionCount = 0
        lastErrorCode = null
        drainPending = false
        outstandingUrbCount = 0
        recoveryCount = 0
        unplugCount = 0
        startStopCount = 0
        configureSucceeded = false
        recovering = false
        lastTransitionMs = nowMs
    }

    // -------------------------------------------------------------- simulators

    /**
     * Runs [iterations] complete start -> stop cycles on a virtual clock and
     * returns the total simulated recovery time in milliseconds.
     *
     * One cycle is: permission prompt, open, claim, configure, first URB, a
     * short playback dwell, stop, drain to IDLE. "Recovery" is the stop-request
     * to IDLE interval, i.e. how long the endpoint is unusable between tracks.
     * Each cycle is budgeted against [MAX_RECOVERY_MS].
     *
     * The machine must be entered from IDLE and is left in IDLE.
     */
    fun simulateStartStop(iterations: Int): Long {
        require(iterations >= 0) { "iterations must be >= 0, was $iterations" }
        if (state != UsbSessionState.IDLE) {
            throw IllegalStateException("simulateStartStop must be entered from IDLE, current state is $state")
        }
        var now = lastTransitionMs
        var recoveryTotalMs = 0L
        repeat(iterations) { index ->
            now += PERMISSION_PROMPT_MS
            onPermissionRequested(now)
            now += PERMISSION_GRANT_MS
            onPermissionGranted(now)
            now += OPEN_MS
            onOpenSucceeded(now)
            now += CLAIM_MS
            onClaimSucceeded(now)
            now += CONFIGURE_MS
            onConfigureSucceeded(now)
            now += STREAM_START_MS
            onStreamStarted(now)

            now += PLAYBACK_MS
            val stopAt = now
            onStopRequested(now)
            now += DRAIN_MS
            onDrainSucceeded(now)
            recoveryTotalMs += now - stopAt

            check(state == UsbSessionState.IDLE) { "start/stop cycle $index did not return to IDLE (state=$state)" }
        }
        return recoveryTotalMs
    }

    /**
     * Runs [iterations] unplug -> replug recoveries and returns the total
     * simulated recovery time in milliseconds.
     *
     * One recovery is: detach, reap the cancelled URBs to IDLE, wait for USB
     * re-enumeration, then a fresh permission/admit/open/claim/configure/start.
     * "Recovery" is the detach to first-URB interval, i.e. how long audio is
     * gone. The permission grant is retained across the replug, so no dialog is
     * modelled. Each cycle is budgeted against [MAX_RECOVERY_MS].
     *
     * Entry is allowed from IDLE (a session is opened first) or from STREAMING
     * (the natural pre-unplug state); the machine is left in STREAMING.
     */
    fun simulateUnplugReplug(iterations: Int): Long {
        require(iterations >= 0) { "iterations must be >= 0, was $iterations" }
        if (state != UsbSessionState.IDLE && state != UsbSessionState.STREAMING) {
            throw IllegalStateException(
                "simulateUnplugReplug must be entered from IDLE or STREAMING, current state is $state"
            )
        }
        var now = lastTransitionMs
        if (state == UsbSessionState.IDLE) {
            now += PERMISSION_PROMPT_MS
            onPermissionRequested(now)
            now += PERMISSION_GRANT_MS
            onPermissionGranted(now)
            now += OPEN_MS
            onOpenSucceeded(now)
            now += CLAIM_MS
            onClaimSucceeded(now)
            now += CONFIGURE_MS
            onConfigureSucceeded(now)
            now += STREAM_START_MS
            onStreamStarted(now)
        }
        var recoveryTotalMs = 0L
        repeat(iterations) {
            now += PLAYBACK_MS
            val detachAt = now
            onDetached(now)
            now += URB_REAP_MS
            onDrainSucceeded(now)

            now += REPLUG_ENUMERATION_MS
            onPermissionRequested(now)
            now += PERMISSION_GRANT_MS
            onPermissionGranted(now)
            now += OPEN_MS
            onOpenSucceeded(now)
            now += CLAIM_MS
            onClaimSucceeded(now)
            now += CONFIGURE_MS
            onConfigureSucceeded(now)
            now += STREAM_START_MS
            onStreamStarted(now)
            recoveryTotalMs += now - detachAt
        }
        return recoveryTotalMs
    }

    // ---------------------------------------------------------------- internals

    private fun requireState(action: String, vararg allowed: UsbSessionState) {
        if (state !in allowed) {
            throw IllegalStateException(
                "$action is only valid from ${allowed.joinToString(", ")}, current state is $state"
            )
        }
    }

    private fun moveTo(next: UsbSessionState, nowMs: Long, action: String) {
        if (drainPending && next in DRAIN_BLOCKED) {
            throw IllegalStateException(
                "$action would enter $next with drainPending=true and " +
                    "$outstandingUrbCount outstanding URB(s); rebinding with live URBs is forbidden"
            )
        }
        previousState = state
        state = next
        lastTransitionMs = nowMs
        transitionCount++
        // Configuration validity is scoped to a single CONFIGURING stay.
        if (next != UsbSessionState.CONFIGURING) configureSucceeded = false
    }

    companion object {
        /** Isochronous URBs modelled per stream (two-buffer double buffering). */
        const val URBS_PER_STREAM: Int = 2

        /** Recovery budget for one simulated teardown cycle. */
        const val MAX_RECOVERY_MS: Long = 2_000L

        const val ERR_PERMISSION_DENIED: String = "permission_denied"
        const val ERR_DEVICE_DETACHED: String = "device_detached"
        const val ERR_DRAIN_INCOMPLETE: String = "drain_incomplete"

        // Deterministic timings for the simulators. They are deliberately
        // pessimistic for a UAC2 DAC on Android: a permission dialog answered
        // by the user, a 120 ms open, and a 180 ms drain.
        const val PERMISSION_PROMPT_MS: Long = 250L
        const val PERMISSION_GRANT_MS: Long = 60L
        const val OPEN_MS: Long = 120L
        const val CLAIM_MS: Long = 40L
        const val CONFIGURE_MS: Long = 60L
        const val STREAM_START_MS: Long = 30L
        const val PLAYBACK_MS: Long = 500L
        const val DRAIN_MS: Long = 180L
        const val URB_REAP_MS: Long = 120L
        const val REPLUG_ENUMERATION_MS: Long = 400L

        private val DRAIN_BLOCKED = setOf(
            UsbSessionState.OPENING,
            UsbSessionState.CLAIMING,
            UsbSessionState.CONFIGURING,
            UsbSessionState.STREAMING,
        )
    }
}
