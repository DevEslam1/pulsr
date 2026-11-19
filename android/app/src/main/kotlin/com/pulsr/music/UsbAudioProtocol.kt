package com.pulsr.music

/**
 * Clock programming with an optional Clock-Selector preference.
 *
 * This is the same contract as [UsbAudioProtocol.programPlaybackClock]; the
 * extra [preferredSelectorPin] is a *hint* from a per-device quirk profile and
 * never changes the default path: a `null` pin delegates straight to the
 * existing entry point, so every current caller keeps its exact behaviour.
 *
 * Semantics of a non-null hint:
 *
 *  * the clock the selector currently points at is still attempted first, so a
 *    device that already works is never re-pinned;
 *  * when that source cannot deliver [rate] and the topology has a multi-input
 *    Clock Selector, the preferred pin is tried before the generic scan;
 *  * a pin the selector does not expose, or whose clock entity is missing from
 *    the descriptor graph, is ignored and the existing scan runs unchanged;
 *  * the selector is put back on its original pin as soon as the preferred
 *    source is proven unusable, and again at the end of a failed scan. A
 *    restore that is refused twice is reported as
 *    [UsbAudioProtocol.RateSetResult.SELECTOR_RESTORE_FAILED], exactly like the
 *    default implementation, because the DAC is then clocked from a source that
 *    was just proven unusable.
 *
 * The scan therefore can only ever return one of the results the default
 * implementation already returns: a preferred pin never invents a new failure
 * code, and it can never leave the selector silently on the wrong source.
 */
internal fun UsbAudioProtocol.programPlaybackClock(
    transport: UsbControlTransfer,
    parsed: UsbAudioControlParser.Result,
    endpoint: Int,
    rate: Int,
    fixedUac1: Boolean,
    preferredSelectorPin: Int? = null,
): UsbAudioProtocol.RateSetResult {
    if (preferredSelectorPin == null) {
        return this.programPlaybackClock(transport, parsed, endpoint, rate, fixedUac1)
    }
    if (rate <= 0) return UsbAudioProtocol.RateSetResult.FAILED
    if (parsed.uacVersion != UsbAudioControlParser.UAC2) {
        // UAC1 has no clock entity, so a selector pin cannot apply: keep the
        // legacy endpoint path (and UAC3 is refused there, as before).
        return this.programPlaybackClock(transport, parsed, endpoint, rate, fixedUac1)
    }
    val selection = UsbAudioProtocol.resolveActiveClockSelection(transport, parsed)
        ?: return UsbAudioProtocol.RateSetResult.FAILED
    // The current clock is always attempted first. Validity is a
    // post-condition, never a pre-condition (an unprogrammed clock reports 0).
    attemptClockProgram(transport, selection.clock, endpoint, rate)?.let { return it }
    val selectorId = selection.selectorId ?: return UsbAudioProtocol.RateSetResult.FAILED
    val originalPin = selection.pin ?: return UsbAudioProtocol.RateSetResult.FAILED
    val interfaceNumber = selection.selectorInterface
        ?: parsed.clockSelectorInterfaces[selectorId]
        ?: parsed.controlInterface
    val inputs = parsed.clockSelectorInputs[selectorId] ?: return UsbAudioProtocol.RateSetResult.FAILED
    if (interfaceNumber < 0) return UsbAudioProtocol.RateSetResult.FAILED

    // Pins already proven unusable in this call. The original pin was just
    // attempted through its active clock; a pin that does not exist on this
    // selector is simply not in `inputs` and is skipped below.
    val tried = mutableSetOf(originalPin)
    if (preferredSelectorPin in 1..inputs.size && preferredSelectorPin != originalPin) {
        val preferredClock = parsed.clockSources
            .firstOrNull { it.clockId == inputs[preferredSelectorPin - 1] }
        if (preferredClock != null &&
            UsbAudioProtocol.setClockSelectorPin(
                transport, selectorId, interfaceNumber, preferredSelectorPin,
            )
        ) {
            tried += preferredSelectorPin
            attemptClockProgram(transport, preferredClock, endpoint, rate)?.let { return it }
            // The preferred source cannot carry the rate: restore the original
            // pin before the scan so the DAC is never left pointing at it.
            if (!UsbAudioProtocol.setClockSelectorPin(
                    transport, selectorId, interfaceNumber, originalPin,
                )
            ) {
                if (!UsbAudioProtocol.setClockSelectorPin(
                        transport, selectorId, interfaceNumber, originalPin,
                    )
                ) {
                    return UsbAudioProtocol.RateSetResult.SELECTOR_RESTORE_FAILED
                }
            }
        }
    }

    for ((pinIndex, inputId) in inputs.withIndex()) {
        val pin = pinIndex + 1
        if (pin in tried) continue
        val clock = parsed.clockSources.firstOrNull { it.clockId == inputId } ?: continue
        if (!UsbAudioProtocol.setClockSelectorPin(transport, selectorId, interfaceNumber, pin)) continue
        attemptClockProgram(transport, clock, endpoint, rate)?.let { return it }
    }

    if (UsbAudioProtocol.setClockSelectorPin(transport, selectorId, interfaceNumber, originalPin)) {
        return UsbAudioProtocol.RateSetResult.FAILED
    }
    // Retry once before reporting that the selector itself could not be put
    // back: the DAC is still on a dead source, which is a different failure.
    if (UsbAudioProtocol.setClockSelectorPin(transport, selectorId, interfaceNumber, originalPin)) {
        return UsbAudioProtocol.RateSetResult.FAILED
    }
    return UsbAudioProtocol.RateSetResult.SELECTOR_RESTORE_FAILED
}

/**
 * Program [rate] on [clock] and accept it only when the read-back matches
 * **and** the clock reports itself valid afterwards. Null means "this clock
 * cannot deliver the rate", which is what lets the caller try the next pin.
 */
private fun attemptClockProgram(
    transport: UsbControlTransfer,
    clock: UsbAudioControlParser.ClockSource,
    endpoint: Int,
    rate: Int,
): UsbAudioProtocol.RateSetResult? {
    val attempt = UsbAudioProtocol.setSampleRateWithResult(transport, 2, clock, endpoint, rate, false)
    if (!attempt.isSuccess) return null
    return if (UsbAudioProtocol.isClockValid(transport, clock)) attempt else null
}
