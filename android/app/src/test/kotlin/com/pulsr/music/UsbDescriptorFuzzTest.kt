// Deterministic descriptor fuzz for the UAC1/UAC2 parser.
//
// Gate 4 asks for 1,000,000 descriptor/control cases with no OOB, no crash and
// no invented capability. This test drives `UsbAudioControlParser.parse` with
// random byte arrays plus mutated valid prefixes and asserts the post-conditions
// the rest of the app relies on:
//   * every advertised rate is a positive, plausible audio rate;
//   * every alt setting exposes a sane subslot/resolution/channel count;
//   * interface numbers are non-negative when present.
//
// It is a plain JVM test (no Android framework) and uses a fixed seed, so a
// failure is reproducible from the printed case index.

package com.pulsr.music

import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class UsbDescriptorFuzzTest {

    private companion object {
        const val CASES = 1_000_000
        const val MAX_LEN = 192
    }

    @Test
    fun oneMillionDescriptorsStayWithinInvariants() {
        val random = Random(0x5EED_2026)
        val started = System.nanoTime()

        // A valid-ish UAC2 preamble: AC interface header, clock source, AS
        // interface + format + endpoint. Mutating it reaches the deep parser
        // paths far more often than pure noise.
        val seed = byteArrayOf(
            0x09, 0x02.toByte(), 0x40, 0x00, 0x02, 0x01, 0x00, 0x80.toByte(), 0x32,
            0x09, 0x04, 0x00, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00,
            0x08, 0x24, 0x01, 0x00, 0x01, 0x1E, 0x00, 0x01,
            0x08, 0x24, 0x0A, 0x01, 0x01, 0x03, 0x03, 0x00,
            0x09, 0x04, 0x01, 0x00, 0x00, 0x01, 0x02, 0x00, 0x00,
            0x09, 0x04, 0x01, 0x01, 0x01, 0x01, 0x02, 0x00, 0x00,
            0x10, 0x24, 0x01, 0x01, 0x01, 0x01, 0x02, 0x03, 0x00,
            0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x07, 0x05, 0x01, 0x01, 0xC0.toByte(), 0x00, 0x01,
        )

        repeat(CASES) { index ->
            val bytes = when (index % 4) {
                0 -> ByteArray(random.nextInt(0, MAX_LEN + 1)) { random.nextInt(256).toByte() }
                1 -> {
                    val copy = seed.copyOf()
                    repeat(1 + random.nextInt(6)) {
                        val at = random.nextInt(copy.size)
                        copy[at] = random.nextInt(256).toByte()
                    }
                    // Random truncation exercises every "descriptor runs past
                    // the buffer" branch.
                    val keep = random.nextInt(0, copy.size + 1)
                    copy.copyOf(keep)
                }
                else -> {
                    val len = random.nextInt(1, 65)
                    ByteArray(len) { random.nextInt(256).toByte() }
                }
            }

            val result = UsbAudioControlParser.parse(bytes)

            for (rate in result.supportedRates) {
                assertTrue(
                    "case $index: implausible rate $rate",
                    rate in 8_000..1_536_000,
                )
            }
            for (format in result.altSettingFormats) {
                assertTrue(
                    "case $index: negative interface ${format.interfaceNumber}",
                    format.interfaceNumber >= 0,
                )
                assertTrue(
                    "case $index: subslot ${format.subslotSize}",
                    format.subslotSize in 1..4,
                )
                assertTrue(
                    "case $index: resolution ${format.bitResolution}",
                    format.bitResolution in 1..32,
                )
                assertTrue(
                    "case $index: channels ${format.channels}",
                    format.channels in 0..32,
                )
                for (rate in format.supportedRates) {
                    assertTrue(
                        "case $index: implausible alt rate $rate",
                        rate in 8_000..1_536_000,
                    )
                }
            }
            val streaming = result.streamingInterface
            if (streaming != null) {
                assertTrue("case $index: streaming iface $streaming", streaming in 0..255)
            }
        }

        val elapsedMs = (System.nanoTime() - started) / 1_000_000
        println("[PASS] $CASES descriptor cases in ${elapsedMs}ms")
    }
}
